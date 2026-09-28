import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'openrouter_service.dart' show ApiException;

/// Text-to-speech through OpenRouter's audio endpoint.
///
///   POST https://openrouter.ai/api/v1/audio/speech
///   Body: `{"model": "deepgram/flux-tts:free", "input": text,
///          "voice": "flux-cole-en"}`
///   -> 200 with raw MP3 bytes, or a JSON error body.
///
/// One OpenRouter key powers both the AI brain and the voice — no separate
/// TTS provider key is needed. Errors surface the real HTTP status and
/// message; they are never hidden.
class TtsService {
  TtsService();

  final AudioPlayer _player = AudioPlayer();
  bool _disposed = false;

  /// Synthesize [text] and play it. Throws [ApiException] with
  /// feature='Voice response', stage='tts' on any failure.
  Future<void> speak(
    String text,
    String apiKey, {
    void Function()? onPlaybackStart,
    void Function()? onPlaybackDone,
  }) async {
    if (_disposed) return;
    final uri = Uri.parse(AppConfig.openRouterTtsUrl);

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://pocketai.app',
              'X-Title': 'Pocket AI',
            },
            body: jsonEncode({
              'model': AppConfig.openRouterTtsModel,
              'input': text,
              'voice': AppConfig.openRouterTtsVoice,
            }),
          )
          .timeout(AppConfig.httpTimeout);
    } on TimeoutException {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        message:
            'OpenRouter TTS request timed out after '
            '${AppConfig.httpTimeout.inSeconds}s.',
        likelyCause: 'slow network or OpenRouter degradation',
      );
    } catch (e) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        message: 'Network error calling OpenRouter TTS: $e',
        likelyCause: 'no connectivity or DNS failure',
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        httpStatus: resp.statusCode,
        message: 'OpenRouter TTS synthesis failed.',
        bodySnippet: _errorSnippet(resp.bodyBytes),
        likelyCause: resp.statusCode == 401
            ? 'invalid or missing OpenRouter API key — check Settings'
            : resp.statusCode == 429
                  ? 'OpenRouter rate limit (too many requests)'
                  : 'OpenRouter service error',
      );
    }
    if (resp.bodyBytes.isEmpty) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        httpStatus: resp.statusCode,
        message:
            'OpenRouter returned HTTP ${resp.statusCode} with empty audio.',
        likelyCause: 'upstream synthesis produced no audio',
      );
    }

    final done = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
      sub.cancel();
    });
    try {
      await _player.play(BytesSource(resp.bodyBytes));
      onPlaybackStart?.call();
      await done.future.timeout(const Duration(seconds: 60));
      onPlaybackDone?.call();
    } on TimeoutException {
      await sub.cancel();
      throw ApiException(
        feature: 'Voice response',
        stage: 'playback',
        message: 'Audio playback did not complete within 60s.',
        likelyCause: 'audio player stalled',
      );
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // Best effort; stopping a dead player must not crash the pipeline.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _player.dispose();
  }

  String _errorSnippet(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes)) as Map;
      final err = decoded['error'];
      final msg = err is Map
          ? (err['message'] ?? err)
          : (decoded['message'] ?? decoded);
      final s = msg.toString().replaceAll(RegExp(r'\s+'), ' ');
      return s.length > 220 ? '${s.substring(0, 220)}…' : s;
    } catch (_) {
      return 'non-JSON error body (${bodyBytes.length} bytes)';
    }
  }
}
