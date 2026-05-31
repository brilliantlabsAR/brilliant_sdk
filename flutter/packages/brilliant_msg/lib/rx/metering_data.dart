import 'dart:async';

import 'package:logging/logging.dart';

final _log = Logger("RxMeteringData");

/// Receive handler for metering data from the camera sensor
class RxMeteringData {

  // Frame to Phone flags
  final int meteringFlag;
  StreamController<MeteringData>? _controller;

  RxMeteringData({
    this.meteringFlag = 0x12,
  });

  /// Attach this RxMeteringData to the Frame's dataResponse characteristic stream.
  Stream<MeteringData> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxMeteringData etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw tap events into multi-taps
    _controller = StreamController();

    _controller!.onListen = () {
      dataResponseSubs = dataResponse
        .where((data) => data[0] == meteringFlag)
        .listen((data) {
          // parse the metering data from the raw data
          _log.finer('metering data detected');
          _controller!.add(MeteringData(
            spotR: data[1],
            spotG: data[2],
            spotB: data[3],
            matrixR: data[4],
            matrixG: data[5],
            matrixB: data[6],
          ));
      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('MeteringDataResponse stream subscribed');
    };

    _controller!.onCancel = () {
      _log.fine('MeteringDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }
}

class MeteringData {
  final int spotR;
  final int spotG;
  final int spotB;
  final int matrixR;
  final int matrixG;
  final int matrixB;

  MeteringData({
    required this.spotR,
    required this.spotG,
    required this.spotB,
    required this.matrixR,
    required this.matrixG,
    required this.matrixB,
  });
}
