import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:frame_ble/brilliant_device.dart';
import 'package:frame_msg/frame_msg.dart';
import 'package:logging/logging.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_frame_app/simple_frame_app.dart';

void main() => runApp(const MainApp());

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
  bool _playerIsInited = false;
  bool _haloPlaying = false;
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
    _player.openPlayer().then((value) {
      _log.info('Audio player initialized');
      setState(() {
        _playerIsInited = true;
      });
    });

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
      _log.severe('Error executing application logic: $e');
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
  Future<void> _playAudioOnMobile(Uint8List audioBytes, int index) async {
    if (!_player.isPlaying) {
      _log.info('Playing audio clip at index $index, length: ${audioBytes.length} bytes');
      try {
        // first 50ms/400 (16-bit) samples are bad, so skip them
        // TODO remove when firmware update trims them already
        const badSamples = 400;
        Int16List trimmedBytes = audioBytes.buffer.asInt16List();
        if (trimmedBytes.length > badSamples) {
          trimmedBytes = trimmedBytes.sublist(badSamples);
        }
        else {
          trimmedBytes = Int16List(0);
        }

        await _player.startPlayer(fromDataBuffer: trimmedBytes.buffer.asUint8List(), codec: Codec.pcm16, sampleRate: 8000, numChannels: 1, whenFinished: _stopAudio);
      } on Exception catch (e) {
        _log.severe('Error starting audio player: $e');
      }

      setState(() {
        _playingIndex = index;
      });
    }
    else {
      _log.info('Audio player is already playing another clip');
    }
  }

  /// Play the audio from the selected recording
  Future<void> _playAudioOnHaloSpeaker(Uint8List audioBytes, int index) async {
    if (!_haloPlaying) {
      _log.info('Playing audio clip at index $index on Halo speaker, length: ${audioBytes.length} bytes');
      try {
        _haloPlaying = true;

        // first 50ms/400 (16-bit) samples are bad, so skip them
        // TODO remove when firmware update trims them already
        const badSamples = 400;
        Int16List trimmedBytes = audioBytes.buffer.asInt16List();
        if (trimmedBytes.length > badSamples) {
          trimmedBytes = trimmedBytes.sublist(badSamples);
        }
        else {
          trimmedBytes = Int16List(0);
        }

        // configure the speaker for playback (we can do this multiple times)
        await frame!.sendMessage(0x40, TxCode().pack());

        final convertedBytes = trimmedBytes.buffer.asUint8List();

        final sendStopwatch = Stopwatch();
        // loop over recording and send in 25ms (400 bytes of 8kHz, 16-bit mono PCM) chunks
        const int frameSizeBytes = 400;
        for (int offset = 0; offset < convertedBytes.length; offset += frameSizeBytes) {
          sendStopwatch.reset();
          sendStopwatch.start();

          final end = (offset + frameSizeBytes < convertedBytes.length)
              ? offset + frameSizeBytes
              : convertedBytes.length;
          final chunk = convertedBytes.sublist(offset, end);
          //_log.info(() => 'Sending PCM chunk of length ${chunk.length} bytes to Halo');
          await frame!.sendAudio(chunk, awaitBtResponse: false);

          sendStopwatch.stop();

          await Future.delayed(Duration(milliseconds: 25-sendStopwatch.elapsedMilliseconds)); // 40ms for 160-byte lc3 frames, 25ms for 400-byte pcm s16 frames
        }

        await _stopHaloPlayback();

      } on Exception catch (e) {
        _log.severe('Error starting audio player: $e');
        _haloPlaying = false;
      }

      setState(() {
        _playingIndex = index;
      });
    }
    else {
      _log.info('Audio player is already playing another clip');
    }
  }

  /// Cancel the playing of the selected recording
  Future<void> _stopAudio() async {
    _log.info('Stopping audio player');
    await _player.stopPlayer();
    setState(() {
      _playingIndex = null;
    });
  }

  /// Cancel the playing of the selected recording
  Future<void> _stopHaloPlayback() async {
    _log.info('Stopping Halo speaker playback');
    await frame!.sendMessage(0x41, TxCode().pack());
    setState(() {
      _haloPlaying = false;
      _playingIndex = null;
    });
  }

  Future<void> _shareClip(Uint8List rawAudioBytes) async {
    // Share the raw bytes as a WAV file
    await Share.shareXFiles(
      [XFile.fromData(_convertToWav(rawAudioBytes), mimeType: 'audio/wav', name: 'clip.wav')],
      fileNameOverrides: ['clip.wav'],
    );
  }

  Uint8List _convertToWav(Uint8List rawAudio, {int sampleRate = 8000, int channels = 1, int bitDepth = 8}) {
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

    if (bitDepth == 8) {
      _log.info('Converting 8-bit signed PCM to unsigned PCM for WAV format');
      // For 8-bit PCM, audio data is unsigned, so we need to convert from signed to unsigned
      final unsignedAudio = Uint8List(rawAudio.length);
      for (int i = 0; i < rawAudio.length; i++) {
        unsignedAudio[i] = rawAudio[i] + 128;         // Convert signed to unsigned
      }
      wavData.add(unsignedAudio);                     // Audio data
    } else {
      _log.info('Keeping signed PCM for WAV format');
      wavData.add(rawAudio);                          // Audio data
    }

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
        title: 'Audio Clip Recorder PCM',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Audio Clip Recorder PCM'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ListView.builder(
              itemCount: _rawAudioClips.length,
              itemBuilder: (context, index) {
                return Card(
                  child: ListTile(
                    title: Text('Audio Clip ${index + 1} (${(_rawAudioClips[index].length/8000.0).toStringAsFixed(2)}s)'),
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
                              _playAudioOnMobile(_rawAudioClips[index], index);
                            },
                          ),
                          if (frame != null && frame!.type == BrilliantDeviceType.halo) IconButton(
                            icon: const Icon(Icons.headphones),
                            onPressed: () {
                              _playAudioOnHaloSpeaker(_rawAudioClips[index], index);
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
