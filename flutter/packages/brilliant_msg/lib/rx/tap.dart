import 'dart:async';

import 'package:logging/logging.dart';

final _log = Logger("RxTap");

/// Multi-Tap data stream, returns the number of taps detected
class RxTap {

  // Frame to Phone flags
  final int tapFlag;
  final Duration threshold;
  StreamController<int>? _controller;

  RxTap({
    this.tapFlag = 0x09,
    this.threshold = const Duration(milliseconds: 300),
  });

  /// Attach this RxTap to the Frame's dataResponse characteristic stream.
  Stream<int> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxTap etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw tap events into multi-taps
    _controller = StreamController();

    // track state of multi-taps
    int lastTapTime = 0;
    int taps = 0;
    Timer? t;

    _controller!.onListen = () {
      dataResponseSubs = dataResponse
        .where((data) => data[0] == tapFlag)
        .listen((data) {
          int tapTime = DateTime.now().millisecondsSinceEpoch;
          // debounce taps that occur too close to the prior tap
          if (tapTime - lastTapTime < 40) {
            _log.finer('tap ignored - debouncing');
            lastTapTime = tapTime;
          }
          else {
            _log.finer('tap detected');
            lastTapTime = tapTime;

            taps++;
            t?.cancel();
            t = Timer(threshold, () {
              _controller!.add(taps);
              taps = 0;
            });
          }

      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('TapDataResponse stream subscribed');
    };

    _controller!.onCancel = () {
      _log.fine('TapDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }


}