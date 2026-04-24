import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/computed_metrics.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';
import '../models/session_record.dart';
import '../models/target_unit.dart';
import '../repositories/drill_template_repository.dart';
import '../repositories/metrics_repository.dart';
import '../repositories/session_repository.dart';
import '../services/metrics_engine.dart';
import '../services/audio_service.dart';
import '../services/ble_service.dart';
import '../services/config_hasher.dart';
import '../services/event_batcher.dart';
import '../services/preferences_repository.dart';
import '../services/range_session_view.dart';
import '../services/transmitter_protocol.dart';
import '../services/tts_port.dart';
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

  // --- Domain state (plan-1) ---
  List<TargetUnit> targets = [];
  bool isScanning = false;
  DrillSession? currentSession;

  /// Targets that dropped out mid-drill (transmitter EVT_ACK timeout ->
  /// ERR/unreachable/<id>/). Cleared on each new drill start.
  final Set<int> unreachableTargets = {};

  // --- Gate-2 additions ---
  final PreferencesRepository? preferences;
  final AudioService? audio;
  final TtsPort? tts;
  final RangeSessionView? rangeSessionView;
  final DrillTemplateRepository? drillTemplates;

  Map<int, String> _targetNames = <int, String>{};
  Set<int> _removedTargetIds = <int>{};
  bool _showRemoved = false;
  bool _onboardingComplete = false;
  bool _readyChimePlayedForCurrentCycle = false;
  // ignore: unused_field
  bool _discoveryDoneSeenForCurrentCycle = false;
  bool _readyAudioEnabled = true;
  double _readyAudioVolume = 1.0;

  Map<int, String> get targetNames => Map.unmodifiable(_targetNames);
  Set<int> get removedTargetIds => Set.unmodifiable(_removedTargetIds);
  bool get showRemoved => _showRemoved;
  bool get onboardingComplete => _onboardingComplete;
  bool get readyAudioEnabled => _readyAudioEnabled;
  double get readyAudioVolume => _readyAudioVolume;

  // --- Phase machine + telemetry (plan-1) ---
  DrillPhase _phase = DrillPhase.idle;
  DrillPhase get phase => _phase;

  StreamSubscription<String>? _dataSub;
  StreamSubscription<ConnectionStatus>? _statusSub;

  Timer? _armingTimeout;
  Timer? _stoppingTimeout;
  Timer? _scanTimeout;

  ConnectionStatus _lastStatus = ConnectionStatus.disconnected;

  final SessionRepository? _sessions;
  final ShooterState? _shooterState;
  final MetricsRepository? _metricsRepo;
  ComputedMetrics? currentMetrics;
  EventBatcher? _batcher;
  String? _activeDbSessionId;
  int _iterationsCompleted = 0;
  Future<void>? _pendingClose;

  /// Public read access for screens (Results share-sheet etc.) that need the
  /// id of the DB session backing [currentSession].
  String? get activeSessionId => _activeDbSessionId;

  /// Public read access to the session repository for screens that need to
  /// query historical events (Results share-sheet reads via
  /// [SessionRepository.getEventsFor]).
  SessionRepository? get sessions => _sessions;

  AppState._internal({
    SessionRepository? sessions,
    ShooterState? shooterState,
    MetricsRepository? metricsRepo,
    this.preferences,
    this.audio,
    this.tts,
    this.rangeSessionView,
    this.drillTemplates,
  })  : _sessions = sessions,
        _shooterState = shooterState,
        _metricsRepo = metricsRepo {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
  }

  factory AppState({
    SessionRepository? sessions,
    ShooterState? shooterState,
    MetricsRepository? metricsRepo,
    PreferencesRepository? preferences,
    AudioService? audio,
    TtsPort? tts,
    RangeSessionView? rangeSessionView,
    DrillTemplateRepository? drillTemplates,
  }) =>
      AppState._internal(
        sessions: sessions,
        shooterState: shooterState,
        metricsRepo: metricsRepo,
        preferences: preferences,
        audio: audio,
        tts: tts,
        rangeSessionView: rangeSessionView,
        drillTemplates: drillTemplates,
      );

  @visibleForTesting
  factory AppState.forTesting({
    required SessionRepository sessions,
    required ShooterState shooterState,
    MetricsRepository? metricsRepo,
    PreferencesRepository? preferences,
    AudioService? audio,
    TtsPort? tts,
    RangeSessionView? rangeSessionView,
    DrillTemplateRepository? drillTemplates,
  }) =>
      AppState._internal(
        sessions: sessions,
        shooterState: shooterState,
        metricsRepo: metricsRepo,
        preferences: preferences,
        audio: audio,
        tts: tts,
        rangeSessionView: rangeSessionView,
        drillTemplates: drillTemplates,
      );

  @visibleForTesting
  void setCurrentMetricsForTesting(ComputedMetrics? m) {
    currentMetrics = m;
    notifyListeners();
  }

  // --- Hydrate gate-2 prefs on startup ---
  Future<void> hydratePreferences() async {
    final prefs = preferences;
    if (prefs == null) return;
    _targetNames = await prefs.getTargetNames();
    _removedTargetIds = await prefs.getRemovedTargetIds();
    _onboardingComplete = await prefs.isOnboardingComplete();
    _readyAudioEnabled = await prefs.isReadyAudioEnabled();
    _readyAudioVolume = await prefs.getReadyAudioVolume();
    notifyListeners();
  }

  // --- Target-name + removed-target API (gate-2) ---
  Future<void> setTargetName(int id, String? name) async {
    await preferences?.setTargetName(id, name);
    if (name == null || name.isEmpty) {
      _targetNames.remove(id);
    } else {
      _targetNames[id] = name;
    }
    notifyListeners();
  }

  Future<void> markTargetRemoved(int id) async {
    _removedTargetIds.add(id);
    await preferences?.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  Future<void> unmarkTargetRemoved(int id) async {
    _removedTargetIds.remove(id);
    await preferences?.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  void toggleShowRemoved() {
    _showRemoved = !_showRemoved;
    notifyListeners();
  }

  // --- Onboarding (gate-2) ---
  Future<void> markOnboardingComplete() async {
    _onboardingComplete = true;
    await preferences?.setOnboardingComplete(true);
    notifyListeners();
  }

  /// Test-only direct setter for [onboardingComplete]. Production code
  /// should go through [hydratePreferences] + [markOnboardingComplete].
  @visibleForTesting
  void setOnboardingCompleteForTesting(bool value) {
    _onboardingComplete = value;
    notifyListeners();
  }

  // --- Ready audio (gate-2) ---
  Future<void> setReadyAudioEnabled(bool v) async {
    _readyAudioEnabled = v;
    await preferences?.setReadyAudioEnabled(v);
    notifyListeners();
  }

  Future<void> setReadyAudioVolume(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    _readyAudioVolume = clamped;
    await preferences?.setReadyAudioVolume(clamped);
    notifyListeners();
  }

  @visibleForTesting
  Future<void> playReadyChimeForTesting() async {
    if (!_readyAudioEnabled) return;
    await audio?.playReady(volume: _readyAudioVolume);
  }

  // --- Phase machine internals (plan-1 — untouched) ---
  void _setPhase(DrillPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }

  void _handleConnectionStatus(ConnectionStatus status) {
    final prev = _lastStatus;
    _lastStatus = status;

    final wasReconnecting = prev == ConnectionStatus.reconnecting;
    final isNowConnected = status == ConnectionStatus.connected;
    final drillLive = _phase == DrillPhase.arming ||
        _phase == DrillPhase.running ||
        _phase == DrillPhase.stopping;

    if (wasReconnecting && isNowConnected && drillLive) {
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
      _scanTimeout?.cancel();
      _scanTimeout = null;
      isScanning = false;
      _discoveryDoneSeenForCurrentCycle = true;
      // Gate-2 #15: play the "ready" chime once per discovery cycle.
      if (!_readyChimePlayedForCurrentCycle) {
        _readyChimePlayedForCurrentCycle = true;
        if (_readyAudioEnabled) {
          unawaited(audio?.playReady(volume: _readyAudioVolume));
        }
      }
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
        unawaited(_closeActiveDbSession(finishedNormally: false));
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
    _readyChimePlayedForCurrentCycle = false;
    _discoveryDoneSeenForCurrentCycle = false;
    for (final t in targets) {
      t.isOnline = false;
    }
    notifyListeners();
    // Safety timeout: transmitter's full scan is ~1.5s (30 addresses × 50ms).
    // Give it 8s for BLE + any queueing delay; if DDONE/ hasn't arrived by
    // then, something broke — clear isScanning so the user can retry.
    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 8), () {
      if (isScanning) {
        isScanning = false;
        notifyListeners();
      }
    });
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

    // Gate-2: stamp range-session activity on drill start.
    unawaited(rangeSessionView?.markActivity());

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
    // SAFETY-CRITICAL (e7f926b): guard BOTH the state transition AND the
    // wire write. Without this guard the write fired unconditionally — any
    // caller that invoked stopDrill() while phase was already
    // stopping/finished/idle would still blast STOP/ at the transmitter. An
    // upstream bug in some widget rebuild loop was driving ~6000 STOP/sec
    // which drowned out the ESP32's drill FSM. Writing only during a real
    // running/arming → stopping transition keeps the wire honest regardless
    // of caller rebound.
    if (_phase != DrillPhase.running && _phase != DrillPhase.arming) {
      return;
    }
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
    // Gate-2: stamp range-session activity on drill end as well.
    unawaited(rangeSessionView?.markActivity());
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
    final metricsRepo = _metricsRepo;
    if (metricsRepo != null) {
      final events = await sessions.getEventsFor(id);
      final computed = MetricsEngine.compute(id, events);
      currentMetrics = computed;
      await metricsRepo.save(computed);
      notifyListeners();
    }
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
  void handleSnapReplyForTesting({required bool running}) {
    if (running) {
      if (_phase == DrillPhase.arming || _phase == DrillPhase.stopping) {
        _setPhase(DrillPhase.running);
      }
      return;
    }
    final session = currentSession;
    if (session != null && session.isRunning) {
      session.addEvent(SessionEvent(type: EventType.drillFinished));
    }
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    _setPhase(DrillPhase.finished);
    final closeFuture = _closeActiveDbSession(finishedNormally: false);
    _pendingClose = closeFuture;
    unawaited(closeFuture);
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
