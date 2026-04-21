import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/ble_service.dart';
import '../services/transmitter_protocol.dart';
import '../models/target_unit.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';
import '../models/session_record.dart';
import '../repositories/session_repository.dart';
import '../services/config_hasher.dart';
import '../services/event_batcher.dart';
import 'shooter_state.dart';

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

  final SessionRepository? _sessions;
  final ShooterState? _shooterState;
  EventBatcher? _batcher;
  String? _activeDbSessionId;
  int _iterationsCompleted = 0;
  Future<void>? _pendingClose;

  AppState._internal({
    SessionRepository? sessions,
    ShooterState? shooterState,
  })  : _sessions = sessions,
        _shooterState = shooterState {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
  }

  factory AppState({
    SessionRepository? sessions,
    ShooterState? shooterState,
  }) =>
      AppState._internal(sessions: sessions, shooterState: shooterState);

  @visibleForTesting
  factory AppState.forTesting({
    required SessionRepository sessions,
    required ShooterState shooterState,
  }) =>
      AppState._internal(sessions: sessions, shooterState: shooterState);

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
      final session = currentSession;
      if (session != null && session.isRunning) {
        session.addEvent(SessionEvent(type: EventType.drillFinished));
      }
      _setPhase(DrillPhase.finished);
      unawaited(_closeActiveDbSession(finishedNormally: false));
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
      if (decoded.type == EventType.targetActivated &&
          _phase == DrillPhase.arming) {
        _armingTimeout?.cancel();
        _armingTimeout = null;
        _setPhase(DrillPhase.running);
      }
      if (currentSession != null) {
        currentSession!.addEvent(decoded);
        _batcher?.add(decoded);
        if (decoded.type == EventType.targetActivated) {
          _iterationsCompleted++;
        }
        if (decoded.type == EventType.drillFinished) {
          _armingTimeout?.cancel();
          _stoppingTimeout?.cancel();
          _setPhase(DrillPhase.finished);
          unawaited(_closeActiveDbSession(finishedNormally: true));
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
    _iterationsCompleted = 0;
    _setPhase(DrillPhase.arming);

    final sessions = _sessions;
    final shooterState = _shooterState;
    if (sessions != null && shooterState != null && shooterState.current != null) {
      final id = const Uuid().v4();
      _activeDbSessionId = id;
      final programCode =
          config.programType == ProgramType.programA ? 'A' : 'B';
      await sessions.insert(SessionRecord(
        id: id,
        shooterId: shooterState.current!.id,
        programType: programCode,
        configJson: ConfigHasher.canonicalJson(config),
        configHash: ConfigHasher.hash(config),
        startedAt: DateTime.now(),
        finishedNormally: false,
        iterationsCompleted: 0,
      ));
      _batcher = EventBatcher(
        onFlush: (events) => sessions.appendEvents(id, events),
      )..start();
    }

    _armingTimeout?.cancel();
    _armingTimeout = Timer(const Duration(seconds: 3), () {
      if (_phase == DrillPhase.arming) {
        _setPhase(DrillPhase.armingFailed);
      }
    });

    try {
      await bleService.write(TransmitterProtocol.encodeDrillStart(config));
    } catch (_) {
      // BLE write failure — the arming timeout above will transition to
      // armingFailed. Swallow here so the persistence path (already committed
      // above) is not rolled back and callers don't need to try/catch.
    }
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
          unawaited(_closeActiveDbSession(finishedNormally: false));
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
    unawaited(_closeActiveDbSession(finishedNormally: false));
  }

  Future<void> _closeActiveDbSession({required bool finishedNormally}) async {
    final id = _activeDbSessionId;
    final sessions = _sessions;
    final batcher = _batcher;
    if (id == null || sessions == null) return;
    if (batcher != null) {
      await batcher.stop();
    }
    await sessions.closeSession(
      id: id,
      endedAt: DateTime.now(),
      finishedNormally: finishedNormally,
      iterationsCompleted: _iterationsCompleted,
    );
    _activeDbSessionId = null;
    _batcher = null;
  }

  @visibleForTesting
  void handleSessionEventForTesting(SessionEvent event) {
    if (currentSession != null) {
      currentSession!.addEvent(event);
      _batcher?.add(event);
      if (event.type == EventType.targetActivated) {
        _iterationsCompleted++;
      }
      if (event.type == EventType.drillFinished) {
        _pendingClose = _closeActiveDbSession(finishedNormally: true);
      }
    }
  }

  @visibleForTesting
  Future<void> forceFlushForTesting() async {
    final id = _activeDbSessionId;
    final sessions = _sessions;
    final batcher = _batcher;
    if (batcher != null) {
      await batcher.stop();
      if (id != null && sessions != null && identical(_batcher, batcher)) {
        _batcher = EventBatcher(
          onFlush: (events) => sessions.appendEvents(id, events),
        )..start();
      }
    }
    // Drain any pending close triggered by a FIN event in
    // handleSessionEventForTesting above. Safe to call even if no close
    // is pending.
    await _pendingClose;
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
