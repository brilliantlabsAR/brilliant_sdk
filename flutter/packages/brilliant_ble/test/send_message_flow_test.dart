// Unit tests for sendMessage() flow control on Halo. No device required: a
// fake TX characteristic models Halo's data receive queue, which drops a write
// without response that does not fit, and a consumer loop stands in for
// data.lua, acknowledging each packet once its (deliberately slow) handler has
// taken it.
import 'dart:async';
import 'dart:typed_data';

import 'package:brilliant_ble/brilliant_ble.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

const ack = [0x01, 0x01, 0x00, 0x00];
const ackFailed = [0x01, 0x01, 0x00, 0x01];

class FakeDevice implements BluetoothDevice {
  FakeDevice(this._mtu);

  final int _mtu;
  final links = StreamController<BluetoothConnectionState>.broadcast();

  @override
  int get mtuNow => _mtu;

  @override
  Stream<BluetoothConnectionState> get connectionState => links.stream;

  @override
  Future<void> disconnect(
          {int timeout = 35, bool queue = true, int androidDelay = 2000}) async =>
      links.add(BluetoothConnectionState.disconnected);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// RX characteristic: notifications the test or the fake device emits
class FakeRx implements BluetoothCharacteristic {
  final notifications = StreamController<List<int>>.broadcast();

  void notify(List<int> value) => notifications.add(value);

  @override
  Stream<List<int>> get onValueReceived => notifications.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// TX characteristic that queues data writes the way Halo firmware does
class FakeHaloTx implements BluetoothCharacteristic {
  FakeHaloTx(this.rx, {this.queueSize = 4096, this.handlerDelay = Duration.zero});

  final FakeRx rx;
  final int queueSize;
  final Duration handlerDelay;
  bool autoAck = true;

  final queue = <List<int>>[]; // packets waiting for the handler, marker stripped
  int queuedBytes = 0;
  final received = <List<int>>[]; // packets the handler took, in order
  int dropped = 0;
  int maxQueued = 0;
  final writeSizes = <int>[];
  Completer<void>? _wake;
  bool _running = false;

  @override
  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) async {
    final data = List<int>.from(value); // the caller reuses its buffer
    writeSizes.add(data.length);
    await Future<void>.delayed(Duration.zero);
    if (data.first != 0x01) {
      return;
    }
    final frame = data.sublist(1);
    if (queuedBytes + frame.length + 2 > queueSize) {
      dropped++; // what Halo does to a write without response
      return;
    }
    queue.add(frame);
    queuedBytes += frame.length + 2;
    if (queuedBytes > maxQueued) maxQueued = queuedBytes;
    final wake = _wake;
    _wake = null;
    wake?.complete();
  }

  /// data.lua: takes each queued packet, handles it, then ACKs it
  Future<void> handler() async {
    _running = true;
    while (_running) {
      while (queue.isEmpty) {
        _wake = Completer<void>();
        await _wake!.future;
        if (!_running) return;
      }
      final frame = queue.removeAt(0);
      queuedBytes -= frame.length + 2;
      await Future<void>.delayed(handlerDelay);
      received.add(frame);
      if (autoAck) rx.notify(ack);
    }
  }

  void stop() {
    _running = false;
    _wake?.complete();
    _wake = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Halo {
  Halo({int mtu = 515, int queueSize = 4096, Duration handlerDelay = Duration.zero})
      : device = FakeDevice(mtu),
        rx = FakeRx() {
    tx = FakeHaloTx(rx, queueSize: queueSize, handlerDelay: handlerDelay);
    ble = BrilliantDevice(
      state: BrilliantConnectionState.connected,
      device: device,
      maxStringLength: mtu - 5,
      maxDataLength: mtu - 6,
      type: BrilliantDeviceType.halo,
    )
      ..txChannel = tx
      ..rxChannel = rx;
  }

  final FakeDevice device;
  final FakeRx rx;
  late final FakeHaloTx tx;
  late final BrilliantDevice ble;
}

/// Undoes sendMessage() framing: [code, len16, data...] then [code, data...]
List<(int, List<int>)> reassemble(List<List<int>> frames) {
  final messages = <(int, List<int>)>[];
  int? code;
  int size = 0;
  List<int> data = [];
  for (final frame in frames) {
    if (code == null) {
      code = frame[0];
      size = frame[1] << 8 | frame[2];
      data = frame.sublist(3);
    } else {
      data.addAll(frame.sublist(1));
    }
    if (data.length == size) {
      messages.add((code, data));
      code = null;
    }
  }
  return messages;
}

void main() {
  test('write size fills whole link-layer packets', () {
    expect(bleWriteSize(512), 495);
    expect(bleWriteSize(494), 244);
    expect(bleWriteSize(244), 244);
    expect(bleWriteSize(243), 243); // less than one packet: unchanged
    expect(bleWriteSize(20), 20);
  });

  test('ACKs are matched exactly', () {
    expect(isDataAck(ack), isTrue);
    expect(isDataAck(ackFailed), isTrue);
    expect(isDataAck([0x01, 0x0a, 0x00, 0x00]), isFalse);
    expect(isDataAck([0x01, 0x01, 0x00]), isFalse);
    expect(isDataAck([0x01, 0x01, 0x00, 0x00, 0x00]), isFalse);
    expect(isDataAck([0x02, 0x01, 0x00, 0x00]), isFalse);
  });

  for (final delayMs in [0, 2, 10]) {
    test('slow handler loses nothing (${delayMs}ms per packet)', () async {
      final halo = Halo(handlerDelay: Duration(milliseconds: delayMs));
      final payloads = [
        for (final (i, size) in [1, 300, 8192, 5000, 2].indexed)
          List<int>.filled(size, i)
      ];
      unawaited(halo.tx.handler());
      for (final (i, payload) in payloads.indexed) {
        await halo.ble.sendMessage(0x20 + i, Uint8List.fromList(payload));
      }
      await halo.ble.waitForAcks();
      halo.tx.stop();

      expect(halo.tx.dropped, 0);
      expect(halo.tx.maxQueued, lessThanOrEqualTo(halo.tx.queueSize));
      final messages = reassemble(halo.tx.received);
      expect(messages.length, payloads.length);
      for (final (i, payload) in payloads.indexed) {
        expect(messages[i].$1, 0x20 + i);
        expect(messages[i].$2, payload);
      }
      // every data write fills whole link-layer packets, except a message's last
      expect(halo.tx.writeSizes.reduce((a, b) => a > b ? a : b), 495);
    });
  }

  test('a bigger receive buffer allows more in flight', () async {
    final halo = Halo(queueSize: 16384, handlerDelay: const Duration(milliseconds: 1));
    halo.ble.receiveBufferSize = 16384;
    unawaited(halo.tx.handler());
    await halo.ble.sendMessage(0x20, Uint8List(20000));
    await halo.ble.waitForAcks();
    halo.tx.stop();

    expect(halo.tx.dropped, 0);
    expect(halo.tx.maxQueued, greaterThan(4096));
  });

  test('a receive buffer size larger than the device\'s drops data', () async {
    // The window really is what prevents loss: overstate the queue and the
    // fake device, like Halo, drops what doesn't fit
    final halo = Halo(handlerDelay: const Duration(milliseconds: 5));
    halo.ble.receiveBufferSize = 16384;
    unawaited(halo.tx.handler());
    await halo.ble.sendMessage(0x20, Uint8List(20000)).catchError((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 500));
    halo.tx.stop();

    expect(halo.tx.dropped, greaterThan(0));
  });

  test('a failed ACK is thrown at once and not by the next call', () async {
    final halo = Halo();
    await halo.ble.sendMessage(0x20, Uint8List(1)); // one packet outstanding
    final stopwatch = Stopwatch()..start();
    final wait = halo.ble.waitForAcks();
    halo.rx.notify(ackFailed);
    await expectLater(
        wait,
        throwsA(isA<BrilliantBluetoothException>()
            .having((e) => e.msg, 'msg', contains('failed to process'))));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    // the failure is reported once only
    await halo.ble.waitForAcks();
  });

  test('a failure ACK during a send is thrown by that send', () async {
    final halo = Halo();
    halo.tx.autoAck = false;
    // 20000 bytes need more packets than the window allows unacknowledged
    final send = halo.ble.sendMessage(0x20, Uint8List(20000));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    halo.rx.notify(ackFailed);
    await expectLater(
        send,
        throwsA(isA<BrilliantBluetoothException>()
            .having((e) => e.msg, 'msg', contains('failed to process'))));
  });

  test('other data still reaches sendData while ACKs are outstanding', () async {
    final halo = Halo();
    halo.tx.autoAck = false;
    final seen = <List<int>>[];
    final sub = halo.ble.dataResponse.listen(seen.add);

    // two packets outstanding
    await halo.ble.sendMessage(0x20, Uint8List(600));
    // what sendData() does once ACKs are settled; called directly here to
    // overlap it with the outstanding ACKs
    var responded = false;
    final send = halo.ble
        .sendDataRawOnCharacteristic(Uint8List.fromList([0x01, 0x10]), halo.tx)
        .then((_) => responded = true);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    halo.rx.notify(ack);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(responded, isFalse, reason: 'an ACK is not a data response');

    // an app message (code 0x0a) is not an ACK, even mid-transfer
    halo.rx.notify([0x01, 0x0a, 0x00, 0x00]);
    await send;

    // one ACK still outstanding
    final wait = halo.ble.waitForAcks();
    halo.rx.notify(ack);
    await wait.timeout(const Duration(seconds: 1));

    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    // user streams see everything, ACKs included, as before
    expect(seen, [
      [0x01, 0x00, 0x00],
      [0x0a, 0x00, 0x00],
      [0x01, 0x00, 0x00],
    ]);
  });

  test('a device that stops acknowledging times out', () async {
    final halo = Halo();
    // no consumer: nothing is ever acknowledged
    await expectLater(
        halo.ble.sendMessage(0x20, Uint8List(20000)),
        throwsA(isA<BrilliantBluetoothException>()
            .having((e) => e.msg, 'msg', contains('Timeout'))));
    // the outstanding count was reset
    await halo.ble.waitForAcks(timeout: const Duration(milliseconds: 10));
  });

  test('a disconnect fails the waiters at once', () async {
    final halo = Halo();
    await halo.ble.sendMessage(0x20, Uint8List(1));
    final wait = halo.ble.waitForAcks();
    halo.device.links.add(BluetoothConnectionState.disconnected);
    await expectLater(
        wait.timeout(const Duration(seconds: 1)),
        throwsA(isA<BrilliantBluetoothException>()
            .having((e) => e.msg, 'msg', contains('Disconnected'))));
  });

  test('a control signal does not wait on a stuck device', () async {
    final halo = Halo();
    await halo.ble.sendMessage(0x20, Uint8List(1000)); // 3 packets, no consumer
    halo.tx.writeSizes.clear();
    final stopwatch = Stopwatch()..start();
    // sendString writes with response through the same fake
    await halo.ble.sendBreakSignal();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(halo.tx.writeSizes, [1]); // the break went out
  });
}
