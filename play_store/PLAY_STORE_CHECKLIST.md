# Play Store upload checklist

## Upload-ready files

| File | Notes |
|---|---|
| `banknote-assistant-1.0.0-1.aab` | Signed with the **upload key**, versionName 1.0.0, versionCode 1, package `com.banknoteassistant.app`, targetSdk 36, minSdk 26 |
| `graphics/icon-512.png` | Store icon |
| `graphics/feature-graphic-1024x500.png` | Feature graphic |
| `graphics/screenshots/*.png` | Phone screenshots (1080×2160) |
| `STORE_LISTING.md` | Listing text, content rating, data safety answers |
| `PRIVACY_POLICY.md` | Host it publicly and add your contact email |

## Upload key — back it up now
- Keystore: `C:\Users\Yousuf\.android-keys\banknote-assistant-upload.jks`
- Passwords and alias: `mobile/android/key.properties`. This file is git-ignored and is never committed.
- SHA-256 fingerprint: `91:84:03:3A:37:17:8A:9E:8D:0B:DB:B7:A5:2B:A6:8B:58:45:2C:06:4B:31:DA:19:D7:06:B1:A7:CC:5E:C0:9D`

Copy the `.jks` file **and** the passwords to a password manager or other safe backup. With
**Play App Signing**, which is the default for new apps, Google holds the final signing key and
this file is only the *upload* key. If you lose it, Play support can reset it, but that takes days.

For CI releases, add these GitHub secrets:
- `ANDROID_KEYSTORE_BASE64`: run `base64 -w0 banknote-assistant-upload.jks`
- `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD`: the password from `key.properties`
- `ANDROID_KEY_ALIAS`: `upload`

## ⚠️ Blocker for a public (production) release
No denomination recognition model is bundled. The app reports "recognition model not
installed" and cannot identify notes. Publishing it to production as a banknote reader would
very likely be rejected under Google Play's **Minimum Functionality** and **Deceptive Behavior**
policies, and it would fail its users.

Before production:
1. Collect data, then train, evaluate and install a model (`machine_learning/README.md`). Copy
   the `.tflite` and `labels.json` into `mobile/assets/models/`.
2. Set `MIN_CONFIDENCE` from the evaluation threshold sweep.
3. Test with real notes on several phones, preferably with blind and low-vision users.
4. Increase the version in `mobile/pubspec.yaml` (for example `1.0.1+2`) and rebuild the AAB.
5. Retake the screenshots showing real results.

You **can** upload this AAB now to the **Internal testing** track, which has no review
requirement for content, to check installation, signing and the Play pre-launch report.

## New personal developer accounts
Google requires personal accounts created after November 2023 to run a **closed test with at
least 12 testers for 14 continuous days** before applying for production access. Plan that
test once the model is installed.

## Steps in Play Console
1. **Create app:** name "Banknote Assistant", app, free, then accept the declarations.
2. **Set up your app:** complete every *App content* section using `STORE_LISTING.md`.
3. **Store listing:** fill in the text and graphics.
4. **Testing → Internal testing → Create release:** upload the `.aab`. Accept Play App Signing
   when asked, add release notes, then roll out.
5. Add testers by email list, install from the opt-in link, and review the **pre-launch report**.

## Rebuilding the AAB
```bash
cd mobile
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab (signed via android/key.properties)
```

Flutter may print "failed to strip debug symbols" at the end of the build. That happens because
Android `cmdline-tools` is not installed. The AAB is still created and its native libraries are
stripped. To remove the message, install the tools with Android Studio → SDK Manager →
"Android SDK Command-line Tools".
