import 'package:flutter/material.dart';

import '../config.dart';
import '../services/assistant_brain.dart';
import '../services/wake_word_service.dart';

/// Main screen: clean, simple, normal Android design.
///
/// Pocket AI branding, the Piti assistant, a large mic orb, clear listening
/// state, simple status feedback, minimal navigation. Nothing futuristic.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.brain,
    required this.onOpenSettings,
    required this.onOpenDebug,
  });

  final AssistantBrain brain;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDebug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Status & debug',
            onPressed: onOpenDebug,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: onOpenSettings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: brain,
        builder: (context, _) {
          final listening =
              brain.state == AssistantState.listening ||
              brain.state == AssistantState.waitingWakeWord;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                const Text(
                  AppConfig.appName,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppConfig.assistantName} — your voice assistant',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 36),
                // The orb: tap to talk when wake word is unavailable.
                GestureDetector(
                  onTap: brain.listenNow,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listening
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[300],
                      boxShadow: listening
                          ? [
                              BoxShadow(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.4),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      listening ? Icons.mic : Icons.mic_none_outlined,
                      size: 64,
                      color: listening ? Colors.white : Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Clear listening state.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: listening ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        brain.state.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (brain.statusDetail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    brain.statusDetail,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                _EngineChip(engine: brain.wakeEngine),
                const SizedBox(height: 24),
                if (brain.lastHeard.isNotEmpty)
                  _InfoCard(
                    title: 'You said',
                    body: brain.lastHeard,
                    icon: Icons.person_outline,
                  ),
                if (brain.lastSpoken.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: '${AppConfig.assistantName} said',
                    body: brain.lastSpoken,
                    icon: Icons.smart_toy_outlined,
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Say ${AppConfig.wakeWordDisplay} to wake me, or tap the microphone.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.engine});
  final WakeWordEngine engine;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        engine == WakeWordEngine.porcupine
            ? Icons.check_circle_outline
            : Icons.info_outline,
        size: 18,
      ),
      label: Text(engine.label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.icon,
  });
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontSize: 12)),
        subtitle: Text(body, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
