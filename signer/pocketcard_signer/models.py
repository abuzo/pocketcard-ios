"""A bounded, versioned wire contract. Error text intentionally contains no input."""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import re
from dataclasses import dataclass
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

MAX_REQUEST = 5 * 1024 * 1024
MAX_METADATA = 64 * 1024


class InputError(ValueError):
    def __init__(self, code: str = "invalid_request"):
        self.code = code
        super().__init__(code)


def _text(value: str, limit: int, required: bool = False) -> str:
    if len(value) > limit or "\0" in value or any(0xD800 <= ord(c) <= 0xDFFF for c in value):
        raise ValueError("invalid_text")
    if required and not value.strip():
        raise ValueError("empty_text")
    return value


def _uuid(value: str) -> str:
    if str(UUID(value)) != value:
        raise ValueError("invalid_id")
    return value


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class ExportField(StrictModel):
    id: str
    label: str
    value: str

    _id = field_validator("id")(_uuid)

    @field_validator("label")
    @classmethod
    def label_limit(cls, value: str) -> str: return _text(value, 40, True)

    @field_validator("value")
    @classmethod
    def value_limit(cls, value: str) -> str: return _text(value, 2000, True)


class ExportMetadata(StrictModel):
    schemaVersion: Literal[1]
    id: str
    revision: int = Field(ge=1, le=2**63-2)
    template: Literal["photo", "information", "mixed"]
    title: str
    caption: str | None = None
    fields: list[ExportField] = Field(max_length=10)
    theme: Literal["ocean", "forest", "plum", "sand"]
    includesImage: bool

    _id = field_validator("id")(_uuid)

    @field_validator("schemaVersion", mode="before")
    @classmethod
    def schema_is_integer(cls, value):
        if type(value) is not int: raise ValueError("invalid_schema")
        return value

    @field_validator("title")
    @classmethod
    def title_limit(cls, value: str) -> str: return _text(value, 60, True)

    @field_validator("caption")
    @classmethod
    def caption_limit(cls, value: str | None) -> str | None:
        return _text(value, 500) if value is not None else None

    @model_validator(mode="after")
    def template_projection(self):
        if self.includesImage != (self.template != "information"):
            raise ValueError("invalid_image_projection")
        if self.template == "information" and self.caption is not None:
            raise ValueError("hidden_caption")
        if self.template == "photo" and self.fields:
            raise ValueError("hidden_fields")
        if self.template != "photo" and not self.fields:
            raise ValueError("missing_fields")
        if len({field.id for field in self.fields}) != len(self.fields):
            raise ValueError("duplicate_fields")
        return self


class WireEnvelope(StrictModel):
    metadata: str
    imageBase64: str | None = None
    contentHash: str


@dataclass(frozen=True)
class ParsedRequest:
    metadata: ExportMetadata
    metadata_bytes: bytes
    image: bytes | None
    content_hash: str


def strict_json(data: bytes | str):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise InputError()
            result[key] = value
        return result
    def reject_constant(_): raise InputError()
    if isinstance(data, bytes): data = data.decode("utf-8", errors="strict")
    return json.loads(data, object_pairs_hook=unique, parse_constant=reject_constant)


def parse_envelope(raw: bytes) -> ParsedRequest:
    if len(raw) > MAX_REQUEST: raise InputError("request_too_large")
    try:
        envelope = WireEnvelope.model_validate(strict_json(raw))
        metadata_bytes = envelope.metadata.encode("utf-8", errors="strict")
        if len(metadata_bytes) > MAX_METADATA: raise InputError("metadata_too_large")
        metadata = ExportMetadata.model_validate(strict_json(metadata_bytes))
        image = base64.b64decode(envelope.imageBase64, validate=True) if envelope.imageBase64 is not None else None
        if metadata.includesImage != bool(image): raise InputError()
        if not metadata.includesImage and image is not None: raise InputError()
        if not re.fullmatch(r"[a-f0-9]{64}", envelope.contentHash): raise InputError()
        expected = hashlib.sha256(metadata_bytes + b"\0" + (image or b"")).hexdigest()
        if not hmac.compare_digest(envelope.contentHash, expected): raise InputError("content_mismatch")
        return ParsedRequest(metadata, metadata_bytes, image, expected)
    except InputError:
        raise
    except (ValueError, TypeError, UnicodeError, RecursionError, ValidationError, binascii.Error):
        raise InputError() from None
