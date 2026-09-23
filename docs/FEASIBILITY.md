# Flutter Web moisture-meter feasibility findings

Study date: 23 September 2026. Status: prototype implemented; desktop integration verified; physical-device and real-meter accuracy study pending.

## Conclusion

The selected packages can be integrated into a self-contained Flutter Web app with capture, cropped OCR, editable confirmation and local photo storage. The release app and actual Tesseract runtime successfully loaded and recognized a synthetic decimal image while the local origin server was stopped.

This establishes desktop integration feasibility only. It does **not** establish recognition accuracy on LCD/seven-segment moisture-meter displays, camera behavior on Android/iPhone, long-term retention, or production readiness. No real meter photographs or physical target phones were available in this workspace.

## Implementation and environment

- Flutter 3.47.5 stable, Dart 3.13.4; release JavaScript/CanvasKit build. Wasm dry-run passed, but a Wasm release was not tested.
- camera 0.12.1 (camera_web 0.3.5+6), flutter_tesseract_ocr 0.4.31, idb_shim 2.9.9.
- Tesseract.js and non-SIMD core 4.0.2, local English trained data; single-line numeric recognition; optional grayscale/contrast enhancement.
- Desktop browser actually exercised: Microsoft Edge 153 (Chromium 153), macOS; browser-reported UA `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 Edg/153.0.0.0`. UA OS identification is not a hardware inventory. Desktop Chrome itself was not exercised.
- Offline release approximately 58.7 MiB uncompressed, including engine variants, all Flutter assets, and approximately 18.5 MiB OCR assets. Initial asset transfer time over mobile networks is unmeasured.

## Evidence

| Check | Outcome |
| --- | --- |
| `flutter analyze` | Pass, no issues |
| `flutter test` | 7 tests passed: crop mapping, mirror normalization, numeric parsing, repository reopen, preview correction, duplicate-save prevention, failed-save retention, home/gallery navigation at 390 × 844 logical pixels |
| Release build | Pass; local engine/font assets, no runtime CDN requirement |
| JS adapter tests | 3 tests passed: worker reuse and serialization, worker reset/retry after failure and timeout |
| Service-worker test | 1 test passed: interrupted installation removes the incomplete new cache and preserves the previous cache |
| Desktop home/gallery | Rendered successfully; empty gallery loads through browser idb_shim |
| Offline readiness | Home and study page reached “Ready offline” |
| App reload with origin stopped | Home rendered from cache |
| OCR with origin stopped | Fresh study page loaded engine/data from cache and recognized `12.5` |
| Actual camera permission/capture/retake/rotation | Unverified on physical devices |
| Browser photo save/reopen with real images | Unverified; automated storage round trip uses idb_shim memory factory |
| Successful cache update across app versions | Lifecycle implemented; end-to-end browser update test pending |
| iPhone Safari / Android Chrome | Unverified |
| 30 real meter images / glare / seven-segment display accuracy | Unverified |

Desktop synthetic OCR observations (one generated black-on-white `12.5`, 600 × 160 pixels):

| Run | Recognized | Duration |
| --- | --- | ---: |
| First worker initialization + recognition, assets already cached | `12.5` | 871 ms |
| Subsequent call, worker reused | `12.5` | 94 ms |
| Fresh page/worker after origin server stopped | `12.5` | 748 ms |

These are individual smoke measurements, not representative statistics. No real-image accuracy, correction rate, or mobile median/p95 is claimed. The offline exercise removed the origin server; it did not disable every network interface or restart the browser process. Full disconnected cold browser launch remains a phone acceptance check.

## Remaining study protocol

Use the release build over trusted HTTPS, with one Android Chrome phone and one iPhone Safari phone. Record exact phone model, OS/browser versions, meter model and available storage. Use the same origin throughout each run.

1. Collect at least 30 **real** labeled meter crops, including decimal readings, clear front-on displays, dim light, glare and oblique angles. Include multiple readings and visible decimal positions. Manually double-check ground truth before OCR. Do not tune against or relabel failed outputs.
2. Open `/study.html`, reload for a fresh worker, enter device identification, select files named `12.5__condition_01.png` and run. Download results JSON. Run the same dataset on each phone. It compares original and enhanced versions; synthesis is excluded from real metrics.
3. Report exact numeric-value accuracy and fraction needing correction before user edits for each variant/device. Empty results and errors count as failures. Compare decimals without floating-point rounding; trailing zero precision differences alone are not numerical errors. Report sample counts, cold initialization-plus-recognition, warm median/p95, errors and raw outputs. The study page calculates these metrics; do not run the synthetic smoke first when measuring real cold initialization.
4. In the app, test camera permission denied/allowed, missing camera where possible, rear-camera preference, portrait/landscape, glare and close focus, background/resume, repeated captures, retake, manual correction, save and gallery detail. Verify crop boundaries against a marked target. Record capture-to-preview and capture-to-OCR latency separately.
5. Save multiple photos; reload, close/reopen, and verify image bytes/reading/timestamp remain associated correctly. Exercise quota/storage errors and ensure the preview remains recoverable. Repeat in private browsing and document its retention limitations.
6. Wait for “Ready offline,” close all app tabs, disable connectivity, reopen the HTTPS URL and perform capture → OCR → save → gallery → close/reopen. Verify no essential network dependency remains.
7. Interrupt initial caching, reconnect and retry. With a complete old installation, interrupt a new version download; confirm the old app still opens offline. Finish the new version, close all tabs and reopen; verify the new version and existing IndexedDB photos.

The study has no preset pass threshold. Its final recommendation must be based on measured accuracy, correction effort, latency and the intended retention requirements.

## Risks and boundaries

- Tesseract recognition of segmented displays is an empirical question. A valid-looking wrong number can pass syntax validation; explicit human confirmation remains necessary. The whitelist does not guarantee separation of adjacent numbers or preservation of faint decimal points.
- The web camera plugin lacks native focus-point/exposure controls and frame streaming. Quality depends on the browser camera implementation. This app recognizes a still crop, not live frames.
- The overlay covers the centered half-width and half-height of the actual aspect-preserved preview. That is 25% of its area. Front/non-rear captures are normalized because this version of camera_web mirrors their stored pixels.
- Offline caching and IndexedDB are browser-managed. Clearing site data, eviction and private browsing can remove records/assets. This is not a backup system.
- The gallery currently reads all records, including image bytes, into memory. This is acceptable for a bounded feasibility dataset, not validated for thousands of photographs. Production should paginate thumbnail metadata and fetch originals only on detail views.
- First visit needs the complete approximately 59 MiB cache before offline readiness. Mobile download/storage impact and worker initialization memory are not measured.
- Updates activate after all old app tabs close. A changed origin creates separate storage; use a stable origin for studies.
- No backend, remote OCR, automatic cloud backup, export/delete photo UI, native app packaging or production deployment is included.

## Primary references

- [camera_web platform requirements and limitations](https://pub.dev/packages/camera_web)
- [flutter_tesseract_ocr web bridge](https://pub.dev/packages/flutter_tesseract_ocr)
- [idb_shim documentation](https://pub.dev/documentation/idb_shim/latest/)
- [Flutter web service-worker guidance](https://docs.flutter.dev/platform-integration/web/faq)
- [Browser quotas, eviction and private browsing](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)
