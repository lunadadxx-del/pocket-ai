/// Central configuration for Pocket AI.
///
/// SECURITY: this file contains NO secrets. All API keys are entered by the
/// user in the app's Settings screen and stored with flutter_secure_storage.
/// Nothing here is a credential — only public endpoint URLs and model IDs.
class AppConfig {
  AppConfig._();

  static const String appName = 'Pocket AI';
  static const String assistantName = 'Piti';
  static const String wakeWordDisplay = '“Piti”';

  // --- AI brain (OpenRouter) ---
  // Model ID verified live on 2026-09-27 UTC via the public
  // https://openrouter.ai/api/v1/models endpoint (no key required).
  // Listed name there: "Google: Gemma 4 31B".
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String openRouterModelId = 'google/gemma-4-31b-it';
  // Free-tier variant of the same model (may be rate-limited):
  static const String openRouterModelIdFree = 'google/gemma-4-31b-it:free';

  // --- Voice (Deepgram Flux TTS) ---
  // Verified 2026-09-27 UTC from Deepgram docs: Flux TTS voices are served ONLY
  // on /v2/speak (batch REST). /v1/speak serves Aura voices only.
  // The `model` query param is REQUIRED on v2. Auth: `Authorization: Token <key>`.
  // Options go on the query string; the JSON body carries only {"text": ...}.
  static const String deepgramTtsUrl = 'https://api.deepgram.com/v2/speak';
  static const String deepgramTtsModel = 'flux-kit-en';
  static const String deepgramTtsEncoding = 'mp3';

  // --- Platform channels ---
  static const String actionsChannel = 'com.pocketai.pocket_ai/actions';

  // --- Wake word (Picovoice Porcupine) ---
  // "Piti" is a CUSTOM keyword. Porcupine ships no built-in "Piti" model, so
  // the user must generate one (free) in the Picovoice Console:
  //   1. Sign up at console.picovoice.ai (free)
  //   2. Porcupine -> Train custom wake word "Piti" for Android (English)
  //   3. Download the .ppn file, rename it to piti_android.ppn
  //   4. Place it at assets/porcupine/piti_android.ppn and rebuild the app
  // Until that file exists, the Porcupine engine reports itself unavailable
  // and the app uses the honestly-labeled keyword-spotting fallback instead.
  // (The fallback is NOT a true acoustic wake-word detector — see README.)
  static const String porcupineKeywordAsset =
      'assets/porcupine/piti_android.ppn';
  static const double porcupineSensitivity = 0.6;

  // --- Timeouts ---
  static const Duration sttListenFor = Duration(seconds: 10);
  static const Duration sttPauseFor = Duration(seconds: 3);
  static const Duration httpTimeout = Duration(seconds: 30);
}
