Pocket AI — Porcupine custom keyword file
==========================================

The wake word "Piti" needs a custom Porcupine keyword model file named:

    piti_android.ppn

placed in THIS directory (assets/porcupine/). It is not bundled because a
keyword model is trained per phrase in the (free) Picovoice Console:

  1. Sign up at https://console.picovoice.ai (free)
  2. Go to Porcupine -> Train a custom wake word
  3. Phrase: "Piti", platform: Android, language: English
  4. Download the .ppn file and rename it to piti_android.ppn
  5. Copy it into assets/porcupine/ and rebuild the app:
         flutter build apk --debug

Until the file exists, the Porcupine engine reports itself unavailable and
the app falls back to keyword spotting — which is honestly labeled in the
app and README as NOT a true wake-word detector.
