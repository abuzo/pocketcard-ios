import json
import pytest
from conftest import envelope, metadata, png
from pocketcard_signer.models import parse_envelope, InputError


def test_strings_preserve_unicode_and_leading_zeroes():
    parsed = parse_envelope(json.dumps(envelope()).encode())
    assert parsed.metadata.fields[0].value == "0000123"
    assert parsed.metadata.title == "Дом 🏠"


@pytest.mark.parametrize("change", [
    {"title": "x"*61}, {"revision": 0}, {"revision": True}, {"revision": 2**63},
    {"schemaVersion": 2}, {"unknown": "hidden"}, {"title": "  "}, {"title": "hi\0there"},
    {"template": "eventTicket"}, {"includesImage": "true"}, {"fields": []},
    {"caption": "Hidden text"}, {"includesImage": True}, {"id": "../../file"},
])
def test_invalid_metadata_is_rejected(change):
    meta = metadata(); meta.update(change)
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(meta)).encode())


def test_duplicate_field_ids_are_rejected():
    meta = metadata(); meta["fields"] *= 2
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(meta)).encode())


def test_photo_cannot_smuggle_fields():
    meta = metadata("mixed"); meta["template"] = "photo"
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(meta, png())).encode())


def test_information_cannot_smuggle_an_image():
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(image=png())).encode())


def test_photo_requires_image():
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(metadata("photo"))).encode())


def test_hash_is_exact_wire_bytes_not_reserialized_json():
    raw = json.dumps(metadata(), indent=2, ensure_ascii=False)
    parsed = parse_envelope(json.dumps(envelope(raw=raw)).encode())
    assert parsed.metadata_bytes == raw.encode()
    broken = envelope(raw=raw); broken["metadata"] += " "
    with pytest.raises(InputError): parse_envelope(json.dumps(broken).encode())


@pytest.mark.parametrize("raw", [b'{"metadata":"a","metadata":"b"}', b'\xff', b'[]', b'{"x":NaN}'])
def test_invalid_json_and_duplicate_keys(raw):
    with pytest.raises(InputError): parse_envelope(raw)


def test_duplicate_metadata_key():
    raw = json.dumps(metadata())[:-1] + ',"title":"duplicate"}'
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(raw=raw)).encode())


def test_unknown_outer_keys():
    body = envelope(); body["path"] = "/secret"
    with pytest.raises(InputError): parse_envelope(json.dumps(body).encode())


def test_limits_at_boundary():
    meta = metadata(); meta["title"] = "😀"*60
    meta["fields"][0]["value"] = "x"*2000
    parse_envelope(json.dumps(envelope(meta)).encode())
    meta["fields"][0]["value"] += "x"
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(meta)).encode())


def test_bad_base64_and_oversized_request():
    body = envelope(metadata("photo")); body["imageBase64"] = "not:base64"
    with pytest.raises(InputError): parse_envelope(json.dumps(body).encode())
    with pytest.raises(InputError): parse_envelope(b" "*(5*1024*1024+1))


def test_unpaired_surrogate_is_rejected():
    meta = metadata(); meta["title"] = "\ud800"
    with pytest.raises(InputError): parse_envelope(json.dumps(envelope(raw=json.dumps(meta))).encode())
