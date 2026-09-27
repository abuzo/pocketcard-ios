import base64
import hashlib
import io
import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from PIL import Image

PASS_TYPE = "pass.test.pocketcard"
TEAM = "TESTTEAM01"
TOKEN = "local-test-only-token-0123456789abcdef"


def metadata(template="information"):
    return dict(schemaVersion=1, id=str(uuid.uuid4()), revision=1, template=template,
                title="Дом 🏠", caption="Подпись" if template != "information" else None,
                fields=[] if template == "photo" else [dict(id=str(uuid.uuid4()), label="Код", value="0000123")],
                theme="ocean", includesImage=template != "information")


def png(size=(120, 160)):
    image = Image.new("RGB", size, (40, 80, 120))
    out = io.BytesIO(); image.save(out, "PNG")
    return out.getvalue()


def envelope(meta=None, image=None, raw=None):
    meta = meta if meta is not None else metadata()
    raw = raw if raw is not None else json.dumps(meta, ensure_ascii=False, separators=(",", ":"))
    return dict(metadata=raw, imageBase64=base64.b64encode(image).decode() if image is not None else None,
                contentHash=hashlib.sha256(raw.encode() + b"\0" + (image or b"")).hexdigest())


@pytest.fixture(scope="session")
def material():
    """Ephemeral test PKI only. These certificates are not Apple-issued."""
    now = datetime.now(timezone.utc)
    root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    root_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "PocketCard test root")])
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "PocketCard test intermediate")])
    subject = x509.Name([x509.NameAttribute(NameOID.USER_ID, PASS_TYPE),
                         x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, TEAM),
                         x509.NameAttribute(NameOID.COMMON_NAME, "PocketCard TEST ONLY")])
    def issue(name, pub, issuer, signing_key, ca):
        return (x509.CertificateBuilder().subject_name(name).issuer_name(issuer).public_key(pub)
                .serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=1))
                .not_valid_after(now+timedelta(days=2)).add_extension(x509.BasicConstraints(ca=ca, path_length=None), True)
                .sign(signing_key, hashes.SHA256()))
    root = issue(root_name, root_key.public_key(), root_name, root_key, True)
    intermediate = issue(ca_name, ca_key.public_key(), root_name, root_key, True)
    cert = issue(subject, key.public_key(), ca_name, ca_key, False)
    return key, cert, intermediate, root


@pytest.fixture
def settings(tmp_path, material):
    from pocketcard_signer.signing import SignerSettings
    key, cert, intermediate, root = material
    for name, obj in (("certificate.pem", cert), ("intermediate.pem", intermediate), ("root.pem", root)):
        (tmp_path/name).write_bytes(obj.public_bytes(serialization.Encoding.PEM))
    (tmp_path/"key.pem").write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                     serialization.NoEncryption()))
    return SignerSettings(token=TOKEN, pass_type_identifier=PASS_TYPE, team_identifier=TEAM,
                          organization_name="PocketCard test", contact="test@example.invalid",
                          certificate_path=tmp_path/"certificate.pem", key_path=tmp_path/"key.pem",
                          intermediate_path=tmp_path/"intermediate.pem", root_path=tmp_path/"root.pem")
