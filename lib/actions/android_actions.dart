import 'package:flutter/services.dart';

import '../config.dart';
import '../services/openrouter_service.dart' show ApiException;

/// Result of one Android action, exactly as reported by the platform.
/// [ok] is true ONLY when Android confirmed the action succeeded.
class ActionResult {
  ActionResult({required this.ok, required this.message, this.data});

  final bool ok;
  final String message;
  final Map<String, dynamic>? data;

  factory ActionResult.fromMap(Map<dynamic, dynamic> map) {
    return ActionResult(
      ok: map['ok'] == true,
      message: map['message']?.toString() ?? '',
      data: map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : null,
    );
  }

  factory ActionResult.failure(String message) =>
      ActionResult(ok: false, message: message);
}

class ContactMatch {
  ContactMatch({required this.displayName, required this.phone});
  final String displayName;
  final String phone;

  factory ContactMatch.fromMap(Map<dynamic, dynamic> m) => ContactMatch(
    displayName: m['displayName']?.toString() ?? 'Unknown',
    phone: m['phone']?.toString() ?? '',
  );
}

/// Dart side of the native action bridge.
///
/// Every method returns what Android ACTUALLY reported. The brain speaks
/// only these confirmed results — it never claims an action happened
/// unless [ActionResult.ok] is true.
class AndroidActions {
  AndroidActions();

  static const MethodChannel _channel = MethodChannel(AppConfig.actionsChannel);

  Future<ActionResult> _invoke(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        args,
      );
      if (raw == null) {
        return ActionResult.failure('Android returned no result for $method.');
      }
      return ActionResult.fromMap(raw);
    } on PlatformException catch (e) {
      return ActionResult.failure(
        'Platform error in $method: ${e.message ?? e.code}',
      );
    } on MissingPluginException {
      return ActionResult.failure(
        'Native bridge not available for $method (not running on Android?).',
      );
    }
  }

  /// Open an app by spoken name. Android resolves known packages first,
  /// then matches installed launchable apps by label.
  Future<ActionResult> openAppByName(String name) =>
      _invoke('openAppByName', {'name': name});

  Future<ActionResult> openSettings() => _invoke('openSettings');

  /// Resolve [name] against device contacts. Returns the real matches —
  /// the caller decides: 0 -> report missing, 1 -> call, many -> clarify.
  /// Phone numbers come ONLY from the contacts provider. Never invented.
  Future<List<ContactMatch>> findContacts(String name) async {
    final res = await _invoke('findContacts', {'name': name});
    if (!res.ok) {
      throw ApiException(
        feature: 'Phone call',
        stage: 'action',
        message: 'Contact lookup failed: ${res.message}',
        likelyCause: 'READ_CONTACTS permission missing',
      );
    }
    final list = res.data?['matches'] as List? ?? [];
    return list
        .whereType<Map>()
        .map((m) => ContactMatch.fromMap(m))
        .where((c) => c.phone.isNotEmpty)
        .toList();
  }

  Future<ActionResult> placeCall(String phone) =>
      _invoke('placeCall', {'phone': phone});

  Future<ActionResult> setAlarm({
    required int hour,
    required int minute,
    required String message,
  }) =>
      _invoke('setAlarm', {'hour': hour, 'minute': minute, 'message': message});

  /// Keep the process in the foreground while the wake-word engine runs so
  /// Android does not kill the mic. This changes process priority only —
  /// it does not fake any capability (see README limitations).
  Future<ActionResult> keepAliveStart() => _invoke('keepAliveStart');
  Future<ActionResult> keepAliveStop() => _invoke('keepAliveStop');
}
