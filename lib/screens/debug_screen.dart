import 'package:flutter/material.dart';

import '../services/assistant_brain.dart';
import '../services/latency_tracker.dart';

/// Status & debug screen.
///
/// - Capability matrix: every claimed ability with its honest tag.
///   Tags: [WORKING] [PARTIALLY WORKING] [ERROR] [NOT TESTED] [BLOCKED]
/// - Per-stage latency of the last turn (measured, never estimated).
/// - Microphone owner (exactly one at a time — see MicArbiter).
/// - Timestamped event log with real errors.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key, required this.brain});

  final AssistantBrain brain;

  // NOTE: update these tags only after real testing. Never mark something
  // [WORKING] because the code "looks right".
  static const List<_Capability> _capabilities = [
    _Capability(
      'Wake word "Piti" (Porcupine, on-device)',
      '[NOT TESTED]',
      'Implemented. Needs Picovoice key + custom .ppn keyword file; '
          'no physical device test yet.',
    ),
    _Capability(
      'Wake word fallback (keyword spotting)',
      '[NOT TESTED]',
      'Implemented and honestly labeled: NOT a true wake-word detector.',
    ),
    _Capability(
      'Voice command capture (Android SpeechRecognizer)',
      '[NOT TESTED]',
      'Implemented via speech_to_text; no physical device test yet.',
    ),
    _Capability(
      'AI intent parsing (Gemma 4 31B via OpenRouter)',
      '[NOT TESTED]',
      'Implemented; needs user API key; no live call made yet.',
    ),
    _Capability(
      'Open app by voice (PackageManager)',
      '[NOT TESTED]',
      'Implemented natively; no physical device test yet.',
    ),
    _Capability(
      'Open Settings',
      '[NOT TESTED]',
      'Implemented natively; no physical device test yet.',
    ),
    _Capability(
      'Call contact by name (real contact lookup)',
      '[NOT TESTED]',
      'Implemented: 0/1/many match handling, never invents numbers; '
          'no physical device test yet.',
    ),
    _Capability(
      'Set alarm (AlarmClock intent)',
      '[NOT TESTED]',
      'Implemented; depends on a clock app handling the intent; '
          'no physical device test yet.',
    ),
    _Capability(
      'Multi-action commands (ordered plan)',
      '[NOT TESTED]',
      'Implemented: AI returns an ordered step list; each step is '
          'verified before the next runs; the reply is composed only '
          'from confirmed results; a failed step stops the plan honestly. '
          'No physical device test yet.',
    ),
    _Capability(
      'Voice reply (OpenRouter Flux TTS)',
      '[NOT TESTED]',
      'Implemented against POST /v1/audio/speech; needs user API key; '
          'no live call made yet.',
    ),
    _Capability(
      'Hands-free: app in background',
      '[NOT TESTED]',
      'Foreground keep-alive service implemented to hold the process; '
          'OEM battery savers may still kill it.',
    ),
    _Capability(
      'Hands-free: screen locked / screen off',
      '[BLOCKED]',
      'Android does not deliver mic audio to background apps on the '
          'lock screen without a foreground service + user exemptions; '
          'not implemented — claimed nowhere.',
    ),
    _Capability(
      'Playing media / sending messages / web search',
      '[BLOCKED]',
      'Not supported by the action set. The AI says so honestly instead '
          'of pretending.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status & debug')),
      body: ListenableBuilder(
        listenable: brain,
        builder: (context, _) {
          final timings = brain.latency.report();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section('Microphone', [
                Text(
                  'Owner: ${brain.mic.owner.name}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Text(
                  'Rule: exactly one owner at a time. '
                  'wakeWord -> command -> wakeWord handoff per turn.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ]),
              _Section('Last turn latency (measured)', [
                if (timings.isEmpty)
                  const Text(
                    'No turn completed yet.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  for (final t in timings)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(t.stage.label)),
                          Text(
                            t.formatted,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${(brain.latency.total.inMilliseconds / 1000).toStringAsFixed(2)}s',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
              _Section('Capability matrix', [
                for (final c in _capabilities)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${c.tag} ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _tagColor(c.tag),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              TextSpan(
                                text: c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          c.note,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              _Section('Event log', [
                if (brain.log.isEmpty)
                  const Text(
                    'No events yet.',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  for (final e in brain.log.reversed.take(80))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${_time(e.time)} ${e.tag} ${e.text}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Color _tagColor(String tag) {
    return switch (tag) {
      '[WORKING]' => Colors.green[700]!,
      '[PARTIALLY WORKING]' => Colors.orange[800]!,
      '[ERROR]' => Colors.red[700]!,
      '[BLOCKED]' => Colors.purple[700]!,
      _ => Colors.grey[600]!,
    };
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _Capability {
  const _Capability(this.name, this.tag, this.note);
  final String name;
  final String tag;
  final String note;
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
