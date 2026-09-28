import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for user-supplied API keys.
///
/// Keys are entered by the user in the Settings screen and kept in the
/// Android Keystore via flutter_secure_storage. They are NEVER hardcoded,
/// NEVER logged, and NEVER written anywhere else.
class ApiKeyStore {
  ApiKeyStore();

  static const String _openRouterKey = 'openrouter_api_key';
  static const String _picovoiceKey = 'picovoice_access_key';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> getOpenRouterKey() => _storage.read(key: _openRouterKey);
  Future<String?> getPicovoiceKey() => _storage.read(key: _picovoiceKey);

  Future<void> setOpenRouterKey(String v) =>
      _storage.write(key: _openRouterKey, value: v.trim());
  Future<void> setPicovoiceKey(String v) =>
      _storage.write(key: _picovoiceKey, value: v.trim());

  Future<void> clearOpenRouterKey() => _storage.delete(key: _openRouterKey);
  Future<void> clearPicovoiceKey() => _storage.delete(key: _picovoiceKey);

  /// True when the key required for a full voice round-trip is present.
  /// One OpenRouter key powers both the AI brain and TTS.
  Future<bool> hasVoicePipelineKeys() async {
    final or = await getOpenRouterKey();
    return or != null && or.isNotEmpty;
  }
}
