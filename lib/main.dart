import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'screens/debug_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_key_store.dart';
import 'services/assistant_brain.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PocketAiApp());
}

class PocketAiApp extends StatefulWidget {
  const PocketAiApp({super.key});

  @override
  State<PocketAiApp> createState() => _PocketAiAppState();
}

class _PocketAiAppState extends State<PocketAiApp> {
  late final ApiKeyStore _keys;
  late final AssistantBrain _brain;

  @override
  void initState() {
    super.initState();
    _keys = ApiKeyStore();
    _brain = AssistantBrain(keys: _keys);
    _boot();
  }

  Future<void> _boot() async {
    // Permissions the assistant genuinely needs. Each is requested once;
    // denials are reported honestly instead of worked around.
    final mic = await Permission.microphone.request();
    final contacts = await Permission.contacts.request();
    final phone = await Permission.phone.request();
    if (mic.isDenied || mic.isPermanentlyDenied) {
      _brain.logEvent(
        '[ERROR]',
        'Microphone permission denied — voice input cannot work. '
            'Grant it in Android Settings > Apps > Pocket AI > Permissions.',
      );
    }
    if (contacts.isDenied || contacts.isPermanentlyDenied) {
      _brain.logEvent(
        '[ERROR]',
        'Contacts permission denied — "call <name>" cannot resolve contacts.',
      );
    }
    if (phone.isDenied || phone.isPermanentlyDenied) {
      _brain.logEvent(
        '[ERROR]',
        'Phone permission denied — placing calls will fail.',
      );
    }
    final hasKeys = await _keys.hasVoicePipelineKeys();
    if (!hasKeys) {
      _brain.logEvent(
        '[BLOCKED]',
        'API key missing. Enter the OpenRouter key in '
            'Settings before a full voice turn can run.',
      );
    }
    await _brain.start();
  }

  @override
  void dispose() {
    _brain.dispose();
    super.dispose();
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(keys: _keys, brain: _brain),
      ),
    );
  }

  void _openDebug(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DebugScreen(brain: _brain)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) => HomeScreen(
          brain: _brain,
          onOpenSettings: () => _openSettings(context),
          onOpenDebug: () => _openDebug(context),
        ),
      ),
    );
  }
}
