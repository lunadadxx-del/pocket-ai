import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config.dart';
import 'openrouter_service.dart' show ApiException;

/// Which engine is actually listening for the wake word.
///
/// The distinction matters: only [porcupine] is a true on-device acoustic
/// wake-word detector. [keywordSpotting] is a plain STT + substring loop and
/// is NEVER presented as a true wake-word detector (spec rule).
enum WakeWordEngine { porcupine, keywordSpotting, unavailable }

extension WakeWordEngineLabel on WakeWordEngine {
  String get label => switch (this) {
    WakeWordEngine.porcupine =>
      'Porcupine (true on-device wake-word detection)',
    WakeWordEngine.keywordSpotting =>
      'Keyword spotting fallback — NOT a true wake-word detector',
    WakeWordEngine.unavailable => 'Wake word unavailable',
  };

  String get tag => switch (this) {
    WakeWordEngine.porcupine => '[WORKING]',
    WakeWordEngine.keywordSpotting => '[PARTIALLY WORKING]',
    WakeWordEngine.unavailable => '[BLOCKED]',
  };
}

abstract class WakeWordService {
  WakeWordEngine get engine;

  /// Emits the wall-clock time the wake word was detected, so the caller
  /// can measure wake -> command-handoff latency honestly.
  Stream<DateTime> get onWakeWord;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
  bool get isRunning;
}

/// True on-device wake-word detection via Picovoice Porcupine.
///
/// Requires:
///  1. A free Picovoice AccessKey entered in Settings.
///  2. A custom "Piti" keyword file (.ppn) trained in the Picovoice Console
///     and placed at assets/porcupine/piti_android.ppn (see config.dart).
/// If either is missing, [start] throws an [ApiException] explaining exactly
/// what is missing and the caller must fall back honestly.
class PorcupineWakeWordService implements WakeWordService {
  PorcupineWakeWordService({required this.accessKey});

  final String accessKey;
  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  PorcupineManager? _manager;
  bool _running = false;

  @override
  WakeWordEngine get engine => WakeWordEngine.porcupine;

  @override
  Stream<DateTime> get onWakeWord => _controller.stream;

  @override
  bool get isRunning => _running;

  Future<void> _ensureManager() async {
    if (_manager != null) return;
    // The custom keyword file must be bundled by the user (see config.dart).
    try {
      await rootBundle.load(AppConfig.porcupineKeywordAsset);
    } catch (_) {
      throw ApiException(
        feature: 'Wake word',
        stage: 'wake',
        message:
            'Custom "Piti" keyword file missing: '
            '${AppConfig.porcupineKeywordAsset} is not bundled.',
        likelyCause:
            'train "Piti" in the Picovoice Console and add the '
            '.ppn file to assets/porcupine/, then rebuild',
      );
    }
    if (accessKey.isEmpty) {
      throw ApiException(
        feature: 'Wake word',
        stage: 'wake',
        message: 'Picovoice AccessKey is not set.',
        likelyCause: 'enter the free key in Settings',
      );
    }
    try {
      _manager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        [AppConfig.porcupineKeywordAsset],
        (_) {
          if (!_controller.isClosed) _controller.add(DateTime.now());
        },
        sensitivities: [AppConfig.porcupineSensitivity],
      );
    } on PorcupineException catch (e) {
      throw ApiException(
        feature: 'Wake word',
        stage: 'wake',
        message: 'Porcupine failed to initialize: ${e.message}',
        likelyCause: 'invalid access key or incompatible keyword file',
      );
    }
  }

  @override
  Future<void> start() async {
    await _ensureManager();
    if (_running) return;
    try {
      await _manager!.start();
      _running = true;
    } on PorcupineRuntimeException catch (e) {
      throw ApiException(
        feature: 'Wake word',
        stage: 'wake',
        message: 'Porcupine could not capture audio: ${e.message}',
        likelyCause:
            'microphone held by another component or '
            'RECORD_AUDIO permission missing',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    try {
      await _manager?.stop();
    } catch (_) {
      // Best effort.
    }
    _running = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _manager?.delete();
    } catch (_) {}
    _manager = null;
    await _controller.close();
  }
}

/// Honestly-labeled fallback: continuous speech recognition watching for the
/// substring "piti".
///
/// THIS IS NOT A TRUE ACOUSTIC WAKE-WORD DETECTOR. It is an STT + substring
/// loop: slower, less reliable, battery-hungry, and it needs network for
/// recognition. It exists only so the app stays usable until the user sets
/// up Porcupine, and the UI/ README label it exactly this way.
class KeywordSpottingFallback implements WakeWordService {
  KeywordSpottingFallback();

  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _running = false;
  bool _stopping = false;

  @override
  WakeWordEngine get engine => WakeWordEngine.keywordSpotting;

  @override
  Stream<DateTime> get onWakeWord => _controller.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    final available = await _speech.initialize();
    if (!available) {
      throw ApiException(
        feature: 'Wake word',
        stage: 'wake',
        message:
            'Fallback keyword spotting unavailable: speech '
            'recognition not available on this device.',
      );
    }
    _running = true;
    _stopping = false;
    _loop();
  }

  Future<void> _loop() async {
    while (_running && !_stopping) {
      final heard = Completer<void>();
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase();
          if (words.contains('piti') || words.contains('pity')) {
            if (!_controller.isClosed) _controller.add(DateTime.now());
            if (!heard.isCompleted) heard.complete();
          }
          if (result.finalResult && !heard.isCompleted) {
            heard.complete();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
        ),
      );
      await heard.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      await _speech.stop();
      // Brief yield so stop() can take effect between passes.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    _running = false;
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
