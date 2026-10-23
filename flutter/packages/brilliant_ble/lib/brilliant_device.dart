
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:brilliant_ble/brilliant_bluetooth.dart';
import 'package:logging/logging.dart';

import 'brilliant_bluetooth_exception.dart';
import 'brilliant_connection_state.dart';

final _log = Logger("Bluetooth");

// Link-layer data PDUs carry at most 251 bytes, and the first PDU of an ATT
// write also carries the 4-byte L2CAP and 3-byte ATT headers
const int _llPduPayload = 251;
const int _attWriteOverhead = 7;

/// Default size in bytes of Halo's data receive queue
/// (`frame.bluetooth.receive_buffer_size()` on the device)
const int haloReceiveBufferSize = 4096;

/// Returns the largest ATT write value, at most [maxWrite] bytes, that exactly
/// fills whole link-layer packets (251k - 7 bytes: 244, 495, ...). A write
/// that overruns a packet boundary by a few bytes spends a whole extra packet
/// of airtime on them. Returns [maxWrite] when not even one packet fits.
int bleWriteSize(int maxWrite) {
  final packets = (maxWrite + _attWriteOverhead) ~/ _llPduPayload;
  if (packets == 0) {
    return maxWrite;
  }
  return packets * _llPduPayload - _attWriteOverhead;
}

/// Whether [notification] (as received on the RX characteristic, including
/// its 0x01 data marker) is data.lua's per-packet ACK: `01 01 00 00`, or
/// `01 01 00 01` when the device failed to process the packet.
bool isDataAck(List<int> notification) {
  return notification.length == 4 &&
      notification[0] == 0x01 &&
      notification[1] == 0x01 &&
      notification[2] == 0x00;
}

enum BrilliantDeviceType {
  frame,
  halo,
  unknown,
}

class BrilliantDevice {

  BluetoothDevice device;
  BrilliantConnectionState state;
  int? maxStringLength;
  int? maxDataLength;
  BrilliantDeviceType type;

  BluetoothCharacteristic? txChannel;
  BluetoothCharacteristic? rxChannel;
  BluetoothCharacteristic? audioTxChannel;

  /// Size in bytes of the device's data receive queue (Halo only).
  /// [sendMessage] keeps no more packets unacknowledged than fit in it, which
  /// is what keeps a slow device-side handler from losing data. Set it to
  /// match a device app that calls `frame.bluetooth.receive_buffer_size()`;
  /// larger values allow faster sends.
  int receiveBufferSize = haloReceiveBufferSize;

  // sendMessage() flow control on Halo: packets written but not yet
  // acknowledged by data.lua, and whether one of them was reported as failed
  int _acksOutstanding = 0;
  bool _ackFailed = false;
  // completed (true) on each ACK, or (false) if the link drops
  Completer<bool>? _ackSignal;
  // a sendData() awaiting the device's data response
  Completer<List<int>>? _pendingDataResponse;
  // listening to the RX channel and link state only while something above
  // is outstanding
  StreamSubscription<List<int>>? _rxSubscription;
  StreamSubscription<BluetoothConnectionState>? _linkSubscription;

  BrilliantDevice({
    required this.state,
    required this.device,
    this.maxStringLength,
    this.maxDataLength,
    this.type = BrilliantDeviceType.unknown,
  });

  // to enable reconnect()
  String get uuid => device.remoteId.str;

  Stream<BrilliantDevice> get connectionState {
    return FlutterBluePlus.events.onConnectionStateChanged
        .where((event) =>
            event.connectionState == BluetoothConnectionState.connected ||
            (event.connectionState == BluetoothConnectionState.disconnected &&
                event.device.disconnectReason != null &&
                event.device.disconnectReason!.code != 23789258))
        .asyncMap((event) async {
      if (event.connectionState == BluetoothConnectionState.connected) {
        _log.info("Connection state stream: Connected");
        try {
          return await BrilliantBluetooth.enableServices(event.device);
        } catch (error) {
          _log.warning("Connection state stream: Invalid due to $error");
          return Future.error(BrilliantBluetoothException(error.toString()));
        }
      }
      _log.info(
          "Connection state stream: Disconnected due to ${event.device.disconnectReason!.description}");
      // Auto-reconnect on Android for non-user-initiated disconnects only.
      // code == 23789258 is FlutterBluePlus's bmUserCanceledErrorCode (filtered
      // out upstream by .where()), but code == 0 (GATT_SUCCESS/"success") is
      // what Android reports when the local host calls gatt.disconnect() — i.e.
      // a programmatic/user-initiated disconnect. Reconnecting in that case
      // causes immediate spurious reconnection after an intentional disconnect.
      if (Platform.isAndroid &&
          event.device.disconnectReason!.code != 0) {
        event.device.connect(timeout: const Duration(days: 365));
      }
      return BrilliantDevice(
        state: BrilliantConnectionState.disconnected,
        device: event.device,
      );
    });
  }


  // logs each string message (messages without the 0x01 first byte) and provides a stream of the utf8-decoded strings
  // Lua error strings come through here too, so logging at info
  Stream<String> get stringResponse {
    // changed to only listen for data coming through the Frame's rx characteristic, not all attached devices as before
    return rxChannel!.onValueReceived
        .where((event) => event[0] != 0x01)
        .map((event) {
      if (event[0] != 0x02) {
        _log.info(() => "Received string: ${utf8.decode(event)}");
      }
      return utf8.decode(event);
    });
  }

  Stream<List<int>> get dataResponse {
    // changed to only listen for data coming through the Frame's rx characteristic, not all attached devices as before
    return rxChannel!.onValueReceived
        .where((event) => event[0] == 0x01)
        .map((event) {
      _log.finest(() => "Received data: ${event.sublist(1)}");
      return event.sublist(1);
    });
  }

  /// Listens to the RX channel (and the link state) only while ACKs or a data
  /// response are outstanding, so a stale BrilliantDevice holds no listeners
  void _updateRxListener() {
    final needed = _acksOutstanding > 0 || _pendingDataResponse != null;
    if (needed && _rxSubscription == null) {
      _rxSubscription = rxChannel!.onValueReceived.listen(_onRxValue);
      _linkSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onLinkLost();
        }
      });
    } else if (!needed && _rxSubscription != null) {
      unawaited(_rxSubscription!.cancel());
      unawaited(_linkSubscription?.cancel());
      _rxSubscription = null;
      _linkSubscription = null;
    }
  }

  /// Sorts each RX notification: a data.lua ACK is counted while any are
  /// outstanding, and kept from a pending sendData() response. User streams
  /// ([dataResponse], [stringResponse]) still see every notification.
  void _onRxValue(List<int> value) {
    if (value.isEmpty || value[0] != 0x01) {
      return;
    }
    if (_acksOutstanding > 0 && isDataAck(value)) {
      _acksOutstanding--;
      if (value[3] != 0) {
        _ackFailed = true;
      }
      _signalAck(true);
    } else if (_pendingDataResponse != null) {
      final response = _pendingDataResponse!;
      _pendingDataResponse = null;
      response.complete(value.sublist(1));
    }
    _updateRxListener();
  }

  /// Wakes anything awaiting ACKs or a data response so it fails now, not at
  /// its timeout
  void _onLinkLost() {
    _acksOutstanding = 0;
    _ackFailed = false;
    _signalAck(false);
    final response = _pendingDataResponse;
    _pendingDataResponse = null;
    response?.completeError(const BrilliantBluetoothException(
        "Disconnected while awaiting a data response"));
    _updateRxListener();
  }

  void _signalAck(bool linkUp) {
    final signal = _ackSignal;
    _ackSignal = null;
    signal?.complete(linkUp);
  }

  /// Forgets the outstanding ACKs. If the device sends them later anyway,
  /// they can be miscounted against a later sendMessage() (or, with none
  /// outstanding, be taken as a sendData() response); that is acceptable
  /// after a timeout, a failure or a break/reset, where the device app's
  /// state is already lost.
  void _resetAcks() {
    _acksOutstanding = 0;
    _ackFailed = false;
    _signalAck(true);
    _updateRxListener();
  }

  /// Waits until at most [maxOutstanding] sendMessage() packets are
  /// unacknowledged. Throws as soon as the device reports a failed packet,
  /// if it stops acknowledging for [timeout], or if the link drops.
  Future<void> _awaitAcks(int maxOutstanding,
      {Duration timeout = const Duration(seconds: 5)}) async {
    while (true) {
      if (_ackFailed) {
        _resetAcks();
        throw const BrilliantBluetoothException(
            "Device failed to process a message (see its print output)");
      }
      if (_acksOutstanding <= maxOutstanding) {
        return;
      }
      final signal = _ackSignal ??= Completer<bool>();
      final bool linkUp;
      try {
        linkUp = await signal.future.timeout(timeout);
      } on TimeoutException {
        if (_ackFailed) {
          continue;
        }
        _resetAcks();
        throw const BrilliantBluetoothException(
            "Timeout waiting for data response");
      }
      if (!linkUp) {
        throw const BrilliantBluetoothException(
            "Disconnected while awaiting a data response");
      }
    }
  }

  /// Waits until the device has acknowledged every packet [sendMessage] has
  /// sent, i.e. its data handler has taken them all in.
  ///
  /// On Halo, sendMessage() returns once its last packet is written, so that
  /// consecutive messages stream back to back. Every other call that talks
  /// to the device waits for this first, so data is always processed before,
  /// say, a break signal; call it directly to wait for that point.
  ///
  /// Throws a [BrilliantBluetoothException] if the device reports a failed
  /// packet, stops acknowledging for [timeout], or disconnects.
  Future<void> waitForAcks({Duration timeout = const Duration(seconds: 5)}) {
    return _awaitAcks(0, timeout: timeout);
  }

  /// Before a control signal or disconnect: wait briefly, but a stuck device
  /// app is exactly what break/reset/remove are for, so never fail on it
  Future<void> _settleAcks() async {
    try {
      await _awaitAcks(0, timeout: const Duration(seconds: 1));
    } catch (_) {
      _resetAcks();
    }
  }

  Future<void> disconnect() async {
    _log.info("Disconnecting");
    try {
      await _settleAcks();
      await device.disconnect();
    } catch (_) {}
  }

  Future<void> clearDisplay() async {
    _log.fine("Sending clearDisplay");
    if (type == BrilliantDeviceType.halo) {
      await sendString(
          'frame.display.clear()print(1)',
          awaitResponse: true,
          log: false);
    }
    else{
      await sendString(
          'frame.display.bitmap(1,1,4,2,15,"\\xFF")frame.display.show()print(1)',
          awaitResponse: true,
          log: false);
    }
  }

  /// Checks if Lua is in the REPL/break by sending a simple print command and expecting a response.
  /// If Lua is in the REPL/break state, it will respond with the printed output and we return true.
  /// If a Lua main loop is running, it will not respond to the print command within the short timeout, and we return false.
  Future<bool> isLuaInReplState({Duration timeout = const Duration(milliseconds: 200)}) async{
    try {
      final response = await sendString("print(1)", awaitResponse: true, log: false);
      return response != null && response == "1";
    } on BrilliantBluetoothException catch (e) {
      if (e.msg == "Timeout waiting for string response") {
        return false;
      }
      else {
        rethrow;
      }
    }
  }

  /// Discards any unsolicited print output currently arriving on the channel
  /// (e.g. the 'interrupted'/reboot banner produced by a break or reset), so
  /// the next `sendString(awaitResponse: true)` receives a clean response
  /// rather than the stray banner.
  ///
  /// Bounded so it never hangs: returns after [quiet] of silence, or [maxTotal]
  /// at the latest. An idle device emits nothing, so the common case costs a
  /// single quiet window. A break only prints 'interrupted' when it actually
  /// interrupts a running chunk, and the banner can span more than one
  /// notification, so we soak up everything until the channel goes quiet rather
  /// than awaiting a single line.
  Future<void> drainPrintChannel({
    Duration quiet = const Duration(milliseconds: 250),
    Duration maxTotal = const Duration(milliseconds: 1500),
  }) async {
    if (rxChannel == null) return;
    final done = Completer<void>();
    Timer? quietTimer;
    void restartQuiet() {
      quietTimer?.cancel();
      quietTimer = Timer(quiet, () {
        if (!done.isCompleted) done.complete();
      });
    }

    final sub = stringResponse.listen((_) => restartQuiet());
    restartQuiet(); // start the silence clock even if nothing ever arrives
    final cap = Timer(maxTotal, () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
    } finally {
      quietTimer?.cancel();
      cap.cancel();
      await sub.cancel();
    }
  }

  Future<void> sendBreakSignal() async {
    _log.info("Sending break signal");
    await _settleAcks();
    await sendString("\x03", awaitResponse: false, log: false);
    // short delay to allow the break to complete on Frame/Halo before sending Lua commands
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> sendResetSignal() async {
    _log.info("Sending reset signal");
    await _settleAcks();
    await sendString("\x04", awaitResponse: false, log: false);
    if (type == BrilliantDeviceType.halo) {
      await Future.delayed(const Duration(milliseconds: 200));
    } else {
      // Frame takes ~200ms reset
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> sendRemoveSignal() async {
    if (type == BrilliantDeviceType.halo) {
      _log.info("Sending remove signal");
      await _settleAcks();
      await sendString("\x05", awaitResponse: false, log: false);
    } else {
      _log.info("Remove signal is Halo-only");
    }
      //await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<String?> sendString(
    String string, {
    bool awaitResponse = true,
    bool log = true,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (log) {
        _log.info(() => "Sending string: $string");
      }

      if (state != BrilliantConnectionState.connected) {
        throw BrilliantBluetoothException("Device is not connected");
      }

      // let any sendMessage() data be processed first
      await waitForAcks();

      final data = utf8.encode(string);
      final maxLength = maxStringLength;
      if (maxLength == null || data.length > maxLength) {
        throw BrilliantBluetoothException("Payload exceeds allowed length of ${maxLength ?? 'unknown'}");
      }

      final tx = txChannel;
      final rx = rxChannel;
      if (tx == null || (awaitResponse && rx == null)) {
        throw BrilliantBluetoothException("Required channels not available");
      }

      // Set up the response listener before writing
      Future<String>? responseFuture;
      if (awaitResponse) {
        responseFuture = rx!.onValueReceived
            .timeout(timeout, onTimeout: (event) {
                throw const BrilliantBluetoothException("Timeout waiting for string response");
            })
            .first
            .then((response) => utf8.decode(response));
      }

      // Now perform the write
      await tx.write(data, withoutResponse: false, allowLongWrite: true);

      // Wait for the response if needed
      if (awaitResponse && responseFuture != null) {
        return await responseFuture;
      }

      return null;
    } catch (error) {
      _log.warning("Couldn't send string. $error");
      rethrow;
    }
  }

  /// Sends [data] (prefixed with the data marker) and waits for the device's
  /// data response. Calls must not overlap: a second concurrent call takes
  /// over the pending response, and the first times out.
  Future<void> sendData(List<int> data, {bool awaitBtResponse = true, Duration timeout = const Duration(seconds: 5)}) async {
    await waitForAcks();
    final Uint8List byteData = Uint8List.fromList(data..insert(0, 0x01));
    await sendDataRawOnCharacteristic(byteData, txChannel!, awaitBtResponse: awaitBtResponse, awaitAppResponse: true, validateHeader: true, timeout: timeout);
  }

  Future<void> sendAudio(Uint8List data, {bool awaitBtResponse = false}) async {
    if (audioTxChannel != null) {
      await sendDataRawOnCharacteristic(data, audioTxChannel!, awaitBtResponse: awaitBtResponse, awaitAppResponse: false, validateHeader: false);
    }
  }

  Future<void> sendDataRaw(Uint8List data, {bool awaitBtResponse = true, Duration timeout = const Duration(seconds: 5)}) async {
    await waitForAcks();
    await sendDataRawOnCharacteristic(data, txChannel!, awaitBtResponse: awaitBtResponse, awaitAppResponse: true, validateHeader: true, timeout: timeout);
  }

  /// Same as sendData but user includes the 0x01 header byte to avoid extra memory allocation
  /// awaitBtResponse indicates whether to wait for a bluetooth-level ack from the write operation (write-without-response/write-with-response)
  /// awaitAppResponse indicates whether to wait for an application-level ack from the data handler on the device
  /// validateHeader indicates whether to check that the first byte is 0x01 (true for data tx, false for audio)
  /// timeout indicates how long to wait for the application-level ack before timing out
  Future<void> sendDataRawOnCharacteristic(Uint8List data, BluetoothCharacteristic char, {bool awaitBtResponse = true, bool awaitAppResponse = true, bool validateHeader = true, Duration timeout = const Duration(seconds: 5)}) async {
    try {
      _log.finer(() => "Sending ${data.length - 1} bytes of plain data");
      _log.finest(data);

      if (state != BrilliantConnectionState.connected) {
        throw ("Device is not connected");
      }

      if (data.length > maxDataLength! + 1) {
        throw ("Payload exceeds allowed length of ${maxDataLength! + 1}");
      }

      if (validateHeader && data[0] != 0x01) {
        throw ("Data packet missing 0x01 header");
      }

      if (awaitAppResponse) {
        // Perform the write and wait for the application-level response concurrently.
        // This prevents a race condition where a very fast device could respond
        // before we start listening for it. A sendMessage() ACK arriving
        // meanwhile is not taken as the response (see _onRxValue).
        final response = Completer<List<int>>();
        _pendingDataResponse = response;
        _updateRxListener();
        try {
          await Future.wait([
            char.write(data, withoutResponse: !awaitBtResponse),
            response.future.timeout(timeout, onTimeout: () {
              throw const BrilliantBluetoothException("Timeout waiting for data response");
            }),
          ]);
        } finally {
          if (identical(_pendingDataResponse, response)) {
            _pendingDataResponse = null;
          }
          _updateRxListener();
        }
      } else {
        // don't wait for an application-level ack, and a bluetooth-level ack only if requested
        await char.write(data, withoutResponse: !awaitBtResponse);
      }
    } catch (error) {
      _log.warning("Couldn't send data. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Writes one sendMessage() packet (with its 0x01 marker) without response,
  /// keeping at most [window] packets unacknowledged
  Future<void> _sendWindowedPacket(Uint8List packet, int window) async {
    if (state != BrilliantConnectionState.connected) {
      throw const BrilliantBluetoothException("Device is not connected");
    }
    await _awaitAcks(window - 1);

    // count it before the write: its ACK can arrive while the write is awaited
    _acksOutstanding++;
    _updateRxListener();
    try {
      _log.finest(packet);
      await txChannel!.write(packet, withoutResponse: true);
    } catch (error) {
      // no ACK will come for a packet that wasn't written
      if (_acksOutstanding > 0) {
        _acksOutstanding--;
        _updateRxListener();
      }
      _log.warning("Couldn't send data. $error");
      if (error is BrilliantBluetoothException) rethrow;
      throw BrilliantBluetoothException(error.toString());
    }
  }

  /// Sends a typed message as a series of messages to Frame as chunks marked by
  /// `[0x01 (dataFlag), messageFlag & 0xFF, {first packet: length(Uint16)}, payload(chunked)]`
  /// until all data in the payload is sent. Payload data cannot exceed 65535 bytes in length.
  /// Can be received by a corresponding Lua function on Frame.
  ///
  /// On Frame, each packet is written with response (unless [awaitBtResponse]
  /// is false) and acknowledged by data.lua before the next is sent.
  ///
  /// On Halo, packets are written without response ([awaitBtResponse] is
  /// ignored), each filling whole link-layer packets, paced by a window over
  /// data.lua's per-packet ACKs: Halo queues each packet until the Lua handler
  /// takes it and silently drops a write that doesn't fit, so no more packets
  /// are left unacknowledged than fit in [receiveBufferSize]. This returns
  /// once its last packet is written, so consecutive messages stream back to
  /// back; the ACKs still outstanding are collected by the next call that
  /// talks to the device (see [waitForAcks]). So a Halo app whose own data
  /// receive callback doesn't send data.lua's ACK (data payload `01 00 00`)
  /// times out on that next call rather than in sendMessage().
  Future<void> sendMessage(int msgCode, Uint8List payload, {bool awaitBtResponse = true}) async {

    if (payload.length > 65535) {
      return Future.error(const BrilliantBluetoothException(
          'Payload length exceeds 65535 bytes'));
    }

    // packetSize: bytes per packet after the 0x01 data marker
    final bool windowed = type == BrilliantDeviceType.halo;
    final int packetSize;
    int window = 1;
    if (windowed) {
      // Halo queues each packet less its marker byte, plus a 2-byte length
      final writeSize = bleWriteSize(math.min(device.mtuNow - 3, 512));
      packetSize = writeSize - 1;
      window = math.max(1, receiveBufferSize ~/ (packetSize + 2));
    } else {
      packetSize = maxDataLength!;
    }

    int lengthMsb = payload.length >> 8;
    int lengthLsb = payload.length & 0xFF;
    int sentBytes = 0;
    bool firstPacket = true;
    int bytesRemaining = payload.length;
    int chunksize = packetSize - 1;

    // the full sized packet buffer to prepare. If we are sending a full sized packet,
    // set packetToSend to point to packetBuffer. If we are sending a smaller (final) packet,
    // instead point packetToSend to a range within packetBuffer
    Uint8List packetBuffer = Uint8List(packetSize + 1);
    Uint8List packetToSend = packetBuffer;
    _log.fine(() => 'sendMessage: payload size: ${payload.length}');

    while (sentBytes < payload.length) {
      if (firstPacket) {
        _log.finer('sendMessage: first packet');
        firstPacket = false;

        if (bytesRemaining < chunksize - 2) {
          // first and final chunk - small payload
          _log.finer('sendMessage: first and final packet');
          packetBuffer[0] = 0x01;
          packetBuffer[1] = msgCode & 0xFF;
          packetBuffer[2] = lengthMsb;
          packetBuffer[3] = lengthLsb;
          packetBuffer.setAll(
              4, payload.getRange(sentBytes, sentBytes + bytesRemaining));
          sentBytes += bytesRemaining;
          packetToSend =
              Uint8List.sublistView(packetBuffer, 0, bytesRemaining + 4);
        } else if (bytesRemaining == chunksize - 2) {
          // first and final chunk - small payload, exact packet size match
          _log.finer('sendMessage: first and final packet, exact match');
          packetBuffer[0] = 0x01;
          packetBuffer[1] = msgCode & 0xFF;
          packetBuffer[2] = lengthMsb;
          packetBuffer[3] = lengthLsb;
          packetBuffer.setAll(
              4, payload.getRange(sentBytes, sentBytes + bytesRemaining));
          sentBytes += bytesRemaining;
          packetToSend = packetBuffer;
        } else {
          // first of many chunks
          _log.finer('sendMessage: first of many packets');
          packetBuffer[0] = 0x01;
          packetBuffer[1] = msgCode & 0xFF;
          packetBuffer[2] = lengthMsb;
          packetBuffer[3] = lengthLsb;
          packetBuffer.setAll(
              4, payload.getRange(sentBytes, sentBytes + chunksize - 2));
          sentBytes += chunksize - 2;
          packetToSend = packetBuffer;
        }
      } else {
        // not the first packet
        if (bytesRemaining < chunksize) {
          _log.finer('sendMessage: not the first packet, final packet');
          // final data chunk, smaller than chunksize
          packetBuffer[0] = 0x01;
          packetBuffer[1] = msgCode & 0xFF;
          packetBuffer.setAll(
              2, payload.getRange(sentBytes, sentBytes + bytesRemaining));
          sentBytes += bytesRemaining;
          packetToSend =
              Uint8List.sublistView(packetBuffer, 0, bytesRemaining + 2);
        } else {
          _log.finer(
              'sendMessage: not the first packet, non-final packet or exact match final packet');
          // non-final data chunk or final chunk with exact packet size match
          packetBuffer[0] = 0x01;
          packetBuffer[1] = msgCode & 0xFF;
          packetBuffer.setAll(
              2, payload.getRange(sentBytes, sentBytes + chunksize));
          sentBytes += chunksize;
          packetToSend = packetBuffer;
        }
      }

      if (windowed) {
        // send the chunk; its app-level ack is collected later
        await _sendWindowedPacket(packetToSend, window);
      } else {
        // send the chunk, awaits the app-level ack
        await sendDataRaw(packetToSend, awaitBtResponse: awaitBtResponse);
      }

      bytesRemaining = payload.length - sentBytes;
      _log.finer(() => 'Bytes remaining: $bytesRemaining');
    }
  }

  Future<void> uploadScript(String fileName, String fileContents) async {
    try {
      _log.info("Uploading script: $fileName");
      // TODO temporarily observe memory usage
      // await sendString(
      //     'print("Frame Mem: " .. tostring(collectgarbage("count")))',
      //     awaitResponse: true);

      String file = fileContents;

      file = file.replaceAll('\\', '\\\\');
      file = file.replaceAll("\r\n", "\\n");
      file = file.replaceAll("\n", "\\n");
      file = file.replaceAll("'", "\\'");
      file = file.replaceAll('"', '\\"');

      var resp = await sendString(
          'f=frame.file.open("$fileName", "w");print(2)',
          awaitResponse: true,
          log: false);

      if (resp != "2") {
        throw ("Error opening file: $resp");
      }

      // Chunk by UTF-8 byte length (not string length) so that characters
      // that expand to multiple bytes can't push a packet over the MTU
      for (final chunk
          in chunkLuaString(utf8.encode(file), maxStringLength! - 22)) {
        resp = await sendString("f:write('$chunk');print(2)", awaitResponse: true, log: false);

        if (resp != "2") {
          throw ("Error writing file: $resp");
        }
      }

      resp = await sendString("f:close();print(2)", awaitResponse: true, log: false);

      if (resp != "2") {
        throw ("Error closing file: $resp");
      }

      // TODO temporarily observe memory usage
      // await sendString(
      //     'print("Frame Mem: " .. tostring(collectgarbage("count")))',
      //     awaitResponse: true);
    } catch (error) {
      _log.warning("Couldn't upload script. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }
}

/// Splits [payload] (the UTF-8 bytes of an escaped Lua string literal) into
/// chunks of at most [maxChunkBytes] bytes, without splitting a multi-byte
/// UTF-8 sequence or a Lua escape sequence across two chunks.
List<String> chunkLuaString(List<int> payload, int maxChunkBytes) {
  if (maxChunkBytes <= 0) {
    throw ArgumentError.value(
        maxChunkBytes, 'maxChunkBytes', 'must be positive');
  }

  final chunks = <String>[];
  int index = 0;

  while (index < payload.length) {
    int end = index + maxChunkBytes;

    if (end >= payload.length) {
      end = payload.length;
    } else {
      // Don't split a multi-byte UTF-8 sequence: back up while the byte at
      // the split point is a continuation byte (0b10xxxxxx)
      while (end > index && (payload[end] & 0xC0) == 0x80) {
        end--;
      }

      // Don't split an escape sequence: an odd number of trailing
      // backslashes means the last one starts an escape whose second
      // character would land in the next chunk
      int trailingBackslashes = 0;
      while (end - 1 - trailingBackslashes >= index &&
          payload[end - 1 - trailingBackslashes] == 0x5C) {
        trailingBackslashes++;
      }
      if (trailingBackslashes.isOdd) {
        end--;
      }

      if (end == index) {
        throw ArgumentError.value(maxChunkBytes, 'maxChunkBytes',
            'too small to hold the next character of the payload');
      }
    }

    chunks.add(utf8.decode(payload.sublist(index, end)));
    index = end;
  }

  return chunks;
}
