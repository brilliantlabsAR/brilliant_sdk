import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger("RxAutoExpResult");

/// Receive handler for auto exposure and white balance data from the auto exposure algorithm
class RxAutoExpResult {

  // Frame to Phone flags
  final int autoExpFlag;
  StreamController<AutoExpResult>? _controller;

  RxAutoExpResult({
    this.autoExpFlag = 0x11,
  });

  /// Attach this RxAutoExpResult to the Frame's dataResponse characteristic stream.
  Stream<AutoExpResult> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxAutoExpResult etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw tap events into multi-taps
    _controller = StreamController();

    _controller!.onListen = () {
      dataResponseSubs = dataResponse
        .where((data) => data[0] == autoExpFlag)
        .listen((data) {
          // parse the metering data from the raw data
          _log.finer('auto exposure result detected');

          // Ensure the data length is sufficient
          if (data.length < 65) {
            _log.warning('Insufficient data length for AutoExpResult: ${data.length}');
            return;
          }

          // Extract the relevant data (bytes 1 to 65)
          List<int> relevantData = data.sublist(1, 65);

          // Create a ByteData object from the relevant data
          ByteData byteData = ByteData.sublistView(Uint8List.fromList(relevantData));

          // Unpack the data as 16 float32 values
          List<double> unpacked = List.generate(16, (i) => byteData.getFloat32(i * 4, Endian.little));

          _controller!.add(AutoExpResult(
            error: unpacked[0],
            shutter: unpacked[1],
            analogGain: unpacked[2],
            redGain: unpacked[3],
            greenGain: unpacked[4],
            blueGain: unpacked[5],
            brightness: Brightness(
              centerWeightedAverage: unpacked[6],
              scene: unpacked[7],
              matrix: Matrix(
                r: unpacked[8],
                g: unpacked[9],
                b: unpacked[10],
                average: unpacked[11],
              ),
              spot: Spot(
                r: unpacked[12],
                g: unpacked[13],
                b: unpacked[14],
                average: unpacked[15],
              ),
            ),
          ));
      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('AutoExposureResultDataResponse stream subscribed');
    };

    _controller!.onCancel = () {
      _log.fine('AutoExposureResultDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }
}

class AutoExpResult {
  final double error;
  final double shutter;
  final double analogGain;
  final double redGain;
  final double greenGain;
  final double blueGain;
  final Brightness brightness;

  AutoExpResult({
    required this.error,
    required this.shutter,
    required this.analogGain,
    required this.redGain,
    required this.greenGain,
    required this.blueGain,
    required this.brightness,
  });
}

class Brightness {
  final double centerWeightedAverage;
  final double scene;
  final Matrix matrix;
  final Spot spot;

  Brightness({
    required this.centerWeightedAverage,
    required this.scene,
    required this.matrix,
    required this.spot,
  });
}

class Matrix {
  final double r;
  final double g;
  final double b;
  final double average;

  Matrix({
    required this.r,
    required this.g,
    required this.b,
    required this.average,
  });
}

class Spot {
  final double r;
  final double g;
  final double b;
  final double average;

  Spot({
    required this.r,
    required this.g,
    required this.b,
    required this.average,
  });
}
