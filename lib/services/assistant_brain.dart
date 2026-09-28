import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/android_actions.dart';
import '../config.dart';
import 'api_key_store.dart';
import 'latency_tracker.dart';
import 'mic_arbiter.dart';
import 'openrouter_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';
import 'wake_word_service.dart';

/// UI-facing pipeline states.
enum AssistantState {
  idle,
  startingUp,
  waitingWakeWord,
  listening,
  thinking,
  acting,
  speaking,
  error,
}

extension AssistantStateLabel on AssistantState {
  String get label => switch (this) {
    AssistantState.idle => 'Idle',
    AssistantState.startingUp => 'Starting…',
    AssistantState.waitingWakeWord =>
      'Listening for ${AppConfig.wakeWordDisplay}',
    AssistantState.listening => 'Listening…',
    AssistantState.thinking => 'Thinking…',
    AssistantState.acting => 'Doing it…',
    AssistantState.speaking => 'Speaking…',
    AssistantState.error => 'Something needs attention',
  };
}

class DebugEntry {
  DebugEntry(this.time, this.tag, this.text);
  final DateTime time;
  final String tag; // [WORKING] [ERROR] [NOT TESTED] etc.
  final String text;
}

/// Result of one verified plan step.
class _StepOutcome {
  const _StepOutcome(this.ok, this.text);

  /// True only when Android confirmed the step.
  final bool ok;

  /// Honest sentence describing what happened.
  final String text;
}

/// Orchestrates one full voice turn:
/// wake -> STT -> AI -> Android action -> TTS, with the mic arbiter
/// guaranteeing a single microphone owner at every step.
///
/// HONESTY RULE: the spoken reply is composed from the REAL action result.
/// Nothing is claimed unless Android confirmed it.
class AssistantBrain extends ChangeNotifier {
  AssistantBrain({required this.keys});

  final ApiKeyStore keys;
  final AndroidActions actions = AndroidActions();
  final SttService stt = SttService();
  final TtsService tts = TtsService();
  final OpenRouterService ai = OpenRouterService();
  final LatencyTracker latency = LatencyTracker();
  final MicArbiter mic = MicArbiter();

  WakeWordService? _wake;
  StreamSubscription<void>? _wakeSub;

  AssistantState _state = AssistantState.idle;
  AssistantState get state => _state;

  String _statusDetail = '';
  String get statusDetail => _statusDetail;

  String _lastHeard = '';
  String get lastHeard => _lastHeard;

  String _lastSpoken = '';
  String get lastSpoken => _lastSpoken;

  final List<DebugEntry> _log = [];
  List<DebugEntry> get log => List.unmodifiable(_log);

  WakeWordEngine get wakeEngine => _wake?.engine ?? WakeWordEngine.unavailable;

  void _setState(AssistantState s, [String detail = '']) {
    _state = s;
    _statusDetail = detail;
    notifyListeners();
  }

  void logEvent(String tag, String text) {
    _log.add(DebugEntry(DateTime.now(), tag, text));
    if (_log.length > 300) _log.removeAt(0);
    notifyListeners();
  }

  /// Start the assistant: build the wake-word engine and begin listening.
  Future<void> start() async {
    if (_state != AssistantState.idle && _state != AssistantState.error) {
      return;
    }
    _setState(AssistantState.startingUp);
    latency.reset();

    final picovoiceKey = await keys.getPicovoiceKey() ?? '';
    WakeWordService candidate = PorcupineWakeWordService(
      accessKey: picovoiceKey,
    );
    try {
      // Probe: start() throws honestly when key/keyword file is missing.
      mic.acquireWakeWord();
      await candidate.start();
      _wake = candidate;
      logEvent(
        '[WORKING]',
        'Wake word: Porcupine engine active, listening for '
            '${AppConfig.wakeWordDisplay}.',
      );
    } on ApiException catch (e) {
      mic.forceReset();
      await candidate.dispose();
      logEvent('[BLOCKED]', 'Porcupine unavailable: $e');
      // Honest fallback — labeled as NOT a true wake-word detector.
      final fallback = KeywordSpottingFallback();
      try {
        mic.acquireWakeWord();
        await fallback.start();
        _wake = fallback;
        logEvent(
          '[PARTIALLY WORKING]',
          'Wake word: keyword-spotting fallback active. This is NOT a '
              'true acoustic wake-word detector — set up Porcupine in Settings.',
        );
      } on ApiException catch (e2) {
        mic.forceReset();
        await fallback.dispose();
        _wake = null;
        logEvent('[BLOCKED]', 'No wake-word engine available: $e2');
        _setState(
          AssistantState.waitingWakeWord,
          'Wake word unavailable — tap the orb to talk.',
        );
        return;
      }
    }

    // Keep the process alive while the wake engine runs (foreground service).
    final ka = await actions.keepAliveStart();
    logEvent(
      ka.ok ? '[WORKING]' : '[ERROR]',
      'Foreground keep-alive: ${ka.message}',
    );

    _wakeSub = _wake!.onWakeWord.listen(_onWakeWord);
    _setState(AssistantState.waitingWakeWord);
  }

  Future<void> _onWakeWord(DateTime detectedAt) async {
    if (_state == AssistantState.listening ||
        _state == AssistantState.thinking ||
        _state == AssistantState.acting ||
        _state == AssistantState.speaking) {
      return; // already handling a turn
    }
    logEvent('[WORKING]', 'Wake word ${AppConfig.wakeWordDisplay} detected.');
    await HapticFeedback.mediumImpact();
    unawaited(_handleTurn(wakeDetectedAt: detectedAt));
  }

  /// Manual orb tap: same pipeline without the wake-word stage.
  Future<void> listenNow() async {
    if (_state == AssistantState.listening ||
        _state == AssistantState.thinking ||
        _state == AssistantState.acting ||
        _state == AssistantState.speaking) {
      return;
    }
    await HapticFeedback.selectionClick();
    unawaited(_handleTurn());
  }

  Future<void> _handleTurn({DateTime? wakeDetectedAt}) async {
    latency.reset();
    // --- Mic handoff: wake engine -> command capture ---
    // The wake engine may or may not hold the mic here (manual orb taps
    // happen while idle). Release wake ownership only if it is actually
    // held, then always acquire command ownership so STT never runs
    // without it.
    try {
      await _wake?.stop();
    } catch (_) {
      // Best effort: a failed stop must not wedge the turn.
    }
    // Let Android fully release the recognizer before STT grabs the mic.
    // Skipping this causes "microphone in use" listen failures on some
    // devices when the wake engine was just torn down.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mic.owner == MicOwner.wakeWord) {
      mic.releaseWakeWord();
    } else if (mic.owner != MicOwner.idle) {
      logEvent(
        '[ERROR]',
        'Mic handoff: unexpected owner ${mic.owner}; resetting.',
      );
      mic.forceReset();
    }
    try {
      mic.acquireCommand();
    } on MicOwnershipException catch (e) {
      logEvent('[ERROR]', 'Mic handoff failed: $e');
      mic.forceReset();
      mic.acquireCommand();
    }
    // Honest wake latency: detection -> command mic owned. Manual taps
    // have no wake stage, so nothing is recorded for them.
    if (wakeDetectedAt != null) {
      latency.record(
        Stage.wake,
        DateTime.now().difference(wakeDetectedAt),
        note: 'detection -> command mic handoff',
      );
    }

    try {
      // --- STT ---
      _setState(AssistantState.listening);
      latency.start(Stage.stt);
      final heard = await stt.listenOnce();
      latency.stop(Stage.stt);
      if (heard == null) {
        await _speakAndResume(
          "I didn't catch that. Please try again.",
          extraNote: 'stt: no speech recognized',
        );
        return;
      }
      _lastHeard = heard;
      logEvent('[WORKING]', 'Heard: "$heard"');

      // --- AI ---
      final orKey = await keys.getOpenRouterKey();
      if (orKey == null || orKey.isEmpty) {
        await _speakAndResume(
          'The OpenRouter API key is missing. Add it in Settings.',
          extraNote: 'ai: missing API key',
        );
        return;
      }
      _setState(AssistantState.thinking);
      latency.start(Stage.ai);
      late final AssistantIntent intent;
      try {
        intent = await ai.interpret(heard, orKey);
      } on ApiException catch (e) {
        latency.stop(Stage.ai, note: 'failed');
        logEvent('[ERROR]', e.toString());
        await _speakAndResume(
          _shortSpokenError(e),
          extraNote: 'ai failed: HTTP ${e.httpStatus}',
        );
        return;
      }
      latency.stop(Stage.ai);
      final stepSummary = intent.steps
          .map((s) => '${s.action.name} ${s.params}')
          .join(' -> ');
      logEvent('[WORKING]', 'Plan: $stepSummary');

      // --- Actions: run the ordered plan, verifying each step ---
      _setState(AssistantState.acting);
      latency.start(Stage.action);
      final speakText = await _executePlan(intent);
      latency.stop(Stage.action);

      // --- Speak the REAL result ---
      await _speakAndResume(speakText);
    } on ApiException catch (e) {
      latency.stop(Stage.stt);
      logEvent('[ERROR]', e.toString());
      await _speakAndResume(_shortSpokenError(e));
    } catch (e) {
      logEvent('[ERROR]', 'Unexpected pipeline failure: $e');
      await _speakAndResume(
        'Something failed on my side. The debug screen has the details.',
      );
    }
  }

  /// Execute the ordered plan against Android, verifying each step before
  /// the next runs. The spoken reply is composed ONLY from CONFIRMED
  /// results. If a step fails, later steps are skipped and the reply says
  /// honestly what did and did not happen. Nothing is claimed unless
  /// Android confirmed it.
  Future<String> _executePlan(AssistantIntent intent) async {
    final confirmed = <String>[];
    for (var i = 0; i < intent.steps.length; i++) {
      final step = intent.steps[i];
      final outcome = await _executeStep(step, intent.speak);
      if (outcome.ok) {
        confirmed.add(outcome.text);
      } else {
        // Stop the plan here: do not run later steps on a failed earlier one,
        // and do not claim the failed step worked.
        logEvent(
          '[ERROR]',
          'Plan stopped at step ${i + 1}/${intent.steps.length}: '
              '${outcome.text}',
        );
        final done = confirmed.isEmpty ? '' : 'So far: ${confirmed.join(' ')} ';
        return '$done${outcome.text}';
      }
    }
    if (confirmed.isEmpty) {
      return intent.speak.isNotEmpty ? intent.speak : "I couldn't do that.";
    }
    return confirmed.join(' ');
  }

  /// A single verified step result: [ok] means Android confirmed it, and
  /// [text] is the honest sentence to speak for it.
  Future<_StepOutcome> _executeStep(
    AssistantStep step,
    String modelSpeak,
  ) async {
    switch (step.action) {
      case AssistantAction.openApp:
        final name = step.params['app_name']?.toString() ?? 'that app';
        final res = await actions.openAppByName(name);
        logEvent(
          res.ok ? '[WORKING]' : '[ERROR]',
          'openAppByName("$name"): ${res.message}',
        );
        return _StepOutcome(
          res.ok,
          res.ok
              ? '${res.data?['label'] ?? name} is open.'
              : "I couldn't open $name. ${res.message}",
        );

      case AssistantAction.openSettings:
        final res = await actions.openSettings();
        logEvent(
          res.ok ? '[WORKING]' : '[ERROR]',
          'openSettings: ${res.message}',
        );
        return _StepOutcome(
          res.ok,
          res.ok
              ? 'Settings is open.'
              : "I couldn't open Settings. ${res.message}",
        );

      case AssistantAction.makeCall:
        return _handleMakeCall(step);

      case AssistantAction.setAlarm:
        final hour = (step.params['hour'] as num?)?.toInt();
        final minute = (step.params['minute'] as num?)?.toInt() ?? 0;
        if (hour == null || hour < 0 || hour > 23) {
          return const _StepOutcome(
            false,
            'I need a valid time to set an alarm. Please try again.',
          );
        }
        final res = await actions.setAlarm(
          hour: hour,
          minute: minute,
          message: step.params['message']?.toString() ?? 'Pocket AI alarm',
        );
        logEvent(
          res.ok ? '[WORKING]' : '[ERROR]',
          'setAlarm($hour:$minute): ${res.message}',
        );
        final hm =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        return _StepOutcome(
          res.ok,
          res.ok
              ? 'Alarm set for $hm.'
              : "I couldn't set the alarm. ${res.message}",
        );

      case AssistantAction.chat:
        return _StepOutcome(
          true,
          modelSpeak.isNotEmpty ? modelSpeak : "I don't have a reply for that.",
        );

      case AssistantAction.unsupported:
        return _StepOutcome(
          true,
          modelSpeak.isNotEmpty ? modelSpeak : "I can't do that yet.",
        );
    }
  }

  /// "Call Daddy": resolve the name against REAL contacts.
  /// Never invents a number. 0 matches -> say so. >1 -> ask to clarify.
  Future<_StepOutcome> _handleMakeCall(AssistantStep step) async {
    final name = step.params['contact_name']?.toString() ?? '';
    if (name.isEmpty) {
      return const _StepOutcome(
        false,
        'Who should I call? Please say a contact name.',
      );
    }
    late final List<ContactMatch> matches;
    try {
      matches = await actions.findContacts(name);
    } on ApiException catch (e) {
      logEvent('[ERROR]', e.toString());
      return _StepOutcome(
        false,
        'I could not look up your contacts. ${e.message}',
      );
    }
    logEvent(
      '[WORKING]',
      'findContacts("$name"): ${matches.length} match(es).',
    );

    if (matches.isEmpty) {
      return _StepOutcome(false, "I couldn't find $name in your contacts.");
    }
    if (matches.length > 1) {
      final names = matches.take(3).map((m) => m.displayName).join(', ');
      return _StepOutcome(
        false,
        'I found several contacts matching $name: $names. '
        'Which one should I call?',
      );
    }
    final contact = matches.single;
    final res = await actions.placeCall(contact.phone);
    logEvent(
      res.ok ? '[WORKING]' : '[ERROR]',
      'placeCall(${contact.displayName}): ${res.message}',
    );
    return _StepOutcome(
      res.ok,
      res.ok
          ? 'Calling ${contact.displayName}.'
          : "I couldn't place the call. ${res.message}",
    );
  }

  String _shortSpokenError(ApiException e) {
    if (e.httpStatus == 429) {
      return 'The AI service is rate limited right now. Please wait a moment and try again.';
    }
    if (e.httpStatus == 401) {
      return 'The API key was rejected. Please check it in Settings.';
    }
    // Keep the spoken message short; the full error is on the debug screen.
    return 'That failed: ${e.message}';
  }

  /// Speak [text] via TTS, then hand the mic back to the wake-word engine.
  Future<void> _speakAndResume(String text, {String? extraNote}) async {
    _lastSpoken = text;
    _setState(AssistantState.speaking);
    final orKey = await keys.getOpenRouterKey();
    if (orKey == null || orKey.isEmpty) {
      // Voice key missing: show the text, say so honestly — never pretend
      // the voice response worked.
      logEvent(
        '[ERROR]',
        'Voice response: OpenRouter API key missing — reply shown as text only.',
      );
      _setState(
        AssistantState.waitingWakeWord,
        'OpenRouter key missing — reply shown as text.',
      );
      await _resumeWakeWord();
      return;
    }
    latency.start(Stage.tts);
    try {
      bool playbackStarted = false;
      await tts.speak(
        text,
        orKey,
        onPlaybackStart: () {
          playbackStarted = true;
          latency.stop(Stage.tts);
          latency.start(Stage.playback);
        },
        onPlaybackDone: () => latency.stop(Stage.playback),
      );
      if (!playbackStarted) {
        latency.stop(Stage.tts, note: 'no playback callback');
      }
      logEvent(
        '[WORKING]',
        'Spoke: "$text"${extraNote != null ? ' ($extraNote)' : ''}',
      );
    } on ApiException catch (e) {
      latency.stop(Stage.tts, note: 'failed');
      // TTS failed: report the REAL error. Do not silently show text and
      // pretend the voice response worked.
      logEvent('[ERROR]', e.toString());
      _lastSpoken = 'Voice failed (HTTP ${e.httpStatus ?? '?'}): $text';
    }
    await _resumeWakeWord();
  }

  Future<void> _resumeWakeWord() async {
    // --- Mic handoff: command -> wake engine ---
    try {
      mic.releaseCommand();
    } on MicOwnershipException catch (e) {
      logEvent('[ERROR]', 'Mic release failed: $e');
      mic.forceReset();
    }
    if (_wake != null) {
      try {
        mic.acquireWakeWord();
        await _wake!.start();
      } on ApiException catch (e) {
        mic.forceReset();
        logEvent('[ERROR]', 'Could not resume wake word: $e');
      }
    }
    _setState(AssistantState.waitingWakeWord);
  }

  Future<void> stopAll() async {
    await _wakeSub?.cancel();
    _wakeSub = null;
    try {
      await _wake?.stop();
    } catch (_) {}
    await _wake?.dispose();
    _wake = null;
    await stt.stop();
    await tts.stop();
    await actions.keepAliveStop();
    mic.forceReset();
    _setState(AssistantState.idle);
  }

  @override
  void dispose() {
    // Ordered teardown: stop the pipeline fully BEFORE releasing the
    // audio player, so stop() and dispose() never race on it.
    unawaited(_tearDown());
    super.dispose();
  }

  Future<void> _tearDown() async {
    try {
      await stopAll();
    } catch (_) {
      // Best effort during teardown.
    }
    try {
      await tts.dispose();
    } catch (_) {
      // Best effort during teardown.
    }
  }
}
