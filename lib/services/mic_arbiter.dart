/// Microphone ownership arbiter.
///
/// HARD RULE (from the spec): there must never be multiple components
/// competing for the microphone. Exactly one owner is active at a time.
///
/// Handoff protocol for one assistant turn:
///   1. Wake-word engine detects "Piti"  -> [releaseWakeWord] (engine stops,
///      frees the mic), owner becomes [MicOwner.command].
///   2. STT listens for the command      -> owner stays [MicOwner.command].
///   3. After TTS playback finishes     -> [releaseCommand], owner becomes
///      [MicOwner.wakeWord] again and the wake engine restarts.
///
/// Any attempt to acquire the mic while another owner holds it throws, so a
/// second recorder can never start silently.
enum MicOwner { idle, wakeWord, command }

class MicOwnershipException implements Exception {
  MicOwnershipException(this.message);
  final String message;
  @override
  String toString() => 'MicOwnershipException: $message';
}

class MicArbiter {
  MicOwner _owner = MicOwner.idle;

  MicOwner get owner => _owner;

  void acquireWakeWord() {
    _acquire(MicOwner.wakeWord);
  }

  void acquireCommand() {
    _acquire(MicOwner.command);
  }

  void releaseWakeWord() {
    _release(MicOwner.wakeWord);
  }

  void releaseCommand() {
    _release(MicOwner.command);
  }

  void _acquire(MicOwner next) {
    if (_owner != MicOwner.idle) {
      throw MicOwnershipException(
        'Cannot acquire mic for $next: already owned by $_owner. '
        'Release it first.',
      );
    }
    _owner = next;
  }

  void _release(MicOwner current) {
    if (_owner != current) {
      throw MicOwnershipException(
        'Cannot release mic for $current: owned by $_owner.',
      );
    }
    _owner = MicOwner.idle;
  }

  /// Forced reset used only on error paths so a crashed turn can never
  /// wedge the microphone. Logged to the debug screen when used.
  void forceReset() {
    _owner = MicOwner.idle;
  }
}
