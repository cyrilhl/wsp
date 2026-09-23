#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import hashlib
root = Path('web/ocr')
for line in (root / 'SHA256SUMS').read_text().splitlines():
    expected, name = line.split('  ', 1)
    file = root / name
    if not file.exists() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'Missing/modified OCR asset: {name}. Restore using sh tool/fetch_ocr.sh.')
PY
flutter build web --release --no-web-resources-cdn
python3 tool/prepare_offline.py
