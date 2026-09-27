#!/usr/bin/env python3
"""Compile real Swift model, encode synthetic metadata, validate it with the real Python signer."""
import base64
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'signer'))
from pocketcard_signer.models import parse_envelope  # noqa: E402
from PIL import Image  # noqa: E402


def main():
    binary = ROOT / '.build/wire-contract-fixture'
    binary.parent.mkdir(parents=True, exist_ok=True)
    sources = sorted((ROOT / 'Sources/PocketCardCore').glob('*.swift'))
    subprocess.run(['swiftc', *map(str, sources), str(ROOT / 'scripts/fixtures/ContractFixture.swift'), '-o', str(binary)], check=True)
    output = subprocess.check_output([str(binary)]).splitlines()
    image = io.BytesIO(); Image.new('RGB', (40,50), 'gray').save(image, 'JPEG')
    templates = set()
    for data in output:
        obj = json.loads(data)
        photo = image.getvalue() if obj['includesImage'] else b''
        envelope = dict(metadata=data.decode(), imageBase64=base64.b64encode(photo).decode() if photo else None,
                        contentHash=hashlib.sha256(data+b'\0'+photo).hexdigest())
        actual = parse_envelope(json.dumps(envelope).encode())
        assert actual.metadata.title == 'Тест 🏖️ / Фото'
        if actual.metadata.template == 'photo': assert actual.metadata.fields == []
        else: assert actual.metadata.fields[0].value == '0001\nВторая строка'
        if actual.metadata.template == 'information': assert actual.metadata.caption is None and actual.image is None
        else: assert actual.image == image.getvalue()
        templates.add(actual.metadata.template)
    assert templates == {'photo','information','mixed'}
    print('Swift → Python wire contract: all 3 templates, Unicode, leading zeros, hidden-data filtering and exact-byte hashes passed.')


if __name__ == '__main__': main()
