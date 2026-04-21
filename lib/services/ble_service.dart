import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'transmitter_protocol.dart';

/// High-level connection lifecycle status used by the UI.
///
/// Layered on top of [BluetoothConnectionState] — includes states that
/// flutter_blue_plus does not model directly (scanning, reconnecting,
/// backoff-exhausted failure).
enum ConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
  failed,
}

class BleService {
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String characteristicUuid =
      '0000ffe1-0000-1000-8000-00805f9b34fb';

  static const String _prefsKeyPeripheralUuid = 'atriarch.ble.peripheralUuid';

  static const Duration _scanTimeout = Duration(seconds: 10);
  static const Duration _discoveryTimeout = Duration(seconds: 10);

  // Exponential backoff ladder (cap at 10s, stop after 6 attempts = ~48s).
  static const List<Duration> _backoffLadder = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 10),
    Duration(seconds: 10),
  ];

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;

  final _connectionController =
      StreamController<BluetoothConnectionState>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<String>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  Stream<BluetoothConnectionState> get connectionState =>
      _connectionController.stream;
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;
  Stream<String> get incomingData => _dataController.stream;

  BluetoothDevice? get device => _device;
  bool get isConnected => _characteristic != null;
  ConnectionStatus get status => _status;

  void _emitStatus(ConnectionStatus next) {
    _status = next;
    _statusController.add(next);
  }

  Future<void> connect(BluetoothDevice device) async {
    _manualDisconnect = false;
    _reconnectAttempt = 0;
    _device = device;
    _emitStatus(ConnectionStatus.connecting);

    try {
      await device.connect(timeout: _scanTimeout);
    } on TimeoutException {
      _emitStatus(ConnectionStatus.failed);
      rethrow;
    } catch (_) {
      _emitStatus(ConnectionStatus.failed);
      rethrow;
    }

    await _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen(_onConnectionStateChanged);

    try {
      await _discoverAndSubscribe().timeout(_discoveryTimeout);
    } on TimeoutException {
      _emitStatus(ConnectionStatus.failed);
      rethrow;
    }

    // Persist remoteId on successful initial connect so we can silent-reconnect
    // on next app launch.
    await _persistPeripheralUuid(device.remoteId.toString());

    _emitStatus(ConnectionStatus.connected);
  }

  Future<void> _discoverAndSubscribe() async {
    final device = _device;
    if (device == null) {
      throw StateError('No device to discover services on');
    }
    final services = await device.discoverServices();
    // flutter_blue_plus returns 16-bit SIG UUIDs in short form (e.g. "ffe0")
    // via .toString(). The HM-10 service/char UUIDs we look for fall in that
    // SIG range, so compare via .str128 to force the 128-bit canonical form
    // on both sides.
    for (final service in services) {
      if (service.uuid.str128.toLowerCase() == serviceUuid) {
        for (final char in service.characteristics) {
          if (char.uuid.str128.toLowerCase() == characteristicUuid) {
            _characteristic = char;
            await _startNotifications();
            return;
          }
        }
      }
    }
    throw Exception('Required BLE service/characteristic not found');
  }

  void _onConnectionStateChanged(BluetoothConnectionState state) {
    _connectionController.add(state);
    if (state == BluetoothConnectionState.disconnected) {
      _characteristic = null;
      if (!_manualDisconnect) {
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    final device = _device;
    if (device == null) return;
    if (_reconnectAttempt >= _backoffLadder.length) {
      _emitStatus(ConnectionStatus.failed);
      return;
    }

    final delay = _backoffLadder[_reconnectAttempt];
    _reconnectAttempt++;
    _emitStatus(ConnectionStatus.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_manualDisconnect) return;
      try {
        await device.connect(timeout: _scanTimeout);
        await _discoverAndSubscribe().timeout(_discoveryTimeout);
        // Re-emit connected after successful reconnect.
        _emitStatus(ConnectionStatus.connected);
        _reconnectAttempt = 0;
        // Ask transmitter to snapshot its state so AppState can reconcile.
        try {
          await write(TransmitterProtocol.encodeSnap());
        } catch (_) {
          // Non-fatal — AppState can still reconcile via next telemetry.
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<void> _startNotifications() async {
    if (_characteristic == null) return;
    await _notifySub?.cancel();
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

  /// Attempts to silently reconnect to a previously-paired transmitter.
  ///
  /// Read persisted peripheral UUID from shared_preferences. If present,
  /// first look for it via `FlutterBluePlus.systemDevices` (fast path —
  /// device is already system-paired). If not there, return null so the
  /// caller can fall back to a normal scan.
  Future<BluetoothDevice?> tryReconnectPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = prefs.getString(_prefsKeyPeripheralUuid);
    if (uuid == null || uuid.isEmpty) return null;

    try {
      final systemDevices = await FlutterBluePlus.systemDevices([]);
      for (final d in systemDevices) {
        if (d.remoteId.toString() == uuid) {
          await connect(d);
          return d;
        }
      }
    } catch (_) {
      // Fall through — caller will do a normal scan.
    }
    return null;
  }

  Future<void> _persistPeripheralUuid(String uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyPeripheralUuid, uuid);
    } catch (_) {
      // Persistence is best-effort; a failure here shouldn't block the
      // connection flow.
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    _notifySub = null;
    _connectionSub = null;
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
    _emitStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _notifySub?.cancel();
    _connectionSub?.cancel();
    _connectionController.close();
    _statusController.close();
    _dataController.close();
  }
}
