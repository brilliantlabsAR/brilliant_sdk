import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:brilliant_msg/rx/imu.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  group('RxIMU', () {
    test('parses 32-bit float IMU data correctly', () async {
      final controller = StreamController<List<int>>();
      final rxImu = RxIMU();
      final stream = rxImu.attach(controller.stream);

      IMUData? lastData;
      stream.listen((data) {
        lastData = data;
      });

      // Construct a packet with known float values
      // Flag (1) + Pad (1) + 6 * 4 bytes = 26 bytes
      final buffer = ByteData(26);
      buffer.setUint8(0, 0x0A); // flag
      buffer.setUint8(1, 0x00); // padding

      // Set floats (CompX, CompY, CompZ, AccelX, AccelY, AccelZ)
      // Using known values
      buffer.setFloat32(2, 10.5, Endian.little);
      buffer.setFloat32(6, -20.25, Endian.little);
      buffer.setFloat32(10, 30.0, Endian.little);
      buffer.setFloat32(14, 0.1, Endian.little);
      buffer.setFloat32(18, -9.8, Endian.little);
      buffer.setFloat32(22, 123.456, Endian.little);

      controller.add(buffer.buffer.asUint8List());

      // Wait for stream to process
      await Future.delayed(Duration(milliseconds: 100));

      expect(lastData, isNotNull);
      
      // Check compass values (allow for float precision issues)
      expect(lastData!.raw!.compass.$1, closeTo(10.5, 0.0001));
      expect(lastData!.raw!.compass.$2, closeTo(-20.25, 0.0001));
      expect(lastData!.raw!.compass.$3, closeTo(30.0, 0.0001));

      // Check accel values
      expect(lastData!.raw!.accel.$1, closeTo(0.1, 0.0001));
      expect(lastData!.raw!.accel.$2, closeTo(-9.8, 0.0001));
      expect(lastData!.raw!.accel.$3, closeTo(123.456, 0.0001));

      // Check smoothed values (buffer size 1, should match raw)
      expect(lastData!.compass.$1, closeTo(10.5, 0.0001));
      expect(lastData!.accel.$2, closeTo(-9.8, 0.0001));

      await controller.close();
    });

    test('ignores packets with wrong flag', () async {
        final controller = StreamController<List<int>>();
      final rxImu = RxIMU();
      final stream = rxImu.attach(controller.stream);

      bool receivedData = false;
      stream.listen((data) {
        receivedData = true;
      });

      final buffer = ByteData(26);
      buffer.setUint8(0, 0x99); // Wrong flag
      // ... fill rest ...

      controller.add(buffer.buffer.asUint8List());
      await Future.delayed(Duration(milliseconds: 50));
      expect(receivedData, isFalse);
       await controller.close();
    });

    test('ignores short packets', () async {
      final controller = StreamController<List<int>>();
      final rxImu = RxIMU();
      final stream = rxImu.attach(controller.stream);

      bool receivedData = false;
      stream.listen((data) {
        receivedData = true;
      });

      final buffer = ByteData(20); // Too short
      buffer.setUint8(0, 0x0A);
      
      controller.add(buffer.buffer.asUint8List());
      await Future.delayed(Duration(milliseconds: 50));
      expect(receivedData, isFalse);
      await controller.close();
    });
  });
}
