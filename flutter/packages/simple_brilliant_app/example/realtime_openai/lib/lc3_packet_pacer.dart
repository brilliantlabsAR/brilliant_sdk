import 'dart:collection';
import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';

final _log = Logger("packet_pacer");


class Lc3PacketPacer {
  final Queue<Uint8List> _buffer = Queue();
  Timer? _pacerTimer;
  final int intervalMs;
  bool _reportWhenDone = false;
  Function? _doneCallback;

  // Max ms of audio to buffer before dropping oldest packets
  // NB: if whole clips are encoded for playback, this buffer should
  // be large (e.g. 30s), so we're just protecting against infinite buildup
  final int maxBufferDelayFrames;
  
  // Function to call to send data
  final Function(Uint8List) sendAudio;

  /// Creates an LC3 packet pacer that sends packets at regular intervals.
  /// [intervalMs] is the target interval between packets (e.g. 10ms).
  /// [maxBufferDelayFrames] is the max buffer size in lc3 frames before dropping packets (e.g. 3000 for 30s at 10ms).
  /// [sendAudio] is the function to call to send each packet.
  Lc3PacketPacer({required this.intervalMs, required this.maxBufferDelayFrames, required this.sendAudio});

  void onNewPacketReceived(Uint8List packet) {
    // 1. Add to buffer
    _buffer.add(packet);

    // 2. Safety: Prevent infinite lag (and memory exhaustion)
    // If buffer gets too big (e.g., connection hiccup), drop oldest packets.
    // 20 packets * 10ms = 200ms latency cap.
    if (_buffer.length > maxBufferDelayFrames) {
      _buffer.removeFirst(); 
      _log.finer("Dropping audio packet to reduce latency");
    }

    // 3. Start the pacer if not running
    if (_pacerTimer == null || !_pacerTimer!.isActive) {
      _startPacing();
    }
  }

  void setDoneCallback(Function doneCallback) {
    // When the user indicates no more packets will be added,
    // we can check to see if the buffer is already empty
    // (already played out) and call the doneCallback immediately.
    // Otherwise, we set a flag so that the periodic timer checks
    // for buffer emptiness on each tick,and calls the doneCallback when empty.
    if (_buffer.isEmpty) {
      doneCallback();
      _reportWhenDone = false;
    }
    else {
      _reportWhenDone = true;
      _doneCallback = doneCallback;
    }
  }

  void _startPacing() {
    _pacerTimer?.cancel();
    
    // Use periodic timer for the "metronome" beat
    _pacerTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) async {
      if (_buffer.isEmpty) {
        // Buffer underrun: Stop timer to save resources
        timer.cancel();

        if (_reportWhenDone && _doneCallback != null) {
          _doneCallback!();
          _reportWhenDone = false;
          _doneCallback = null;
        }

        return;
      }

      final packet = _buffer.removeFirst();
      
      try {
        await sendAudio(packet);
        _log.finest(() => "${DateTime.now().toIso8601String()}: Sent LC3 packet of size ${packet.length}");
      } catch (e) {
        _log.info("BLE Error: $e");
      }
    });
  }

  /// Number of packets currently queued for sending
  int get bufferedFrames => _buffer.length;

  /// Discard all queued packets without stopping the pacer
  /// (used when the user interrupts the model's response)
  void clear() {
    _buffer.clear();
  }

  void dispose() {
    _pacerTimer?.cancel();
    _buffer.clear();
  }
}