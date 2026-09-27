"""Build only known Generic layouts. Nothing received is interpreted as a path or URL."""
from __future__ import annotations

import hashlib
import io
import json
import warnings
import zipfile

from PIL import Image, ImageDraw, ImageOps

from .models import InputError, ParsedRequest
from .signing import PassSigner, SignerSettings

THEMES = {"ocean": (19, 48, 74), "forest": (20, 62, 48), "plum": (66, 36, 71), "sand": (243, 232, 210)}
MAX_IMAGE_PIXELS = 4_000_000


def json_bytes(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()


def png_bytes(image: Image.Image) -> bytes:
    # Copy pixels into a new raster; Pillow otherwise carries some source metadata forward.
    clean = Image.new("RGB", image.size)
    clean.paste(image.convert("RGB"))
    output = io.BytesIO(); clean.save(output, "PNG", optimize=True)
    return output.getvalue()


def decode_image(data: bytes) -> Image.Image:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                w, h = image.size
                if image.format not in {"PNG", "JPEG"} or getattr(image, "n_frames", 1) != 1:
                    raise InputError("invalid_image")
                if w < 1 or h < 1 or w*h > MAX_IMAGE_PIXELS or max(w,h) > 4096:
                    raise InputError("invalid_image")
                image.load()
                oriented = ImageOps.exif_transpose(image)
                clean = Image.new("RGB", oriented.size, (255, 255, 255))
                if oriented.mode in ("RGBA", "LA") or "transparency" in oriented.info:
                    rgba = oriented.convert("RGBA"); clean.paste(rgba, mask=rgba.getchannel("A"))
                else: clean.paste(oriented.convert("RGB"))
                return clean
    except InputError:
        raise
    except Exception:
        raise InputError("invalid_image") from None


def build_assets(request: ParsedRequest, settings: SignerSettings) -> dict[str, bytes]:
    m = request.metadata
    back = [{"key": "pc_title_full", "label": "Название", "value": m.title}]
    if m.caption is not None: back.append({"key": "pc_caption", "label": "Подпись", "value": m.caption})
    back.extend({"key": "back_"+f.id, "label": f.label, "value": f.value} for f in m.fields)
    back.extend([
        {"key": "pc_issuer", "label": "Издатель", "value": settings.organization_name},
        {"key": "pc_contact", "label": "Контакт", "value": settings.contact},
        {"key": "pc_privacy", "label": "Важно", "value": "Карточка Wallet не является защищённым хранилищем паролей. Удаление в PocketCard не удаляет эту копию."},
    ])
    front = [{"key": "front_"+f.id, "label": f.label, "value": f.value if len(f.value)<=80 else "См. подробности"} for f in m.fields[:2]]
    background = THEMES[m.theme]
    dark = m.theme == "sand"
    def rgb(c): return f"rgb({c[0]}, {c[1]}, {c[2]})"
    body = dict(formatVersion=1, passTypeIdentifier=settings.pass_type_identifier,
                teamIdentifier=settings.team_identifier, serialNumber=m.id,
                organizationName=settings.organization_name, description="Личная карточка: "+m.title,
                logoText="PocketCard", backgroundColor=rgb(background),
                foregroundColor=rgb((30,35,40) if dark else (255,255,255)),
                labelColor=rgb((60,65,70) if dark else (226,235,245)),
                sharingProhibited=True,
                userInfo=dict(schemaVersion=1, pocketcardID=m.id, revision=m.revision, contentHash=request.content_hash, teamIdentifier=settings.team_identifier),
                generic=dict(primaryFields=[dict(key="pc_title",label="",value=m.title)], secondaryFields=front, backFields=back))
    if m.includesImage:
        body["posterGeneric"] = dict(headerFields=[dict(key="pc_title",label="",value=m.title)],
                                     primaryFields=front, backFields=back)
    assets = {"pass.json": json_bytes(body)}
    for scale, suffix in ((1,""),(2,"@2x"),(3,"@3x")):
        icon = Image.new("RGB", (29*scale,29*scale), background)
        draw = ImageDraw.Draw(icon)
        draw.rounded_rectangle((5*scale,6*scale,24*scale,23*scale), radius=3*scale, outline=(255,255,255) if not dark else (30,35,40), width=2*scale)
        draw.line((9*scale,12*scale,20*scale,12*scale), fill=(125,192,214), width=2*scale)
        assets[f"icon{suffix}.png"] = png_bytes(icon)
    if request.image is not None:
        image = decode_image(request.image)
        for scale, suffix in ((1,""),(2,"@2x"),(3,"@3x")):
            assets[f"thumbnail{suffix}.png"] = png_bytes(ImageOps.fit(image,(90*scale,90*scale),Image.Resampling.LANCZOS))
            assets[f"artwork{suffix}.png"] = png_bytes(ImageOps.fit(image,(358*scale,448*scale),Image.Resampling.LANCZOS))
    return assets


def build_archive(request: ParsedRequest, settings: SignerSettings, signer: PassSigner) -> bytes:
    assets = build_assets(request, settings)
    # SHA-1 is required by the Apple manifest format; the CMS signature uses SHA-256.
    manifest = json_bytes({name: hashlib.sha1(data).hexdigest() for name, data in assets.items()})
    assets["manifest.json"] = manifest
    assets["signature"] = signer.sign(manifest)
    output = io.BytesIO()
    with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(assets.items()):
            info = zipfile.ZipInfo(name, (2026,1,1,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o600 << 16
            package.writestr(info,data)
    result = output.getvalue()
    if len(result) > 12*1024*1024: raise InputError("pass_too_large")
    return result
