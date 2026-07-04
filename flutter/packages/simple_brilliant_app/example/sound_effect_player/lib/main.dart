import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'package:simple_brilliant_app/simple_brilliant_app.dart';

import 'tx_sound_effect.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

/// firmware sound presets available via frame.sound.play()
const _effects = [
  'pickup',
  'laser',
  'explosion',
  'powerup',
  'hit',
  'jump',
  'blip',
];

/// a sound that has been played, so the user can find the seed of one they liked
class _PlayedEffect {
  final String effect;
  final int seed;
  _PlayedEffect(this.effect, this.seed);
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  static const _playSoundMsg = 0x20;

  /// firmware sounds default to 1000ms duration, so space plays out a little
  /// further than that - only one sound effect can play at a time
  static const _soundGap = Duration(milliseconds: 1200);

  final _random = Random();
  late TextEditingController _seedController;
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  String _selectedEffect = _effects.first;
  final List<_PlayedEffect> _history = [];
  bool _autoPlay = false;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    _seedController = TextEditingController();

    // start up if the Frame can be found
    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  /// The seed to play with: the number typed into the seed field,
  /// a random seed if the field is empty, or null if the text is invalid
  int? _chooseSeed() {
    final text = _seedController.text.trim();
    if (text.isEmpty) return _random.nextInt(0x100000000);

    final seed = int.tryParse(text);
    if (seed == null || seed < 0 || seed > 0xFFFFFFFF) return null;
    return seed;
  }

  /// send the play message to Halo and log the sound in the history
  Future<void> _playSound(String effect, int seed) async {
    await frame!.sendMessage(_playSoundMsg, TxSoundEffect(effect: effect, seed: seed).pack());
    if (mounted) setState(() => _history.insert(0, _PlayedEffect(effect, seed)));
  }

  /// Play the selected effect once, with the seed from the text field
  /// (or a random seed if the field is empty)
  @override
  Future<void> run() async {
    final seed = _chooseSeed();
    if (seed == null) {
      _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Seed must be a number from 0 to 4294967295')));
      return;
    }

    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      await _playSound(_selectedEffect, seed);
      // block further submissions until the sound has finished playing
      await Future.delayed(_soundGap);
    } catch (e) {
      _log.warning('Error playing sound: $e');
    }

    if (currentState == ApplicationState.running) {
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// keep playing random variations of the selected effect until canceled
  Future<void> _runAutoPlay() async {
    _autoPlay = true;
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      while (_autoPlay && currentState == ApplicationState.running) {
        await _playSound(_selectedEffect, _random.nextInt(0x100000000));
        await Future.delayed(_soundGap);
      }
    } catch (e) {
      _log.warning('Error during auto play: $e');
    }

    _autoPlay = false;
    if (currentState == ApplicationState.running) {
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    // single plays finish by themselves; the auto play loop notices the flag
    // and restores the ready state
    _autoPlay = false;
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = currentState == ApplicationState.ready;
    final bool autoRunning = _autoPlay && currentState == ApplicationState.running;

    return MaterialApp(
      title: 'Sound Effect Player',
      theme: ThemeData.dark(),
      home: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Sound Effect Player'),
            actions: [getBatteryWidget()]
          ),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _effects.map((effect) => ChoiceChip(
                    label: Text(effect),
                    selected: _selectedEffect == effect,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedEffect = effect);
                    },
                  )).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _seedController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  // the number pad has no dismiss key on some platforms, so
                  // dismiss the keyboard when the user taps anywhere else
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Seed',
                    hintText: 'Leave empty for a random seed',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear seed',
                      onPressed: () => _seedController.clear(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: ready ? run : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: autoRunning ? cancel : (ready ? _runAutoPlay : null),
                        icon: Icon(autoRunning ? Icons.stop : Icons.all_inclusive),
                        label: Text(autoRunning ? 'Stop Auto' : 'Auto Play'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _history.isEmpty
                      ? const Center(child: Text('Played sounds appear here with their seeds'))
                      : ListView.builder(
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final item = _history[index];
                            return ListTile(
                              dense: true,
                              title: Text('${item.effect} (${item.seed})'),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy seed',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: '${item.seed}'));
                                  _messengerKey.currentState?.showSnackBar(
                                      SnackBar(content: Text('Copied seed ${item.seed}')));
                                },
                              ),
                              // load this sound back into the controls for replay
                              onTap: () {
                                setState(() {
                                  _selectedEffect = item.effect;
                                  _seedController.text = '${item.seed}';
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          persistentFooterButtons: getFooterButtonsWidget(),
        ),
      ),
    );
  }
}
