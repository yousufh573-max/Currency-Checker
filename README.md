# Banknote Assistant

An accessible Android app that helps blind and visually impaired people identify
Bangladeshi banknotes, estimate whether a note is torn, add up the money they
have, and check whether it is enough to pay — all by voice (English and বাংলা).

> **Important — read first**
> * **Recognition needs a trained model, and none is included.** No licensed
>   banknote dataset was available, so the app and server report
>   *"recognition model not installed"* and never guess a denomination.
>   Follow [`machine_learning/README.md`](machine_learning/README.md) to collect
>   data, train, evaluate and install a model.
> * A **Developer demo mode** (Settings → Recognition) returns a fixed, scripted
>   sequence so you can try the screens. It is labelled DEMO everywhere and must
>   never be used to count real money.
> * The app **only calculates cash amounts**. It does not detect counterfeits,
>   verify authenticity, transfer money, or confirm that a payment happened.
> * Torn thresholds (Good ≤ 5 %, Damaged ≤ 20 %, Too torn > 20 %) are app settings,
>   **not** Bangladesh Bank rules.

## What's inside

```
banknote-assistant/
├── mobile/            Flutter app (Riverpod, GoRouter, camera, speech_to_text, flutter_tts, Dio, sqflite, TFLite)
├── backend/           FastAPI server (OpenCV quality + torn analysis, ONNX classifier, SQLite sessions)
├── machine_learning/  dataset tools, training, evaluation, export (PyTorch → ONNX / TFLite)
├── design/            App design.pdf (UI reference)
├── docs/              API reference, development report
└── .github/workflows/ CI: tests + debug/release APK + AAB
```

### The seven screens (from `design/App design.pdf`)

| # | Screen | What it does |
|---|---|---|
| 1 | Welcome | Speaks instructions, listens for "Start" (or tap the mic pill), asks for permissions |
| 2 | Scanner | Live camera, yellow frame, spoken guidance (left/right/closer/farther/steady/light/one note), auto-capture when steady, torch |
| 3 | Analysis | Four stages; each tick appears only when that stage really finished; timeout → Retry/Rescan |
| 4 | Accepted note | Denomination, confidence, condition, torn ratio, "Added to total", current total |
| 5 | Rejected note | Red; "Not added to total" — spoken message always matches (fixes the PDF inconsistency) |
| 6 | Payment | Say the amount ("seventy taka", "একশ পঞ্চাশ টাকা") or type it; remaining or shortage |
| 7 | Summary | Totals, Scan Again (with confirmation), Exit, Repeat; session saved on the phone |

Voice commands (English / Bengali): Start/শুরু, Scan/স্ক্যান, Scan Next/পরের, Scan More/আরও,
Stop/থামুন, Finish/শেষ, Total/মোট, Undo/আনডু, Repeat/আবার বলুন, Scan Again/আবার স্ক্যান,
Exit/প্রস্থান, Confirm/হ্যাঁ, Cancel/বাতিল. Every voice action also has an on-screen button.

---

## Quick start (beginner friendly)

### A. Install the app on a phone (no coding)

1. Get `app-release.apk` (from `mobile/build/app/outputs/flutter-apk/` after building,
   or from the GitHub Actions run artifacts).
2. Copy it to the phone, open it, allow "install unknown apps" when asked.
3. Open **Banknote Assistant**, allow microphone and camera.
4. Until a model is installed, scanning will say the model is missing. To try the
   flow, open Settings (gear, top-right) → *Developer demo*.

### B. Build the app yourself

Requirements: Flutter (stable, tested with 3.50.1 / Dart 3.14), JDK 17, Android SDK
with platform **android-37** (`sdkmanager "platforms;android-37.0"`).

```bash
cd mobile
flutter pub get
flutter test                          # unit + widget + accessibility tests
flutter build apk --debug             # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release           # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release     # build/app/outputs/bundle/release/app-release.aab
flutter run                           # run on a connected phone (USB debugging on)
```

**Release signing:** create `mobile/android/key.properties` (never commit it):

```
storeFile=/absolute/path/to/release.jks
storePassword=…
keyAlias=…
keyPassword=…
```

Create a keystore with
`keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias banknote`.
Without `key.properties`, release builds are signed with the debug key — fine for
testing, not for the Play Store.

### C. Run the backend (optional — for server-based recognition)

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate            # Windows  (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
copy .env.example .env            # macOS/Linux: cp .env.example .env
python -m pytest -q               # backend tests
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Open `http://localhost:8000/docs` for Swagger. API reference: [`docs/API.md`](docs/API.md).

To use it from the phone: Settings → Recognition → **Server**, accept the disclosure
(photos are uploaded for analysis; the server keeps only the numeric result), enter
the URL. Release builds require **HTTPS**; debug builds may use `http://<PC-LAN-IP>:8000`.

### D. Train a model

See [`machine_learning/README.md`](machine_learning/README.md).

---

## How it works

**Recognition modes** (Settings → Recognition)

| Mode | Where | Notes |
|---|---|---|
| On this phone (default) | Dart quality + torn estimator, TFLite classifier | Fully offline; photos never leave the device |
| Server | FastAPI | Requires explicit consent; HTTPS in release |
| Developer demo | Scripted | Labelled DEMO on every screen and in speech |

**Torn ratio.** The note is segmented from the background (shadows and fingers that
enter from the frame edge are excluded), its expected rectangle is found from the convex
hull (extrapolated with the denomination's aspect ratio if an end is missing), the
image is perspective-corrected, and

`torn % = (expected area − remaining note area) / expected area × 100`.

If the expected area can't be estimated reliably (note cut off by the frame, two notes,
finger over the note, folded corner, busy background) the result is **uncertain** and
the note is not counted.

**Counting.** Each capture gets a unique ID (idempotency key). The same capture can never
be counted twice; two different notes of the same value are both counted; after an
automatic capture the note must leave the frame before the next automatic capture.
Rejected and uncertain notes are listed separately and never added.

**Voice.** Speech recognition pauses while the app speaks and ignores anything heard
within 0.7 s after speech (so the app never "hears itself"); listening stops when the
app is backgrounded; repeated silence backs off to save battery.

**Accessibility.** TalkBack labels and live regions on every control and status, logical
order, ≥ 48 dp targets (most 64–110 dp), high-contrast text, haptics (different patterns
for added / not added), font scaling up to 180 %, status never conveyed by colour alone,
and a manual alternative for every voice action.

**Privacy & security.** No images are stored: captures live in the app's private cache and
are deleted after the next scan, at session end and at app start. Sessions store only
amounts. No backup/cloud transfer of app data. Release builds block cleartext HTTP. The
server validates uploads by magic bytes and size, decodes in memory, stores only numbers,
rate-limits in production, and refuses `DEMO_MODE` in production. No API keys are embedded
in the app.

## Tests

| Suite | Command |
|---|---|
| Flutter (unit, widget, flow, accessibility) | `cd mobile && flutter test` |
| On-device integration | `cd mobile && flutter test integration_test` (needs a phone/emulator) |
| Backend | `cd backend && python -m pytest -q` |
| Dataset tools | `cd machine_learning && python -m pytest -q tests` |

See [`docs/DEVELOPMENT_REPORT.md`](docs/DEVELOPMENT_REPORT.md) for current results and known limitations.
