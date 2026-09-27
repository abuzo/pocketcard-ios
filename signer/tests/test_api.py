import io
import json
import zipfile
from dataclasses import replace

from fastapi.testclient import TestClient
from conftest import TOKEN, envelope
from pocketcard_signer.api import create_app


def client(settings): return TestClient(create_app(settings))
def headers(): return {"Authorization": f"Bearer {TOKEN}"}


def test_auth_required_before_parsing_body(settings):
    c=client(settings)
    for h in ({}, {"Authorization":"Bearer incorrect"}):
        assert c.post("/v1/passes",content=b"SECRET malformed",headers=h).status_code==401


def test_success_content_type_and_no_store(settings):
    r=client(settings).post("/v1/passes",json=envelope(),headers=headers())
    assert r.status_code==200
    assert r.headers["content-type"]=="application/vnd.apple.pkpass"
    assert r.headers["cache-control"]=="no-store"
    assert zipfile.ZipFile(io.BytesIO(r.content)).testzip() is None


def test_error_never_echoes_fields_or_authorization(settings,caplog):
    raw="This-is-a-sensitive-invalid-input"
    r=client(settings).post("/v1/passes",content=raw,headers={**headers(),"Content-Type":"application/json"})
    assert r.status_code==422
    assert raw not in r.text+caplog.text and TOKEN not in r.text+caplog.text


def test_rate_limit(settings):
    c=client(settings)
    for _ in range(10):
        assert c.post("/v1/passes",json=envelope(),headers=headers()).status_code==200
    assert c.post("/v1/passes",json=envelope(),headers=headers()).status_code==429


def test_request_size_limit(settings):
    r=client(settings).post("/v1/passes",content=b"x"*(5*1024*1024+1),headers={**headers(),"Content-Type":"application/json"})
    assert r.status_code==413


def test_missing_signing_configuration_never_returns_fake_pass():
    c=TestClient(create_app(None))
    assert c.get("/health").json()=={"status":"unconfigured"}
    assert c.post("/v1/passes",json=envelope(),headers=headers()).status_code==503


def test_bad_certificate_fails_closed_but_health_safe(settings):
    s=replace(settings,team_identifier="WRONGTEAM1")
    c=TestClient(create_app(s))
    assert c.get("/health").json()=={"status":"unconfigured"}
    assert c.post("/v1/passes",json=envelope(),headers=headers()).status_code==503


def test_docs_and_unknown_paths_do_not_expose_schemas(settings):
    c=client(settings)
    assert c.get("/docs").status_code==404
    assert c.get("/openapi.json").status_code==404
    assert c.post("/v1/passes/",json=envelope(),headers=headers()).status_code==404


def test_wrong_content_type_rejected(settings):
    assert client(settings).post("/v1/passes",content=b"{}",headers=headers()).status_code==415


def test_one_in_flight_issue_and_lock_released(settings, monkeypatch):
    """Block one real package operation at the boundary; another request must not enter it."""
    import threading
    from concurrent.futures import ThreadPoolExecutor
    import pocketcard_signer.api as api
    started = threading.Event()
    release = threading.Event()
    original = api.build_archive

    def controlled(*args):
        started.set()
        assert release.wait(timeout=10), 'test worker did not get released'
        return original(*args)

    monkeypatch.setattr(api, 'build_archive', controlled)
    with client(settings) as c, ThreadPoolExecutor(max_workers=1) as executor:
        first = executor.submit(c.post, '/v1/passes', json=envelope(), headers=headers())
        try:
            assert started.wait(timeout=10), 'first request never entered signing'
            second = c.post('/v1/passes', json=envelope(), headers=headers())
            assert second.status_code == 429
            assert second.json()['error']['code'] == 'busy'
        finally:
            release.set()
        assert first.result(timeout=10).status_code == 200
        assert c.post('/v1/passes', json=envelope(), headers=headers()).status_code == 200


def test_invalid_request_releases_lock(settings):
    with client(settings) as c:
        invalid = c.post('/v1/passes', content=b'{', headers={**headers(), 'Content-Type': 'application/json'})
        assert invalid.status_code == 422
        assert c.post('/v1/passes', json=envelope(), headers=headers()).status_code == 200
