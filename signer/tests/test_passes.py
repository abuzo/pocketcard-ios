import hashlib
import io
import json
import subprocess
import zipfile
from dataclasses import replace
from datetime import datetime, timedelta, timezone

import pytest
from PIL import Image, PngImagePlugin
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from conftest import envelope, metadata, png, PASS_TYPE
from pocketcard_signer.models import parse_envelope, InputError
from pocketcard_signer.passes import build_assets, build_archive
from pocketcard_signer.signing import PassSigner, SigningError


def parse(meta=None, image=None): return parse_envelope(json.dumps(envelope(meta, image)).encode())


def test_info_has_no_photo_assets_and_complete_back_values(settings):
    meta=metadata(); meta["fields"][0]["value"]="я"*81
    assets=build_assets(parse(meta),settings)
    body=json.loads(assets["pass.json"])
    assert "posterGeneric" not in body
    assert not any(n.startswith(("thumbnail", "artwork")) for n in assets)
    assert body["generic"]["secondaryFields"][0]["value"] == "См. подробности"
    assert any(f["value"] == "я"*81 for f in body["generic"]["backFields"])
    assert body["passTypeIdentifier"] == PASS_TYPE
    assert body["serialNumber"] == meta["id"]
    assert "webServiceURL" not in body and "authenticationToken" not in body


def test_photo_has_poster_and_classic_with_unique_field_keys(settings):
    assets=build_assets(parse(metadata("mixed"),png()),settings)
    body=json.loads(assets["pass.json"])
    assert "posterGeneric" in body and "generic" in body
    for style in ("posterGeneric","generic"):
        keys=[f["key"] for group in body[style].values() for f in group]
        assert len(keys) == len(set(keys))
    assert Image.open(io.BytesIO(assets["artwork@3x.png"])).size == (1074,1344)
    assert Image.open(io.BytesIO(assets["thumbnail@3x.png"])).size == (270,270)


def test_image_metadata_removed(settings):
    im=Image.new("RGB", (60,80)); out=io.BytesIO(); info=PngImagePlugin.PngInfo(); info.add_text("Location", "secret GPS")
    im.save(out,"PNG", pnginfo=info)
    for name, data in build_assets(parse(metadata("photo"),out.getvalue()),settings).items():
        if name.endswith(".png"):
            assert not Image.open(io.BytesIO(data)).info


def test_invalid_or_huge_image_is_rejected(settings):
    with pytest.raises(InputError): build_assets(parse(metadata("photo"),b"not an image"), settings)
    # Header dimension check rejects before the decompressor attempts a full decode.
    with pytest.raises(InputError): build_assets(parse(metadata("photo"),png((3000,3000))), settings)


def test_png_must_not_be_an_animated_image(settings):
    a=Image.new("RGB",(40,40)); b=Image.new("RGB",(40,40),(255,0,0)); out=io.BytesIO()
    a.save(out,"PNG",save_all=True,append_images=[b],duration=100,loop=0)
    with pytest.raises(InputError): build_assets(parse(metadata("photo"),out.getvalue()),settings)


def test_manifest_and_detached_cms_verified_by_openssl(settings,tmp_path):
    parsed=parse(); signer=PassSigner(settings)
    package=build_archive(parsed,settings,signer)
    with zipfile.ZipFile(io.BytesIO(package)) as z:
        assert z.testzip() is None
        manifest=z.read("manifest.json")
        entries=json.loads(manifest)
        assert set(entries)==set(z.namelist())-{"manifest.json","signature"}
        for name, digest in entries.items(): assert hashlib.sha1(z.read(name)).hexdigest()==digest
        (tmp_path/"manifest").write_bytes(manifest); (tmp_path/"signature").write_bytes(z.read("signature"))
    result=subprocess.run(["openssl","cms","-verify","-binary","-inform","DER","-in",str(tmp_path/"signature"),
                           "-content",str(tmp_path/"manifest"),"-CAfile",str(settings.root_path),"-purpose","any","-out",str(tmp_path/"verified")],capture_output=True)
    assert result.returncode==0, result.stderr
    assert (tmp_path/"verified").read_bytes()==manifest
    (tmp_path/"manifest").write_bytes(manifest+b" ")
    result=subprocess.run(["openssl","cms","-verify","-binary","-inform","DER","-in",str(tmp_path/"signature"),
                           "-content",str(tmp_path/"manifest"),"-CAfile",str(settings.root_path),"-purpose","any"],capture_output=True)
    assert result.returncode != 0


def test_wrong_pass_type_team_and_key_are_rejected(settings,tmp_path):
    for s in (replace(settings,pass_type_identifier="pass.test.wrong"),replace(settings,team_identifier="WRONGTEAM1")):
        with pytest.raises(SigningError): PassSigner(s)
    other=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    path=tmp_path/"other.pem"; path.write_bytes(other.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    with pytest.raises(SigningError): PassSigner(replace(settings,key_path=path))


def test_certificate_validity_rechecked_at_each_signature(settings):
    signer=PassSigner(settings)
    with pytest.raises(SigningError): signer.sign(b"{}", now=datetime.now(timezone.utc)+timedelta(days=5))


def test_missing_certificate_fails_closed(settings):
    with pytest.raises(SigningError): PassSigner(replace(settings,certificate_path=settings.certificate_path.parent/"absent"))


def test_trusted_root_chain_required(settings,tmp_path,material):
    # Treating the leaf as a trust root must fail CA checks.
    with pytest.raises(SigningError): PassSigner(replace(settings,root_path=settings.certificate_path))


def test_token_never_in_pass_or_image(settings):
    assets=build_assets(parse(metadata("photo"),png()),settings)
    assert not any(settings.token.encode() in data for data in assets.values())


def test_receipt_contains_expected_team_for_companion_app(settings):
    body=json.loads(build_assets(parse(),settings)["pass.json"])
    assert body["userInfo"]["teamIdentifier"] == settings.team_identifier
