import 'dart:typed_data';

/// The base class for all Tx (transmit phone to Frame) messages that can be sent using sendMessage()
/// which performs splitting across multiple MTU-sized packets
/// an assembled automatically frameside by the data handler.
abstract class TxMsg {

  /// pack() should produce a message data payload that can be parsed by a corresponding
  /// parser in the frameside application (Lua)
  /// The 0x01 (raw user data marker) byte and the msgCode byte are
  /// prepended to each bluetooth write() call by the Frame BLE sendDataRaw() method,
  /// followed by the maximum amount of payload data that will fit until the whole message is sent.
  Uint8List pack();
}
