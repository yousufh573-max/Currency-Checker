# Google Play Console — copy-paste answers

## Main store listing

**App name** (30 characters max)
```
Banknote Assistant
```

**Short description** (80 characters max)
```
Voice-guided Taka note counting for blind and visually impaired users.
```

**Full description** (4000 characters max)
```
Banknote Assistant helps blind and visually impaired people handle Bangladeshi cash independently, using the phone camera and voice, without needing to look at the screen.

HOW IT WORKS
• Say "Start", or tap the large button, to begin.
• Hold one note in front of the camera. Spoken guidance tells you to move it left, right, closer or farther, to hold it steady, or to find better light. The photo is taken automatically when the note is steady.
• The app speaks the note's value and its condition, and keeps a running total.
• Say how much you need to pay, for example "70 Taka" or "সত্তর টাকা". The app tells you whether you have enough and how much will remain, or how much more you need.
• Hear a spoken summary at the end of the session.

DESIGNED FOR ACCESSIBILITY
• Full voice control in English and Bangla (বাংলা)
• Works with TalkBack: every button and status has a spoken label
• Large buttons, high-contrast text and support for large font sizes
• Different vibration patterns for counted and not-counted notes
• Every voice command also has an on-screen button

DAMAGED NOTES
The app estimates how much of a note is missing. Notes that are badly torn, folded, partly covered by fingers, or not clearly recognised are not added to your total, and the app tells you why.

PRIVATE BY DEFAULT
• Works on your phone. Photos are not uploaded and are deleted automatically.
• No account, no ads, no tracking.
• An optional server mode is available only after you explicitly agree.

IMPORTANT
Banknote Assistant only helps you count cash. It does not detect counterfeit notes, verify authenticity, or make payments. The condition thresholds are app settings, not Bangladesh Bank rules.
```
> ⚠️ Publish this description only once a trained recognition model is included in the build (see PLAY_STORE_CHECKLIST.md). Until then the app cannot identify notes, and this text would be misleading.

**App category:** Tools
**Tags:** Accessibility, Finance tools
**Contact email:** _your email_ · **Privacy policy URL:** see below

## Graphics (in `graphics/`)
| Asset | File | Requirement |
|---|---|---|
| App icon | `icon-512.png` | 512×512 PNG ✔ |
| Feature graphic | `feature-graphic-1024x500.png` | 1024×500 ✔ |
| Phone screenshots | `screenshots/01–03` | 2–8 images, 1080×2160 ✔ |

Take new screenshots of note results once a real model is installed. Do not use demo-mode screenshots in the store.

## Privacy policy URL
Upload `PRIVACY_POLICY.md` to a public web page, then paste its link. For example, once this branch is merged to `main`:
`https://github.com/yousufh573-max/Currency-Checker/blob/main/play_store/PRIVACY_POLICY.md`
Fill in the contact email first.

## App content (Policy → App content)

| Section | Answer |
|---|---|
| Ads | No, the app does not contain ads |
| App access | All functionality is available without special access (no login) |
| Target audience | 13+ (select 13–15, 16–17, 18+). This keeps the app outside the Designed for Families program |
| Content rating | Questionnaire category "Utility, Productivity, Communication, or Other". Answer **No** to every content question, giving rating Everyone / PEGI 3 |
| News app | No |
| Government app | No |
| Financial features | None. The app does not provide banking, payments or loans; it only counts cash |
| Health | No |
| COVID-19 | No |
| Accessibility API | The app does **not** use AccessibilityService. It works with TalkBack through standard labels |

## Data safety
These answers take a cautious, transparent approach.

**Does your app collect or share any of the required user data types?** Yes

| Data type | Collected | Shared | Processed ephemerally | Required/optional | Purpose |
|---|---|---|---|---|---|
| Audio → Voice or sound recordings | Yes | No | **Yes** | Optional (buttons work without it) | App functionality |
| Photos and videos → Photos | Yes (server mode only) | No | **Yes** | Optional (off by default) | App functionality |

- **Is all user data encrypted in transit?** Yes. Release builds allow HTTPS only.
- **Can users request that data be deleted?** Data is not retained. Local sessions can be deleted in Settings or by uninstalling the app.
- **Independent security review:** No.

Notes for the reviewer:
- Voice audio is processed by the Android system speech recognition service only while the app is listening.
- Photos stay on the device in the default mode. They leave the device only in user-enabled server mode, and only to the server the user configures.
- Counting history is stored only on the device.

## Permissions declarations
- **Camera, microphone:** standard runtime permissions. No special declaration is needed.
- **No** SMS, call log, location, background location, all-files access, or photo/media permissions are requested.
