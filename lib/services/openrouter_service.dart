import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Typed API failure. Carries the feature, pipeline stage, HTTP status and
/// the real error text so failures are never hidden behind "something went
/// wrong".
class ApiException implements Exception {
  ApiException({
    required this.feature,
    required this.stage,
    required this.message,
    this.httpStatus,
    this.bodySnippet,
    this.likelyCause,
  });

  final String feature;
  final String stage;
  final String message;
  final int? httpStatus;
  final String? bodySnippet;
  final String? likelyCause;

  @override
  String toString() {
    final sb = StringBuffer('[$feature][$stage]');
    if (httpStatus != null) sb.write(' HTTP $httpStatus');
    sb.write(': $message');
    if (likelyCause != null) sb.write(' Likely cause: $likelyCause.');
    if (bodySnippet != null && bodySnippet!.isNotEmpty) {
      sb.write(' Server said: $bodySnippet');
    }
    return sb.toString();
  }
}

/// The actions the assistant can actually perform on the device.
/// The model may only choose from this set — never invent new ones.
enum AssistantAction {
  openApp,
  openSettings,
  makeCall,
  setAlarm,
  chat, // plain conversational reply, no device action
  unsupported, // request is outside supported actions
}

class AssistantStep {
  AssistantStep({required this.action, required this.params});

  final AssistantAction action;
  final Map<String, dynamic> params;

  static AssistantAction _parseAction(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'open_app' => AssistantAction.openApp,
      'open_settings' => AssistantAction.openSettings,
      'make_call' => AssistantAction.makeCall,
      'set_alarm' => AssistantAction.setAlarm,
      'chat' => AssistantAction.chat,
      _ => AssistantAction.unsupported,
    };
  }

  factory AssistantStep.fromJson(Map<String, dynamic> json) {
    final params = Map<String, dynamic>.from(json['params'] as Map? ?? {});
    return AssistantStep(
      action: _parseAction(json['action']?.toString() ?? ''),
      params: params,
    );
  }
}

class AssistantIntent {
  AssistantIntent({required this.steps, required this.speak});

  /// Ordered plan. Steps run sequentially; each step is verified before the
  /// next runs. The spoken reply is composed ONLY from verified results.
  final List<AssistantStep> steps;

  /// Model-provided text, used ONLY for [AssistantAction.chat] and
  /// [AssistantAction.unsupported]. For device actions the spoken reply is
  /// composed from the REAL action results, never from this field.
  final String speak;

  factory AssistantIntent.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final List<AssistantStep> steps;
    if (rawSteps is List) {
      steps = rawSteps
          .whereType<Map<String, dynamic>>()
          .map(AssistantStep.fromJson)
          .toList();
    } else {
      // Tolerate the legacy single-action shape by wrapping it as one step.
      steps = [AssistantStep.fromJson(json)];
    }
    return AssistantIntent(
      steps: steps.isEmpty
          ? [AssistantStep(action: AssistantAction.unsupported, params: {})]
          : steps,
      speak: json['speak']?.toString() ?? '',
    );
  }

  factory AssistantIntent.unsupported(String reason) => AssistantIntent(
    steps: [AssistantStep(action: AssistantAction.unsupported, params: {})],
    speak: reason,
  );
}

class OpenRouterService {
  OpenRouterService();

  static const String _systemPrompt = '''
You are Piti, the voice brain of Pocket AI, an Android voice assistant.
Convert the user's spoken command into ONE JSON object — nothing else, no markdown.
The object has an ordered "steps" array; steps run one at a time, in order.

Supported step actions (use only these):
- {"action":"open_app","params":{"app_name":"YouTube"}}
- {"action":"open_settings","params":{}}
- {"action":"make_call","params":{"contact_name":"Daddy"}}
- {"action":"set_alarm","params":{"hour":7,"minute":30,"message":"wake up"}}
- {"action":"chat","params":{}}
- {"action":"unsupported","params":{}}

Top-level shape:
{"steps":[{...},{...}],"speak":"<only for chat/unsupported, else empty string>"}

Rules:
1. For multi-part commands (e.g. "open YouTube and set an alarm for 7"), put each part as its own step, in the spoken order.
2. For open_app, use the app name the user said (e.g. "YouTube", "Chrome", "WhatsApp", "Google Maps", "Spotify").
3. For make_call, use the contact name exactly as spoken. NEVER invent a phone number.
4. For set_alarm, convert times to 24h integers. If the time is ambiguous, use a single chat step whose "speak" asks for clarification.
5. "speak" is used ONLY when the plan is chat/unsupported. For device actions leave it "" — the app composes the reply from the real results.
6. If the request needs an action you do not support (sending messages, playing media, web search, etc.), return a single "unsupported" step and say so honestly in "speak".
7. Keep every "speak" under 25 words, plain and natural.
''';

  Future<AssistantIntent> interpret(String userText, String apiKey) async {
    final uri = Uri.parse('${AppConfig.openRouterBaseUrl}/chat/completions');
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
              'model': AppConfig.openRouterModelId,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0.2,
              'max_tokens': 300,
              'response_format': {'type': 'json_object'},
            }),
          )
          .timeout(AppConfig.httpTimeout);
    } on TimeoutException {
      throw ApiException(
        feature: 'AI reasoning',
        stage: 'ai',
        message:
            'Request to OpenRouter timed out after '
            '${AppConfig.httpTimeout.inSeconds}s.',
        likelyCause: 'slow network or OpenRouter degradation',
      );
    } catch (e) {
      throw ApiException(
        feature: 'AI reasoning',
        stage: 'ai',
        message: 'Network error calling OpenRouter: $e',
        likelyCause: 'no connectivity or DNS failure',
      );
    }

    if (resp.statusCode == 429) {
      throw ApiException(
        feature: 'AI reasoning',
        stage: 'ai',
        httpStatus: 429,
        message: 'OpenRouter rate limit hit (HTTP 429).',
        bodySnippet: _snippet(resp.body),
        likelyCause:
            'free-tier quota exhausted or too many requests; '
            'retry after a pause or add credits',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        feature: 'AI reasoning',
        stage: 'ai',
        httpStatus: resp.statusCode,
        message: 'OpenRouter request failed.',
        bodySnippet: _snippet(resp.body),
        likelyCause: resp.statusCode == 401
            ? 'invalid or missing OpenRouter API key — check Settings'
            : 'OpenRouter service error',
      );
    }

    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final content =
          (decoded['choices'] as List)[0]['message']['content'] as String;
      final intentJson = jsonDecode(content) as Map<String, dynamic>;
      return AssistantIntent.fromJson(intentJson);
    } catch (e) {
      throw ApiException(
        feature: 'AI reasoning',
        stage: 'ai',
        message: 'Could not parse the model response as JSON: $e',
        bodySnippet: _snippet(resp.body),
        likelyCause: 'model returned non-JSON despite response_format',
      );
    }
  }

  String _snippet(String body) {
    final oneLine = body.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length > 220 ? '${oneLine.substring(0, 220)}…' : oneLine;
  }
}
