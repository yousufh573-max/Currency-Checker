# Development report — Banknote Assistant

Date: 2026-11-25 · Flutter 3.50.1 / Dart 3.14 · Python 3.12.10 · JDK 17 · AGP 9.3 / Gradle 9.5

## Status at a glance

| Area | Status |
|---|---|
| 7 UI screens (PDF pages 1–7) + Settings | Done. Verified on an Android 17 emulator (release APK) |
| Voice (EN + BN), TTS, echo prevention | Done. Parsers unit-tested; real STT/TTS ran on the emulator (TTS spoke; the emulator has no real microphone input) |
| Camera scanning, guidance, auto-capture | Done. Live preview and real frame guidance were verified on the emulator's virtual camera, not on a real banknote |
| Torn-ratio pipeline (server + on-device) | Done. Tested on synthetic images only |
| Session calculation, idempotency, SQLite | Done and tested |
| FastAPI backend (11 endpoints, Swagger) | Done, tested and smoke-run live |
| **Denomination recognition model** | **Not trained: there is no dataset.** The app and server report `model_not_installed` |
| Debug APK / release APK / AAB | **Built successfully** (`dist/`) |

## Test results (actually executed)

| Suite | Result |
|---|---|
| Flutter unit tests (parsers EN/BN, session ledger, eligibility, frame guidance, capture gate, torn estimator, engines, offline failure, SQLite repo) | **98 passed** |
| Flutter widget, flow and accessibility tests (incl. acceptance scenario 20 + 100 + torn 500 → 120, pay 70 → 50, summary shown and spoken; permission granted/denied; timeout/retry; low confidence; model missing; Android tap-target, label and contrast guidelines) | **13 passed** |
| Flutter total (`flutter test`) | **111 passed, 0 failed** |
| `flutter analyze` | No issues |
| Integration test on emulator (`integration_test/app_flow_test.dart`, real sqflite/path_provider) | **1 passed** |
| Backend pytest (vision, quality, torn ratio incl. rotation/shadow/finger/multiple notes/frame edge, API, idempotency, forged IDs, demo labelling) | **28 passed** |
| ML dataset tools (grouped split, leakage detection) | **2 passed** |
| Live backend smoke test (uvicorn) | `/health`, `/docs` (200), analyze → honest `model_not_installed` with real stage results |
| Manual emulator run, release APK | Welcome → scanner → analysis → result (accepted) → result (torn 500, not added); total ৳120; no crashes in logcat |

Not executed: TFLite inference (no model exists), testing with a real phone camera and real banknotes, and real speech recognition (the emulator has no microphone input).

## Bugs found and fixed during testing
* Pydantic copied the stages list, so the API returned no stages.
* Skin-toned print on notes (for example, the orange 50 Taka) was treated as fingers. Occluders are now limited to skin regions that touch the frame edge.
* A screen that never listened could stop the *next* screen's voice listening on dispose. Fixed with owner tokens.
* The summary screen modified a provider during `initState`.
* The payment dialog's text controller was disposed while the dialog was still closing.
* The result status pill overflowed on narrow screens, and button labels wrapped mid-word.
* Third-party libraries merged `READ_PHONE_STATE` and external-storage permissions into the manifest. Both are removed.
* Build issues: the `tflite_flutter` Kotlin/Java JVM-target mismatch was fixed in the root Gradle script, and `compileSdk` was raised to 37 (required by `permission_handler`).

## Backend status
Runs with `uvicorn app.main:app`. It provides input validation by magic bytes and size, in-memory decoding (no images on disk), timeouts, rate limiting in production, environment configuration, logging, and an SQLite session store with server-side `analysis_id`s, so clients cannot inject denominations. Without a model the backend still runs the real quality and torn-detection stages and reports that recognition is unavailable.

## Model training status
- Not trained, because no licensed Bangladeshi banknote dataset was available.
- The training, evaluation, export and install pipeline is complete: see `machine_learning/README.md`. The ONNX export is verified against PyTorch inside the export script.
- The training scripts could not be run here because PyTorch is not installed and there is no data.

## Missing dependencies and datasets
* A dataset of Bangladeshi banknotes (all 9 denominations, both sides, many physical notes), legally obtained.
* PyTorch, torchvision and ai-edge-torch, needed for training and TFLite export (`machine_learning/requirements.txt`).
* Android `cmdline-tools` is not installed. Because of this, Flutter prints *"failed to strip debug symbols"* after building the AAB. I checked the AAB with `llvm-readelf`: all native libraries are already stripped, so the AAB itself is fine. Installing cmdline-tools removes the message.
* A release keystore. Release builds are currently signed with the **debug key** and are not suitable for the Play Store.

## Changes made to this machine
* Flutter SDK cloned to `C:\Users\Yousuf\flutter`. PATH was not changed.
* Gradle installed NDK 28.2.13676358 and CMake 3.22.1 into the Android SDK during the first build.
* A Python venv was created at `backend/.venv`.
* The emulator `Medium_Phone_API_37.0` was booted with `-no-snapshot-save`, and the app was installed on it. The emulator was then shut down.

## Known limitations
* Recognition cannot work until a model is trained. Demo mode is scripted only and is clearly labelled.
* Torn-ratio accuracy has been measured on synthetic images (error under 6 percentage points), not on real notes. Run `evaluation/evaluate.py` once real data with `torn_ratio` annotations exists.
* Fold detection exists on the server only. On the device, folds may count as torn area, and some are flagged as uncertain.
* Live guidance uses luminance only. A plain, uniform background works best, and very busy backgrounds can confuse note localisation.
* The note dimensions used to compute expected aspect ratios are approximate. Verify them against Bangladesh Bank specifications (`NOTE_DIMENSIONS_MM`).
* The universal APK is about 77 MB because of TFLite and all ABIs. Use `flutter build apk --split-per-abi` for smaller per-device APKs.
* Speech recognition quality and Bengali TTS availability depend on the phone's installed Google speech services and voices. If Bengali TTS is missing, the app speaks in English.

## Commands

```bash
# Flutter (Windows path to the SDK installed here)
set PATH=C:\Users\Yousuf\flutter\bin;%PATH%
cd mobile
flutter pub get
flutter test
flutter test integration_test -d <device-id>
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
flutter run

# Backend
cd backend
.venv\Scripts\activate
python -m pytest -q
uvicorn app.main:app --host 0.0.0.0 --port 8000      # http://localhost:8000/docs

# ML (after collecting data)
cd machine_learning
python datasets/split_dataset.py datasets/bdt/manifest.csv
python datasets/validate_dataset.py datasets/bdt/manifest.csv
python training/train.py --manifest datasets/bdt/manifest.csv
python export/export_model.py --tflite --install
python evaluation/evaluate.py --manifest datasets/bdt/manifest.csv --model weights/banknote_classifier.onnx --labels weights/labels.json
```
