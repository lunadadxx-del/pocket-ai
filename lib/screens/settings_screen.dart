import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api_key_store.dart';
import '../services/assistant_brain.dart';
import '../services/wake_word_service.dart';

/// Settings: API key entry (secure storage), wake-word engine status.
///
/// Keys are written to the Android Keystore via flutter_secure_storage.
/// They are never displayed in full, never logged, never hardcoded.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.keys, required this.brain});

  final ApiKeyStore keys;
  final AssistantBrain brain;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _orController = TextEditingController();
  final _pvController = TextEditingController();

  bool _orSaved = false;
  bool _pvSaved = false;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final or = await widget.keys.getOpenRouterKey();
    final pv = await widget.keys.getPicovoiceKey();
    if (!mounted) return;
    setState(() {
      _orSaved = or != null && or.isNotEmpty;
      _pvSaved = pv != null && pv.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _orController.dispose();
    _pvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.brain,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionTitle('API keys'),
            const Text(
              'Keys are stored in the Android Keystore. They are never '
              'shown in full, logged, or included in the app package.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _KeyField(
              label: 'OpenRouter API key',
              hint:
                  'Powers the AI brain (${AppConfig.openRouterModelId}) '
                  'and voice output (${AppConfig.openRouterTtsModel})',
              controller: _orController,
              saved: _orSaved,
              onSave: () async {
                await widget.keys.setOpenRouterKey(_orController.text);
                _orController.clear();
                await _loadFlags();
              },
              onClear: () async {
                await widget.keys.clearOpenRouterKey();
                await _loadFlags();
              },
            ),
            _KeyField(
              label: 'Picovoice AccessKey',
              hint: 'Wake word engine (free at console.picovoice.ai)',
              controller: _pvController,
              saved: _pvSaved,
              onSave: () async {
                await widget.keys.setPicovoiceKey(_pvController.text);
                _pvController.clear();
                await _loadFlags();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Key saved. Restart the assistant to use Porcupine.',
                      ),
                    ),
                  );
                }
              },
              onClear: () async {
                await widget.keys.clearPicovoiceKey();
                await _loadFlags();
              },
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Wake word'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.brain.wakeEngine.tag} ${widget.brain.wakeEngine.label}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'True hands-free wake-up needs the Porcupine engine: '
                      'a free Picovoice AccessKey (above) plus a custom '
                      '"Piti" keyword file trained in the Picovoice Console '
                      'and bundled at assets/porcupine/piti_android.ppn '
                      'before building the app. Without it, the app uses '
                      'keyword spotting, which is NOT a true wake-word '
                      'detector — it is slower and needs network.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('About'),
            const Text(
              'Pocket AI v1.0.0 — voice-first Android assistant.\n'
              'Say "Piti", speak a command, hear the confirmed result.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.saved,
    required this.onSave,
    required this.onClear,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool saved;
  final Future<void> Function() onSave;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(
                  saved ? Icons.check_circle : Icons.circle_outlined,
                  color: saved ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  saved ? 'saved' : 'not set',
                  style: TextStyle(
                    color: saved ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => onSave(),
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: saved ? () => onClear() : null,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
