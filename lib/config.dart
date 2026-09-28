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
  // Text agent model (free tier; may be rate-limited).
  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String openRouterModelId = 'google/gemma-4-31b-it:free';

  // --- Voice output (OpenRouter TTS) ---
  // Text-to-speech goes through OpenRouter so a single API key powers both
  // the brain and the voice:
  //   POST https://openrouter.ai/api/v1/audio/speech
  //   Headers: Authorization: Bearer <OPENROUTER_KEY>,
  //            Content-Type: application/json
  //   Body: {"model": "deepgram/flux-tts:free",
  //          "input": "<text>", "voice": "flux-cole-en"}
  //   -> 200 with raw MP3 bytes, or JSON error.
  static const String openRouterTtsUrl =
      'https://openrouter.ai/api/v1/audio/speech';
  static const String openRouterTtsModel = 'deepgram/flux-tts:free';
  static const String openRouterTtsVoice = 'flux-cole-en';

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
