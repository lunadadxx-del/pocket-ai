import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'openrouter_service.dart' show ApiException;

/// Deepgram Flux TTS over the batch REST endpoint.
///
/// Endpoint verified 2026-09-27 UTC from Deepgram docs:
///   POST https://api.deepgram.com/v2/speak with model and encoding params.
///   Headers: Authorization: Token DEEPGRAM_KEY, Content-Type: application/json
///   Body: {"text": "..."}  -> 200 with binary audio, or JSON error.
/// Errors are surfaced with the real HTTP status and message — never hidden.
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
    final uri = Uri.parse(
      '${AppConfig.deepgramTtsUrl}'
      '?model=${AppConfig.deepgramTtsModel}'
      '&encoding=${AppConfig.deepgramTtsEncoding}',
    );

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Token $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': text}),
          )
          .timeout(AppConfig.httpTimeout);
    } on TimeoutException {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        message:
            'Deepgram TTS request timed out after '
            '${AppConfig.httpTimeout.inSeconds}s.',
        likelyCause: 'slow network or Deepgram degradation',
      );
    } catch (e) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        message: 'Network error calling Deepgram: $e',
        likelyCause: 'no connectivity or DNS failure',
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        httpStatus: resp.statusCode,
        message: 'Deepgram TTS synthesis failed.',
        bodySnippet: _errorSnippet(resp.bodyBytes),
        likelyCause: resp.statusCode == 401
            ? 'invalid or missing Deepgram API key — check Settings'
            : resp.statusCode == 429
            ? 'Deepgram rate limit (too many concurrent requests)'
            : 'Deepgram service error',
      );
    }
    if (resp.bodyBytes.isEmpty) {
      throw ApiException(
        feature: 'Voice response',
        stage: 'tts',
        httpStatus: resp.statusCode,
        message: 'Deepgram returned HTTP ${resp.statusCode} with empty audio.',
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
      final msg = decoded['err_msg'] ?? decoded['message'] ?? decoded;
      final s = msg.toString().replaceAll(RegExp(r'\s+'), ' ');
      return s.length > 220 ? '${s.substring(0, 220)}…' : s;
    } catch (_) {
      return 'non-JSON error body (${bodyBytes.length} bytes)';
    }
  }
}
