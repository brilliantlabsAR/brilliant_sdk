import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:share_plus/share_plus.dart';
import 'package:frame_msg/rx/audio.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterBluePlus.setLogLevel(LogLevel.info);
  runApp(const MainApp());
}

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<Uint8List>? audioClipStreamSubs;
  final List<Uint8List> _rawAudioClips = [];
  final _player = FlutterSoundPlayer();
  int? _playingIndex;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  void dispose() async {
    await audioClipStreamSubs?.cancel();
    await _player.stopPlayer();
    await _player.closePlayer();
    super.dispose();
  }

  /// Start recording audio on Frame
  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // attach a handler to listen for the audio clip
      await audioClipStreamSubs?.cancel();
      audioClipStreamSubs = RxAudio().attach(frame!.dataResponse).listen((audioData) {
        _log.info('Clip length: ${audioData.length} bytes');
        setState(() {
          _rawAudioClips.add(audioData);
          currentState = ApplicationState.ready;
        });
      });

      // tell Frame to start streaming audio
      await frame!.sendMessage(0x30, TxCode().pack());

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// Stop recording audio on Frame
  @override
  Future<void> cancel() async {

    // in canceling state, the user can't click other buttons to start/stop
    // and the state will return to ready when the audio data is all received
    setState(() {
      currentState = ApplicationState.canceling;
    });

    // tell Frame to stop streaming audio
    await frame!.sendMessage(0x31, TxCode().pack());
  }

  /// Play the audio from the selected recording
  Future<void> _playAudio(Uint8List audioBytes, int index) async {
    if (!_player.isPlaying) {

      try {
        await _player.openPlayer();
        await _player.startPlayer(fromDataBuffer: audioBytes, codec: Codec.pcm8, sampleRate: 8000, numChannels: 1);
      } on Exception catch (e) {
        _log.severe('Error starting audio player: $e');
      }

      setState(() {
        _playingIndex = index;
      });
    }

    //if (_player.isPlaying) {
      // TODO skip the pop at the beginning of the recording? or not?
      //await _player.feed(Uint8List.fromList(audioBytes.skip(2700).toList()));
      //await _player.feedUint8FromStream(audioBytes);
    //}

    // no obvious callback from raw_sound when playback finishes, so since we know
    // how long the clip is, we can wait then update the UI (show play button instead of stop)
    // but be aware that the user might have stopped playback early, so bail out
    int clipDurationMs = (audioBytes.length/16.0).toInt();
    int waited = 0;

    while (_player.isPlaying && waited < clipDurationMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    await _stopAudio();
  }

  /// Cancel the playing of the selected recording
  Future<void> _stopAudio() async {
    if (_player.isPlaying) {
      await _player.stopPlayer();
      setState(() {
        _playingIndex = null;
      });
    }
  }

  Future<void> _shareClip(Uint8List rawAudioBytes) async {
    // Share the raw bytes as a WAV file
    await Share.shareXFiles(
      [XFile.fromData(_convertToWav(rawAudioBytes), mimeType: 'audio/wav', name: 'clip.wav')],
      fileNameOverrides: ['clip.wav'],
    );
  }

  Uint8List _convertToWav(Uint8List rawAudio, {int sampleRate = 8000, int channels = 1, int bitDepth = 16}) {
    // Calculate the total size of the WAV file
    int dataSize = rawAudio.length;
    int headerSize = 44; // Standard WAV header is 44 bytes
    int fileSize = headerSize + dataSize;

    // Create a buffer to hold the header and audio data
    final wavData = BytesBuilder();

    // RIFF header
    wavData.add(Uint8List.fromList('RIFF'.codeUnits)); // ChunkID
    wavData.add(_intToBytes(fileSize - 8, 4));         // ChunkSize
    wavData.add(Uint8List.fromList('WAVE'.codeUnits)); // Format

    // fmt sub-chunk
    wavData.add(Uint8List.fromList('fmt '.codeUnits)); // Subchunk1ID
    wavData.add(_intToBytes(16, 4));                   // Subchunk1Size (PCM)
    wavData.add(_intToBytes(1, 2));                    // AudioFormat (1 for PCM)
    wavData.add(_intToBytes(channels, 2));             // NumChannels
    wavData.add(_intToBytes(sampleRate, 4));           // SampleRate
    wavData.add(_intToBytes(sampleRate * channels * (bitDepth ~/ 8), 4)); // ByteRate
    wavData.add(_intToBytes(channels * (bitDepth ~/ 8), 2));              // BlockAlign
    wavData.add(_intToBytes(bitDepth, 2));             // BitsPerSample

    // data sub-chunk
    wavData.add(Uint8List.fromList('data'.codeUnits)); // Subchunk2ID
    wavData.add(_intToBytes(dataSize, 4));             // Subchunk2Size
    wavData.add(rawAudio);                             // Audio data

    // Return the full WAV data as a Uint8List
    return wavData.toBytes();
  }

  // Helper function to convert an integer to a byte list of given length
  Uint8List _intToBytes(int value, int length) {
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[i] = (value >> (8 * i)) & 0xFF;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Frame Audio Recorder',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Frame Audio Recorder'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ListView.builder(
              itemCount: _rawAudioClips.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    title: Text('Audio Clip ${index + 1} (${(_rawAudioClips[index].length/2/8000.0).toStringAsFixed(2)}s)'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min, // Ensures the row takes up minimum space
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: () {
                            _shareClip(_rawAudioClips[index]);
                          },
                        ),
                        _playingIndex == index ?
                          IconButton(
                            icon: const Icon(Icons.stop),
                            onPressed: () {
                              _stopAudio();
                            },
                           ) :
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () {
                              _playAudio(_rawAudioClips[index], index);
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.mic), const Icon(Icons.stop)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
