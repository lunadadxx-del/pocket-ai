import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config.dart';
import 'openrouter_service.dart' show ApiException;

/// Android SpeechRecognizer wrapper (via the speech_to_text plugin).
///
/// One-shot command capture: [listenOnce] resolves with the final transcript
/// or null when nothing was recognized. Throws [ApiException] with
/// feature='Voice input', stage='stt' when recognition is unavailable.
class SttService {
  SttService();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    final available = await _speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    if (!available) {
      throw ApiException(
        feature: 'Voice input',
        stage: 'stt',
        message: 'Speech recognition is not available on this device.',
        likelyCause: 'missing Google voice services or recognizer disabled',
      );
    }
    _initialized = true;
  }

  Future<String?> listenOnce() async {
    await ensureInitialized();
    final completer = Completer<String?>();
    String? lastPartial;

    final started = await _speech.listen(
      onResult: (result) {
        lastPartial = result.recognizedWords;
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: AppConfig.sttListenFor,
        pauseFor: AppConfig.sttPauseFor,
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
    if (!started) {
      throw ApiException(
        feature: 'Voice input',
        stage: 'stt',
        message: 'Could not start the microphone listener.',
        likelyCause:
            'microphone in use by another component or '
            'RECORD_AUDIO permission missing',
      );
    }

    // Safety net: resolve even if the recognizer never reports a final result.
    Timer(AppConfig.sttListenFor + const Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        completer.complete(
          (lastPartial != null && lastPartial!.trim().isNotEmpty)
              ? lastPartial
              : null,
        );
      }
    });

    final text = await completer.future;
    await stop();
    if (text == null || text.trim().isEmpty) return null;
    return text.trim();
  }

  Future<void> stop() async {
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {
      // Best effort.
    }
  }
}
