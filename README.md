# Fieldnote — Flutter Web moisture-meter study

A local-only prototype: camera → center crop → OCR → editable confirmation → IndexedDB photo gallery. Supports offline use after the release app finishes caching. No server API or photo uploads.

## Run

Validated toolchain: Flutter 3.47.5 / Dart 3.13.4. Keep `pubspec.lock`; the requested dependencies remain camera 0.12.1, flutter_tesseract_ocr 0.4.31 and idb_shim 2.9.9.

```sh
flutter pub get
sh tool/build_web.sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open http://localhost:8080. Wait for **Ready offline** before disconnecting. The checked-in OCR assets include English language data; restore missing assets with `sh tool/fetch_ocr.sh`. Build verifies their SHA-256 checksums. The full offline cache is approximately 59 MiB uncompressed.

For physical phones, serve `build/web` from a trusted **HTTPS** origin. A plain HTTP LAN address is not a secure camera context. Configure the server to serve `.wasm` as `application/wasm`, `.js` as JavaScript, and `meter-sw.js` with `Cache-Control: no-cache`. Do not add `Content-Encoding: gzip` to `eng.traineddata.gz`: Tesseract decompresses that file itself. Hosting/deployment is not configured by this project.

Development: `flutter run -d chrome`. Camera/OCR can run during development, but offline installation requires the prepared release build. If using the same origin for development and release, unregister the release worker in browser developer tools first; otherwise it may serve the cached release app.

## Flow

1. **Take photo:** align one numeric display with the centered landscape (2:1) rectangle over the full-screen camera preview.
2. **Preview:** inspect the full image. Check the decimal reading; edit it if needed. Contrast is enhanced automatically during OCR. Retry or retake if needed.
3. **Confirm & save:** commits photo, thumbnail, timestamp, raw OCR and confirmed reading together. Crops are used temporarily for OCR and are not saved. Failed saves retain the preview.
4. **View gallery:** newest first; tap a tile for the original photo, confirmed meter value and timestamp.

Use one decimal number with a dot, optionally negative. Display precision is preserved (`12.50` stays `12.50`). Empty or multi-token OCR results never become a guessed reading. Storage is specific to the browser/profile/origin and can be cleared or evicted. No backup, export of gallery photos, deletion UI or cross-device sync is included.

## Tests

```sh
flutter analyze
flutter test
sh tool/build_web.sh
node --test tool/web_tests.cjs
```

The Dart tests use an in-memory idb_shim factory, not browser IndexedDB. Browser and physical-device evidence and limitations are in [docs/FEASIBILITY.md](docs/FEASIBILITY.md).

## Collect real study results

Open http://localhost:8080/study.html (or the corresponding HTTPS URL).

- The synthetic `12.5` test verifies the real OCR worker integration, including offline loading. It is excluded from real accuracy statistics.
- For a real study, reload the page, enter the phone/OS/browser versions, and select at least 30 **viewfinder-cropped** meter photographs. File names encode ground truth, for example `12.5__glare_01.png` or `8__dim_03.jpg`.
- Run the study once per page session. It processes original and grayscale/contrast variants sequentially, retains all raw results, and offers a local JSON download. Photos are not uploaded or included in the JSON.
- Summary includes exact numeric-value accuracy before correction, corrections required, warm median/p95 and first-call initialization-plus-recognition time. `12.50` and `12.5` compare equal; distinct decimal values do not. Warm statistics exclude the initial call and errors. Synthetic tests should not precede a cold real-study run.
- The study times recognition on already cropped inputs. Record camera/cropping and end-to-end capture latency separately during physical-device testing.

## Implementation notes

`lib/services` separates image processing, OCR and IndexedDB. Images use bytes and Flutter Canvas; no `dart:io`. The camera preview fills the screen without stretching, cropping overflow at the edges. The centered landscape viewfinder is mapped back through that cover scaling to decoded image coordinates for OCR. Front/non-rear web captures are unmirrored before OCR and persistence.

`web/ocr_bridge.js` provides the JavaScript hook required by flutter_tesseract_ocr. It pins Tesseract.js/core 4.0.2, uses a reusable worker, serializes jobs and terminates failed/timed-out workers after a 60-second ceiling. Original and enhanced crops use single-line recognition with a numeric whitelist. The normalized original crop is kept in memory for OCR retries and is not stored or displayed. Older saved records remain readable; any previously stored crop is ignored.

`tool/prepare_offline.py` generates `meter-sw.js` from the release files, names the cache by content hash, and marks it complete only when all assets are cached. Failed installs delete only the incomplete new cache. Successful updates wait until all old app tabs close, then activate on the next visit. Old complete caches are removed only during activation. The app verifies cached entries through its controlling worker before reporting readiness. Keep the same origin to retain photos; application-cache updates do not delete IndexedDB records.

The study is intentionally small: the gallery currently loads all saved records. Benchmark memory with your intended photo count before production; larger galleries should paginate metadata/thumbnails and load original bytes on demand.
