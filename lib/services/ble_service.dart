import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  final _connectionController = StreamController<BluetoothConnectionState>.broadcast();
  final _dataController = StreamController<String>.broadcast();

  Stream<BluetoothConnectionState> get connectionState => _connectionController.stream;
  Stream<String> get incomingData => _dataController.stream;

  BluetoothDevice? get device => _device;
  bool get isConnected => _characteristic != null;

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect();

    _connectionSub = device.connectionState.listen((state) {
      _connectionController.add(state);
      if (state == BluetoothConnectionState.disconnected) {
        _characteristic = null;
      }
    });

    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.toString() == characteristicUuid) {
            _characteristic = char;
            await _startNotifications();
            return;
          }
        }
      }
    }
    throw Exception('Required BLE service/characteristic not found');
  }

  Future<void> _startNotifications() async {
    if (_characteristic == null) return;
    await _characteristic!.setNotifyValue(true);

    String buffer = '';
    _notifySub = _characteristic!.onValueReceived.listen((bytes) {
      buffer += utf8.decode(bytes);
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isNotEmpty) _dataController.add(line);
      }
    });
  }

  Future<void> write(String message) async {
    if (_characteristic == null) throw Exception('Not connected');
    final bytes = utf8.encode(message);
    await _characteristic!.write(bytes);
  }

  Future<void> disconnect() async {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
  }

  void dispose() {
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _connectionController.close();
    _dataController.close();
  }
}
