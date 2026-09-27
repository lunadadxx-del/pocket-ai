# Pocket AI

A voice-first Android AI assistant. Say **“Piti”**, speak a command, hear the
confirmed result.

Day 1 of the 30-day daily build challenge.

## What it does

```
"Piti" → wake → listen → "Open YouTube" → AI understands →
Android opens YouTube → "YouTube is open."
```

Pipeline: **wake word → STT (Android SpeechRecognizer) → OpenRouter
(Google Gemma 4 31B IT) → Android action → Deepgram Flux TTS → spoken reply.**

Core rule: **nothing is faked.** The assistant speaks only what Android
confirmed. Failures are reported with the real error — never hidden behind
"something went wrong."

## Setup

### 1. Prerequisites

- Flutter SDK 3.47+ (`flutter doctor` should show Android toolchain green)
- Android SDK with platform 36 and build-tools 36
- A physical Android device (no emulator mic testing was possible here)

### 2. Get the code and dependencies

```bash
git clone <this-repo>
cd pocket-ai
flutter pub get
```

### 3. Wake-word keyword file (required for true hands-free)

Porcupine ships no built-in "Piti" model, so train one free:

1. Sign up at https://console.picovoice.ai (free)
2. Porcupine → train a custom wake word: phrase **"Piti"**, platform **Android**
3. Download the `.ppn` file, rename to `piti_android.ppn`
4. Put it in `assets/porcupine/` and rebuild

Without it, the app falls back to keyword spotting, which the app labels
honestly as **not** a true wake-word detector.

### 4. API keys — entered in the app, never in the repo

Open the app → **Settings** and enter:

| Key | Used for | Where to get it |
|---|---|---|
| OpenRouter API key | AI brain (`google/gemma-4-31b-it`, verified via the public OpenRouter models endpoint) | openrouter.ai |
| Deepgram API key | Voice output (Flux TTS, `POST https://api.deepgram.com/v2/speak`, model `flux-kit-en`) | deepgram.com |
| Picovoice AccessKey | True on-device wake-word detection | console.picovoice.ai (free) |

Keys are stored in the **Android Keystore** via `flutter_secure_storage`.
They are never displayed in full, never logged, and never committed —
`.gitignore` excludes key material. For public distribution, put these keys
behind your own backend proxy instead of shipping them in the APK.

### 5. Build & run

```bash
flutter analyze        # must be clean
flutter build apk --debug
flutter install
```

Grant Microphone, Contacts, and Phone permissions when asked — each denial
is reported on the debug screen with what breaks because of it.

### Build status (2026-09-27)

| Step | Tag | Notes |
|---|---|---|
| `flutter pub get` | [WORKING] | 85 dependencies resolved. |
| `flutter analyze` | [WORKING] | Clean: "No issues found!". |
| `flutter build apk --debug` | [BLOCKED] | Gradle daemon IPC fails in this sandbox, then dependency downloads are blocked — see below. Not an app-code problem: no Dart/Kotlin compilation errors were reached. |

**Why the APK build is blocked here.** Two sandbox-environment issues, in order:

1. **Gradle daemon IPC broken pipe.** The Gradle client starts its daemon,
   connects over loopback TCP, and gets `Broken pipe` on the first write
   (`Could not dispatch a message to the daemon`). Root cause found via
   strace: the daemon binds an IPv6-mapped socket (`::ffff:127.0.0.1`) and
   the sandbox kernel routes that "loopback" connection via the external
   interface address, so the daemon never accepts it. Workaround that fixes
   IPC: force the JVM onto IPv4 —
   `org.gradle.jvmargs=... -Djava.net.preferIPv4Stack=true` plus
   `GRADLE_OPTS="-Djava.net.preferIPv4Stack=true"`. With this, the daemon
   handshake succeeds and the build proceeds to dependency resolution.
2. **Kotlin Gradle Plugin unreachable.** The build needs
   `org.jetbrains.kotlin:kotlin-gradle-plugin` (app + Flutter plugins) and
   `org.gradle.kotlin:gradle-kotlin-dsl-plugins` (Flutter's
   `flutter_tools/gradle` composite build). These live on Maven Central /
   the Gradle Plugin Portal. This sandbox's egress proxy serves the portal
   root and Central root but stalls (never responds) on every deeper
   artifact path, and the portal's S3 artifact bucket only serves its exact
   `/` listing — any key fetch hangs. Google Maven (`maven.google.com`)
   works fine, but the Kotlin plugin is not published there. Result: the
   plugin artifacts cannot be downloaded in this environment, so the build
   cannot proceed past plugin resolution. On a normal network
   (`flutter build apk --debug` with internet access) this step succeeds.

Reproduce the investigation with:
`./gradlew assembleDebug --no-daemon` in `android/`, plus
`curl -s -o /dev/null -w "%{http_code}\n"` against
`https://repo.maven.apache.org/maven2/junit/junit/4.13.2/junit-4.13.2.pom`
(hangs here; HTTP 200 on an open network).

## Capability matrix

Tags: `[WORKING]` verified · `[PARTIALLY WORKING]` works with limits ·
`[ERROR]` broken, see log · `[NOT TESTED]` implemented, not device-tested ·
`[BLOCKED]` not implemented / platform-blocked — claimed nowhere.

| Capability | Tag | Notes |
|---|---|---|
| Wake word "Piti" (Porcupine, on-device) | [NOT TESTED] | Implemented. Needs Picovoice key + custom `.ppn`. |
| Wake-word fallback (keyword spotting) | [NOT TESTED] | Honestly labeled: NOT a true wake-word detector. |
| Voice command capture (SpeechRecognizer) | [NOT TESTED] | Implemented; needs mic permission. |
| AI intent parsing (Gemma 4 31B via OpenRouter) | [NOT TESTED] | Implemented; needs API key. 429s reported verbatim. |
| Open app by voice | [NOT TESTED] | PackageManager label/package resolution. |
| Open Settings | [NOT TESTED] | Direct settings intent. |
| Call contact by name | [NOT TESTED] | Real contact lookup; 0/1/many-match handling; numbers never invented. |
| Set alarm | [NOT TESTED] | `AlarmClock.ACTION_SET_ALARM`; needs a clock app. |
| Multi-action commands | [NOT TESTED] | AI returns an ordered plan; each step verified before the next runs; reply only from verified results. |
| Voice reply (Deepgram Flux TTS) | [NOT TESTED] | `POST /v2/speak`; real errors surfaced. |
| Background (app not in foreground) | [NOT TESTED] | Foreground keep-alive service holds the process; OEM battery savers may still kill it. |
| Screen locked / screen off wake | [BLOCKED] | Not implemented. Android withholds mic audio on the lock screen without deeper exemptions — claimed nowhere. |
| Playing media, sending messages, web search | [BLOCKED] | Outside the action set; the AI says so honestly. |

The in-app **Status & debug** screen shows this matrix live, plus the
microphone owner, per-stage latency, and the timestamped event log.

## Known Android limitations (honest list)

- **One microphone owner at a time.** The wake engine releases the mic
  before STT starts and re-acquires it after TTS finishes (`MicArbiter`
  enforces this; violations throw instead of silently double-recording).
- **Background execution:** Android 8+ kills background mic access. The app
  runs a foreground service (with a persistent notification) while the wake
  engine is active to keep process priority. Aggressive OEM battery
  optimizers (Xiaomi, Samsung, etc.) can still kill it — the user must
  exempt Pocket AI from battery optimization.
- **Lock screen / screen off:** not supported in this build (see matrix).
- **Phone calls** use `ACTION_CALL` and need the Phone permission; without
  it the failure is reported, not faked.
- **Contact "Daddy" example:** resolved via `ContactsContract`. Exactly one
  match → call is placed. Several → the assistant asks which one. None →
  it says so. A number is never invented.

## How latency is measured

`LatencyTracker` times each stage with a real `Stopwatch` — nothing is
estimated:

`wake → stt → ai → action → tts → playback`

The debug screen renders the breakdown verbatim after every turn. Do not
optimize based on assumptions; measure a change against these numbers.

## Error reporting

Every failure carries **feature, stage, exact error, HTTP status, likely
cause, impact** — in the debug log and, in short spoken form, to the user.
HTTP 429 (rate limit) is reported as rate limiting with the retry
implication, never as a generic failure. If TTS itself fails, the real
error is logged and shown; the app never silently displays text while
pretending the voice reply worked.

## Project layout

```
lib/
  config.dart                 # public constants only — NO secrets
  main.dart                   # boot, permissions, tabs
  actions/android_actions.dart # MethodChannel wrapper (results are honest)
  services/
    api_key_store.dart        # flutter_secure_storage
    assistant_brain.dart      # turn orchestrator + honesty rules
    latency_tracker.dart      # per-stage Stopwatch timing
    mic_arbiter.dart          # single microphone owner enforcement
    openrouter_service.dart   # Gemma 4 31B intent parsing
    stt_service.dart          # Android SpeechRecognizer
    tts_service.dart          # Deepgram Flux TTS + playback
    wake_word_service.dart    # Porcupine (true) + labeled fallback
  screens/
    home_screen.dart          # branding, orb, listening state
    settings_screen.dart      # key entry, wake-word status
    debug_screen.dart         # matrix, latency, mic owner, log
android/                      # Kotlin: actions, contacts, calls, alarms,
                              # foreground keep-alive service
```
