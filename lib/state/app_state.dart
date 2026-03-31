import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/ble_service.dart';
import '../services/transmitter_protocol.dart';
import '../models/target_unit.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';

class AppState extends ChangeNotifier {
  final BleService bleService = BleService();

  List<TargetUnit> targets = [];
  bool isScanning = false;

  DrillSession? currentSession;

  StreamSubscription<String>? _dataSub;

  AppState() {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
  }

  void _handleIncomingData(String message) {
    final decoded = TransmitterProtocol.decodeTelemetry(message);

    if (decoded is DiscoveredTarget) {
      final existing = targets.where((t) => t.id == decoded.id);
      if (existing.isEmpty) {
        targets.add(TargetUnit(id: decoded.id, isOnline: true));
      } else {
        existing.first.isOnline = true;
      }
      notifyListeners();
      return;
    }

    if (decoded is DiscoveryDone) {
      isScanning = false;
      notifyListeners();
      return;
    }

    if (decoded is SessionEvent && currentSession != null) {
      currentSession!.addEvent(decoded);
      notifyListeners();
    }
  }

  Future<void> discoverTargets() async {
    isScanning = true;
    for (final t in targets) {
      t.isOnline = false;
    }
    notifyListeners();
    await bleService.write(TransmitterProtocol.encodeDiscovery());
  }

  Future<void> identifyTarget(int targetId) async {
    await bleService.write(TransmitterProtocol.encodeIdentify(targetId));
  }

  Future<void> startDrill(DrillConfig config) async {
    currentSession = DrillSession(config: config);
    notifyListeners();
    await bleService.write(TransmitterProtocol.encodeDrillStart(config));
  }

  Future<void> stopDrill() async {
    await bleService.write(TransmitterProtocol.encodeStop());
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}
