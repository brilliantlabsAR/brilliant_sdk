import 'dart:async';

import 'package:logging/logging.dart';

final _log = Logger("RxClick");

/// Click types
enum ClickType {  
  single,
  double,
  long
}

/// Click data stream, returns the type of Click detected
class RxClick {

  // Frame to Phone flags
  final int clickFlag;
  StreamController<ClickType>? _controller;

  RxClick({
    this.clickFlag = 0x0B,
  });

  /// Attach this RxClick to the device's dataResponse characteristic stream.
  Stream<ClickType> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxClick etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw click events into ClickTypes
    _controller = StreamController();

    _controller!.onListen = () {
      dataResponseSubs = dataResponse
        .where((data) => data[0] == clickFlag)
        .listen((data) {
          if (data.length == 2) {
            _log.finer(() => 'Click detected: ${data[1]}');
            switch (data[1]) {
              case 1:
                _log.finer(' single');
                _controller!.add(ClickType.single);
                break;
              case 2:
                _log.finer(' double');
                _controller!.add(ClickType.double);
                break;
              case 3:
                _log.finer(' long');
                _controller!.add(ClickType.long);
                break;
              default:
                _log.finer(() => ' unknown Click type ${data[1]}');
            }
          }
      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('ClickDataResponse stream subscribed');
    };

    _controller!.onCancel = () {
      _log.fine('ClickDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }
}