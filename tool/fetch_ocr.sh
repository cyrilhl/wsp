#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p web/ocr
fetch() {
  curl --fail --location --retry 3 "$1" --output "web/ocr/$2.download"
  mv "web/ocr/$2.download" "web/ocr/$2"
}
fetch https://unpkg.com/tesseract.js@4.0.2/dist/tesseract.min.js tesseract.min.js
fetch https://unpkg.com/tesseract.js@4.0.2/dist/worker.min.js worker.min.js
fetch https://unpkg.com/tesseract.js-core@4.0.2/tesseract-core.wasm.js tesseract-core.wasm.js
fetch https://unpkg.com/tesseract.js-core@4.0.2/tesseract-core.wasm tesseract-core.wasm
fetch https://tessdata.projectnaptha.com/4.0.0/eng.traineddata.gz eng.traineddata.gz
fetch https://unpkg.com/tesseract.js@4.0.2/LICENSE.md LICENSE-tesseract-js
fetch https://unpkg.com/tesseract.js-core@4.0.2/LICENSE LICENSE-tesseract-core
