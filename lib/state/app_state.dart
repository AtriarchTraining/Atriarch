import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/drill_log_repository.dart';
import '../data/in_memory_repositories.dart';
import '../data/preferences_repository.dart';
import '../data/session_repository.dart';
import '../services/ble_service.dart';
import '../services/transmitter_protocol.dart';
import '../models/target_unit.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';

/// Drill phase machine (Gate 1 §1.3 / Addendum §3 UI state sync).
///
/// Transitions:
///   idle -> arming        (startDrill called, START sent)
///   arming -> running     (first ACT/ arrives)
///   arming -> armingFailed(3s arming timeout with no ACT)
///   running -> stopping   (stopDrill called, STOP sent)
///   stopping -> finished  (STOP_ACK/ OR 5s aggregate timeout)
///   running -> finished   (FIN/ arrives without STOP)
enum DrillPhase {
  idle,
  arming,
  running,
  stopping,
  finished,
  armingFailed,
}

class AppState extends ChangeNotifier {
  final BleService bleService = BleService();

  List<TargetUnit> targets = [];
  bool isScanning = false;

  DrillSession? currentSession;

  DrillPhase _phase = DrillPhase.idle;
  DrillPhase get phase => _phase;

  /// Targets that dropped out mid-drill (transmitter EVT_ACK timeout ->
  /// ERR/unreachable/<id>/). Cleared on each new drill start.
  final Set<int> unreachableTargets = {};

  StreamSubscription<String>? _dataSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  Timer? _armingTimeout;
  Timer? _stoppingTimeout;

  ConnectionStatus _lastStatus = ConnectionStatus.disconnected;

  /// Gate 2 persistence layer (#11). Non-null so Wave 2 drill-lifecycle
  /// wiring can call them without bang-operator NPEs; tests use
  /// [AppState.forTest] to get in-memory stand-ins.
  final PreferencesRepository preferences;
  final SessionRepository sessions;
  final DrillLogRepository drillLogs;

  AppState({
    required this.preferences,
    required this.sessions,
    required this.drillLogs,
  }) {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
  }

  /// Test seam. Supply real or mock repositories; any omitted argument gets
  /// an in-memory stand-in from [in_memory_repositories.dart]. Lets widget
  /// and unit tests skip `Hive.init(tempDir)` boilerplate.
  factory AppState.forTest({
    PreferencesRepository? preferences,
    SessionRepository? sessions,
    DrillLogRepository? drillLogs,
  }) {
    return AppState(
      preferences: preferences ?? InMemoryPreferencesRepository(),
      sessions: sessions ?? InMemorySessionRepository(),
      drillLogs: drillLogs ?? InMemoryDrillLogRepository(),
    );
  }

  void _setPhase(DrillPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  void _handleConnectionStatus(ConnectionStatus status) {
    final prev = _lastStatus;
    _lastStatus = status;

    // Reconcile on reconnect: if we were previously reconnecting and a drill
    // session is live, ask the transmitter for a snapshot. The SnapReply
    // handler below will flip phase based on `running`.
    final wasReconnecting = prev == ConnectionStatus.reconnecting;
    final isNowConnected = status == ConnectionStatus.connected;
    final drillLive = _phase == DrillPhase.arming ||
        _phase == DrillPhase.running ||
        _phase == DrillPhase.stopping;

    if (wasReconnecting && isNowConnected && drillLive) {
      // Fire-and-forget; errors are surfaced via other channels.
      // Note: BleService also sends SNAP/ itself on reconnect; this is a
      // belt-and-suspenders safeguard in case BleService's auto-SNAP fails.
      unawaited(_sendSnap());
    }
  }

  Future<void> _sendSnap() async {
    try {
      await bleService.write(TransmitterProtocol.encodeSnap());
    } catch (_) {
      // Best-effort; no phase change on failure.
    }
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

    if (decoded is StopAck) {
      _stoppingTimeout?.cancel();
      _stoppingTimeout = null;
      // Mark the session finished locally (mirrors FIN/ semantics).
      final session = currentSession;
      if (session != null && session.isRunning) {
        session.addEvent(SessionEvent(type: EventType.drillFinished));
      }
      _setPhase(DrillPhase.finished);
      return;
    }

    if (decoded is UnreachableTarget) {
      unreachableTargets.add(decoded.id);
      notifyListeners();
      return;
    }

    if (decoded is SnapReply) {
      // Reconcile drill-phase after reconnect.
      if (decoded.running) {
        if (_phase == DrillPhase.arming || _phase == DrillPhase.stopping) {
          _setPhase(DrillPhase.running);
        }
      } else {
        // Transmitter says no drill is running. Close out locally.
        final session = currentSession;
        if (session != null && session.isRunning) {
          session.addEvent(SessionEvent(type: EventType.drillFinished));
        }
        _armingTimeout?.cancel();
        _stoppingTimeout?.cancel();
        _setPhase(DrillPhase.finished);
      }
      return;
    }

    if (decoded is SessionEvent) {
      // First ACT/ during arming unblocks the START button -> running.
      if (decoded.type == EventType.targetActivated &&
          _phase == DrillPhase.arming) {
        _armingTimeout?.cancel();
        _armingTimeout = null;
        _setPhase(DrillPhase.running);
      }
      if (currentSession != null) {
        currentSession!.addEvent(decoded);
        if (decoded.type == EventType.drillFinished) {
          _armingTimeout?.cancel();
          _stoppingTimeout?.cancel();
          _setPhase(DrillPhase.finished);
        }
        notifyListeners();
      }
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

  /// Reset phase to idle. Call when navigating into a setup screen so a
  /// Retry after armingFailed starts from a clean state.
  void resetDrillPhase() {
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _armingTimeout = null;
    _stoppingTimeout = null;
    _setPhase(DrillPhase.idle);
  }

  Future<void> startDrill(DrillConfig config) async {
    currentSession = DrillSession(config: config);
    unreachableTargets.clear();
    _setPhase(DrillPhase.arming);

    _armingTimeout?.cancel();
    _armingTimeout = Timer(const Duration(seconds: 3), () {
      if (_phase == DrillPhase.arming) {
        _setPhase(DrillPhase.armingFailed);
      }
    });

    await bleService.write(TransmitterProtocol.encodeDrillStart(config));
  }

  Future<void> stopDrill() async {
    if (_phase == DrillPhase.running || _phase == DrillPhase.arming) {
      _setPhase(DrillPhase.stopping);
      _stoppingTimeout?.cancel();
      _stoppingTimeout = Timer(const Duration(seconds: 5), () {
        if (_phase == DrillPhase.stopping) {
          // Target-side safe-stop (5s no-RF auto-lower, BLE_SILENCE_TIMEOUT_MS) is the real safety
          // net; the app just moves the user to Results.
          final session = currentSession;
          if (session != null && session.isRunning) {
            session.addEvent(SessionEvent(type: EventType.drillFinished));
          }
          _setPhase(DrillPhase.finished);
        }
      });
    }
    await bleService.write(TransmitterProtocol.encodeStop());
  }

  // Fallback used by the 2s-nav-fallback in drill_running_screen for the
  // pre-STOP_ACK world. Safe to call in either world — sets phase=finished
  // and closes out the session. Idempotent.
  void forceDrillFinished() {
    final session = currentSession;
    if (session != null && session.isRunning) {
      session.addEvent(SessionEvent(type: EventType.drillFinished));
    }
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _setPhase(DrillPhase.finished);
  }

  @override
  void dispose() {
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _dataSub?.cancel();
    _statusSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}
