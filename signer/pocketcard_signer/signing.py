"""CMS signing with identity, key, validity and a configured trust-chain check."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import NameOID


class SigningError(RuntimeError):
    def __init__(self): super().__init__("signer_unavailable")


@dataclass(frozen=True)
class SignerSettings:
    token: str = field(repr=False)
    pass_type_identifier: str
    team_identifier: str
    organization_name: str
    contact: str
    certificate_path: Path
    key_path: Path
    intermediate_path: Path
    root_path: Path
    key_password: bytes | None = field(default=None, repr=False)

    @classmethod
    def from_environment(cls) -> SignerSettings | None:
        names = ("PC_TOKEN", "PC_PASS_TYPE_ID", "PC_TEAM_ID", "PC_ORGANIZATION", "PC_CONTACT",
                 "PC_CERTIFICATE", "PC_PRIVATE_KEY", "PC_WWDR_CERTIFICATE", "PC_APPLE_ROOT_CERTIFICATE")
        if not all(os.environ.get(name) for name in names): return None
        return cls(token=os.environ["PC_TOKEN"], pass_type_identifier=os.environ["PC_PASS_TYPE_ID"],
                   team_identifier=os.environ["PC_TEAM_ID"], organization_name=os.environ["PC_ORGANIZATION"],
                   contact=os.environ["PC_CONTACT"], certificate_path=Path(os.environ["PC_CERTIFICATE"]),
                   key_path=Path(os.environ["PC_PRIVATE_KEY"]), intermediate_path=Path(os.environ["PC_WWDR_CERTIFICATE"]),
                   root_path=Path(os.environ["PC_APPLE_ROOT_CERTIFICATE"]),
                   key_password=os.environ["PC_KEY_PASSWORD"].encode() if os.environ.get("PC_KEY_PASSWORD") else None)


class PassSigner:
    def __init__(self, settings: SignerSettings):
        try:
            if not re.fullmatch(r"[A-Za-z0-9_\-]{32,256}", settings.token): raise SigningError()
            if not re.fullmatch(r"pass\.[A-Za-z0-9.-]{3,200}", settings.pass_type_identifier): raise SigningError()
            if not re.fullmatch(r"[A-Z0-9]{10}", settings.team_identifier): raise SigningError()
            for value in (settings.organization_name, settings.contact):
                if not value.strip() or len(value) > 200 or "\0" in value: raise SigningError()
            self.cert = self._certificate(settings.certificate_path)
            self.intermediate = self._certificate(settings.intermediate_path)
            self.root = self._certificate(settings.root_path)
            self.key = serialization.load_pem_private_key(settings.key_path.read_bytes(), settings.key_password)
            if not isinstance(self.key, (rsa.RSAPrivateKey, ec.EllipticCurvePrivateKey)): raise SigningError()
            if isinstance(self.key, rsa.RSAPrivateKey) and self.key.key_size < 2048: raise SigningError()
            fmt = serialization.PublicFormat.SubjectPublicKeyInfo
            if self.key.public_key().public_bytes(serialization.Encoding.DER, fmt) != self.cert.public_key().public_bytes(serialization.Encoding.DER, fmt):
                raise SigningError()
            self._identity(NameOID.USER_ID, settings.pass_type_identifier)
            self._identity(NameOID.ORGANIZATIONAL_UNIT_NAME, settings.team_identifier)
            for ca in (self.intermediate, self.root):
                if not ca.extensions.get_extension_for_class(x509.BasicConstraints).value.ca: raise SigningError()
            try:
                if self.cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca: raise SigningError()
            except x509.ExtensionNotFound:
                pass
            try:
                if not self.cert.extensions.get_extension_for_class(x509.KeyUsage).value.digital_signature: raise SigningError()
            except x509.ExtensionNotFound:
                pass
            self.cert.verify_directly_issued_by(self.intermediate)
            self.intermediate.verify_directly_issued_by(self.root)
            self.root.verify_directly_issued_by(self.root)
            self._validity(datetime.now(timezone.utc))
        except Exception:
            # Do not expose file paths, certificate details or passwords in API/log messages.
            raise SigningError() from None

    @staticmethod
    def _certificate(path: Path) -> x509.Certificate:
        data = path.read_bytes()
        return x509.load_pem_x509_certificate(data) if b"-----BEGIN CERTIFICATE-----" in data else x509.load_der_x509_certificate(data)

    def _identity(self, oid, expected: str):
        values = self.cert.subject.get_attributes_for_oid(oid)
        if len(values) != 1 or values[0].value != expected: raise SigningError()

    def _validity(self, now: datetime):
        for cert in (self.cert, self.intermediate, self.root):
            if not cert.not_valid_before_utc <= now < cert.not_valid_after_utc: raise SigningError()

    def sign(self, manifest: bytes, *, now: datetime | None = None) -> bytes:
        try:
            self._validity(now or datetime.now(timezone.utc))
            return (pkcs7.PKCS7SignatureBuilder().set_data(manifest)
                    .add_signer(self.cert, self.key, hashes.SHA256()).add_certificate(self.intermediate)
                    .sign(serialization.Encoding.DER, [pkcs7.PKCS7Options.DetachedSignature, pkcs7.PKCS7Options.Binary]))
        except Exception:
            raise SigningError() from None
