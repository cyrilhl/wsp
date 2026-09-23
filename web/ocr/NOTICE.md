# Vendored OCR assets

- Tesseract.js 4.0.2: https://github.com/naptha/tesseract.js/tree/v4.0.2 (Apache-2.0; accompanying LICENSE-tesseract-js).
- Tesseract.js-core 4.0.2: https://github.com/naptha/tesseract.js-core (Apache-2.0; accompanying LICENSE-tesseract-core).
- English trained data: https://tessdata.projectnaptha.com/4.0.0/eng.traineddata.gz (Tesseract language data, Apache-2.0).
- Runtime uses the non-SIMD core for broad mobile compatibility.

See tool/fetch_ocr.sh to reproduce downloads. SHA256SUMS records the exact downloaded artifacts used in this study.
