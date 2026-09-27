"""One-installation MVP service. Run one worker, behind authenticated TLS transport."""
from __future__ import annotations

import asyncio
import hmac
import threading
import time
from collections import deque

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

from .models import MAX_REQUEST, InputError, parse_envelope
from .passes import build_archive
from .signing import PassSigner, SignerSettings, SigningError


def create_app(settings: SignerSettings | None) -> FastAPI:
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None, redirect_slashes=False)
    signer = None
    if settings is not None:
        try: signer = PassSigner(settings)
        except SigningError: pass
    in_flight = threading.Lock()
    rate_lock = threading.Lock()
    attempts: deque[float] = deque()

    def error(status: int, code: str):
        return JSONResponse({"error": {"code": code}}, status_code=status, headers={"Cache-Control":"no-store"})

    @app.get("/health")
    async def health():
        return JSONResponse({"status":"ready" if signer else "unconfigured"}, headers={"Cache-Control":"no-store"})

    @app.post("/v1/passes")
    async def issue(request: Request):
        if settings is None or signer is None: return error(503,"signer_unavailable")
        authorization = request.headers.get("authorization", "")
        expected = "Bearer "+settings.token
        if len(authorization) > 512 or not hmac.compare_digest(authorization.encode(), expected.encode()):
            return error(401,"unauthorized")
        if request.headers.get("content-type", "").split(";",1)[0].strip().lower() != "application/json":
            return error(415,"unsupported_media_type")
        if request.headers.get("content-encoding", "identity").lower() != "identity":
            return error(415,"unsupported_media_type")
        now = time.monotonic()
        with rate_lock:
            while attempts and attempts[0] <= now-60: attempts.popleft()
            if len(attempts)>=10: return error(429,"rate_limited")
            attempts.append(now)
        if not in_flight.acquire(blocking=False): return error(429,"busy")
        handed_to_worker = False
        try:
            try:
                length = int(request.headers.get("content-length","0"))
                if length < 0: return error(400,"invalid_request")
                if length > MAX_REQUEST: return error(413,"request_too_large")
            except ValueError: return error(400,"invalid_request")
            async def read_body():
                data = bytearray()
                async for chunk in request.stream():
                    if len(data)+len(chunk)>MAX_REQUEST: raise InputError("request_too_large")
                    data.extend(chunk)
                return bytes(data)
            raw = await asyncio.wait_for(read_body(), timeout=15)
            def work():
                try:
                    return build_archive(parse_envelope(raw),settings,signer)
                finally:
                    in_flight.release()
            # Shield the worker: a client disconnect must not unlock concurrent signing early.
            task = asyncio.create_task(asyncio.to_thread(work))
            handed_to_worker = True
            def consume_exception(t):
                if not t.cancelled(): t.exception()
            task.add_done_callback(consume_exception)
            payload = await asyncio.shield(task)
            return Response(payload, media_type="application/vnd.apple.pkpass",
                            headers={"Cache-Control":"no-store", "Content-Disposition":'attachment; filename="PocketCard.pkpass"',
                                     "X-Content-Type-Options":"nosniff"})
        except InputError as e:
            return error(413 if e.code in {"request_too_large","metadata_too_large","pass_too_large"} else 422,e.code)
        except (TimeoutError, asyncio.TimeoutError): return error(408,"request_timeout")
        except SigningError: return error(503,"signer_unavailable")
        except Exception: return error(500,"issue_failed")
        finally:
            if not handed_to_worker: in_flight.release()
    return app


app = create_app(SignerSettings.from_environment())
