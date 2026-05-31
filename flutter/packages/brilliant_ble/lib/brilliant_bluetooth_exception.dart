class BrilliantBluetoothException implements Exception {
  final String msg;
  const BrilliantBluetoothException(this.msg);
  @override
  String toString() => 'BrilliantBluetoothException: $msg';
}
