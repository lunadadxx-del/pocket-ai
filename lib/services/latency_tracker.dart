/// Per-stage latency measurement for the voice pipeline.
///
/// Every stage of one assistant turn is timed; nothing is estimated.
/// The debug screen renders [report] verbatim. Do not "optimize" based on
/// these numbers without measuring a change against them.
enum Stage {
  wake, // wake-word detection -> mic handoff (measured by the caller)
  stt, // microphone -> final transcript
  ai, // OpenRouter request -> parsed intent
  action, // Android action execution -> confirmed result
  tts, // Deepgram request -> audio bytes received
  playback, // audio playback start -> completion
}

extension StageLabel on Stage {
  String get label => switch (this) {
    Stage.wake => 'Wake word',
    Stage.stt => 'Speech-to-text',
    Stage.ai => 'AI reasoning',
    Stage.action => 'Android action',
    Stage.tts => 'TTS synthesis',
    Stage.playback => 'Audio playback',
  };
}

class StageTiming {
  StageTiming(this.stage, this.duration, {this.note});
  final Stage stage;
  final Duration duration;
  final String? note;

  String get formatted =>
      '${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s';
}

class LatencyTracker {
  final Map<Stage, Stopwatch> _running = {};
  final Map<Stage, Duration> _done = {};
  final Map<Stage, String> _notes = {};

  void start(Stage stage) {
    _running[stage] = Stopwatch()..start();
    _done.remove(stage);
  }

  void stop(Stage stage, {String? note}) {
    final w = _running.remove(stage);
    if (w != null) {
      w.stop();
      _done[stage] = w.elapsed;
    }
    if (note != null) _notes[stage] = note;
  }

  /// Record a stage timed externally (e.g. wake-word detection latency).
  void record(Stage stage, Duration duration, {String? note}) {
    _running.remove(stage);
    _done[stage] = duration;
    if (note != null) _notes[stage] = note;
  }

  List<StageTiming> report() {
    return Stage.values
        .where((s) => _done.containsKey(s))
        .map((s) => StageTiming(s, _done[s]!, note: _notes[s]))
        .toList();
  }

  Duration get total => _done.values.fold(Duration.zero, (sum, d) => sum + d);

  void reset() {
    _running.clear();
    _done.clear();
    _notes.clear();
  }
}
