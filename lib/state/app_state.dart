import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../data/drill_log_repository.dart';
import '../data/in_memory_repositories.dart';
import '../data/preferences_repository.dart';
import '../data/session_repository.dart';
import '../services/audio_service.dart';
import '../services/ble_service.dart';
import '../services/transmitter_protocol.dart';
import '../models/target_unit.dart';
import '../models/drill_config.dart';
import '../models/drill_session.dart';
import '../models/session_event.dart';
import '../data/session_summary.dart';
import '../util/drill_log_codec.dart';
import '../util/target_name_resolver.dart';

/// Minimal TTS port so tests can drop in a recording fake without pulling
/// in the real `flutter_tts` plugin (which needs platform channels).
abstract class TtsPort {
  Future<void> speak(String text);
  Future<void> stop();
}

class _FlutterTtsPort implements TtsPort {
  _FlutterTtsPort(this._tts);
  final FlutterTts _tts;

  @override
  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      // Plugin failures are non-fatal — walk continues silently.
      debugPrint('TTS.speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // best-effort
    }
  }
}

/// Test fake: records every spoken string without touching the plugin.
class RecordingTtsPort implements TtsPort {
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}

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

  /// Gate 2 #15 ready-audio cue. Non-null; tests inject a [NoopAudioService].
  final AudioService audio;

  /// Gate 2 #20 TTS for Walk-the-Range target naming. Non-null; tests
  /// inject a [RecordingTtsPort] to assert without a platform channel.
  final TtsPort tts;

  // --------------------------------------------- Ready-audio settings (§4.C)
  static const String _kReadyAudioEnabled = 'ready_audio_enabled';
  static const String _kReadyAudioVolume = 'ready_audio_volume';
  static const bool _defaultReadyAudioEnabled = true;
  static const double _defaultReadyAudioVolume = 0.7;

  // ---------------------------------------------- Onboarding gate (Gate 2 #19)
  /// Key for the first-run onboarding-complete flag in `app_settings`. The
  /// wizard at `lib/screens/onboarding/` flips this to `true` after a
  /// successful practice drill + explicit Finish tap.
  static const String _kOnboardingComplete = 'onboarding_complete';

  bool _onboardingComplete = false;
  bool _onboardingHydrated = false;

  /// True once the user has finished the first-run wizard. Source of truth
  /// is [preferences]; cached here for synchronous UI reads in `main.dart`
  /// and the Settings screen.
  bool get onboardingComplete => _onboardingComplete;

  bool _readyAudioEnabled = _defaultReadyAudioEnabled;
  double _readyAudioVolume = _defaultReadyAudioVolume;

  /// True once the ready-audio settings have been loaded from persistence
  /// OR overwritten by a user-driven setter. Used to prevent a late-arriving
  /// hydrate microtask from clobbering a user change that ran first.
  bool _readyAudioHydrated = false;

  /// True while the ready chime is enabled in Settings. Source of truth is
  /// [preferences]; this is a cached snapshot for synchronous UI reads.
  bool get readyAudioEnabled => _readyAudioEnabled;

  /// Playback volume for the ready chime (0.0–1.0). Source of truth is
  /// [preferences]; this is a cached snapshot for synchronous UI reads.
  double get readyAudioVolume => _readyAudioVolume;

  /// Guards duplicate chimes within a single discovery cycle. Resets on
  /// [discoverTargets] (a.k.a. "startScan"), fires once when the fleet
  /// reaches full-online.
  bool _readyChimePlayedForCurrentCycle = false;

  /// True once [DiscoveryDone] has arrived for the current cycle. Used to
  /// gate the late-arriving-target path — we only chime mid-cycle after
  /// `DDONE/` has fired.
  bool _discoveryDoneSeenForCurrentCycle = false;

  /// Live snapshot of saved target names (id -> user-assigned display name).
  /// Loaded from [preferences] on construction; kept in sync by
  /// [setTargetName]. Consumers should render via [targetNameResolver].
  final Map<int, String> _targetNames = <int, String>{};

  /// Live snapshot of soft-deleted target ids. Chips for these ids are
  /// hidden from the setup screens unless [showRemoved] is toggled on.
  final Set<int> _removedTargetIds = <int>{};

  bool _showRemoved = false;

  /// True once the target-pref snapshots have been loaded from persistence
  /// OR overwritten by a user-driven setter. Prevents a late hydrate tick
  /// from clobbering a user change that landed first.
  bool _targetPrefsHydrated = false;

  /// AppBar overflow "Show removed" toggle state (addendum §4.B).
  bool get showRemoved => _showRemoved;

  /// Live resolver built from the in-memory names map. Cheap enough to
  /// rebuild per caller; callers don't need to cache.
  TargetNameResolver get targetNameResolver =>
      TargetNameResolver(Map<int, String>.unmodifiable(_targetNames));

  /// Read-only view of the removed-id set. Useful for "Restore" UI.
  Set<int> get removedTargetIds => Set<int>.unmodifiable(_removedTargetIds);

  AppState({
    required this.preferences,
    required this.sessions,
    required this.drillLogs,
    required this.audio,
    TtsPort? tts,
  }) : tts = tts ?? _FlutterTtsPort(FlutterTts()) {
    _dataSub = bleService.incomingData.listen(_handleIncomingData);
    _statusSub = bleService.connectionStatus.listen(_handleConnectionStatus);
    // Eagerly hydrate target-name + removed-id snapshots so UI gets the
    // real labels on first frame. Safe to fire-and-forget: the preferences
    // repo surfaces empty defaults before init completes.
    unawaited(_hydrateTargetPrefs());
    unawaited(_hydrateReadyAudioPrefs());
    unawaited(_hydrateOnboarding());
  }

  Future<void> _hydrateOnboarding() async {
    try {
      final v = await preferences.getSetting<bool>(_kOnboardingComplete);
      // Guard the setter-before-hydrate race. If a user action already
      // flipped the flag, don't clobber it with a stale read.
      if (_onboardingHydrated) return;
      _onboardingComplete = v ?? false;
      _onboardingHydrated = true;
      notifyListeners();
    } catch (_) {
      // Best-effort; default stays false and the wizard runs.
    }
  }

  /// Persist the onboarding-complete flag. Called from:
  /// - the wizard's final "Finish Onboarding" button (value = true),
  /// - Settings > "Re-run onboarding" (value = false).
  Future<void> setOnboardingComplete(bool complete) async {
    _onboardingHydrated = true;
    if (_onboardingComplete == complete) {
      // Still persist to guard against hydrate races where the cached
      // value briefly matched but persistence is stale.
      await preferences.setSetting<bool>(_kOnboardingComplete, complete);
      return;
    }
    _onboardingComplete = complete;
    notifyListeners();
    await preferences.setSetting<bool>(_kOnboardingComplete, complete);
  }

  Future<void> _hydrateTargetPrefs() async {
    try {
      final names = await preferences.getTargetNames();
      final removed = await preferences.getRemovedTargetIds();
      // Guard the setter-before-hydrate race: a user action that ran first
      // may have already updated the in-memory snapshot; don't clobber it.
      if (_targetPrefsHydrated) return;
      _targetNames
        ..clear()
        ..addAll(names);
      _removedTargetIds
        ..clear()
        ..addAll(removed);
      _targetPrefsHydrated = true;
      notifyListeners();
    } catch (_) {
      // Best-effort; absence of saved names just means fallback `T{id}` labels.
    }
  }

  Future<void> _hydrateReadyAudioPrefs() async {
    try {
      final enabled =
          await preferences.getSetting<bool>(_kReadyAudioEnabled);
      final volume =
          await preferences.getSetting<double>(_kReadyAudioVolume);
      // Guard against the setter-before-hydrate race: a test (or the user on
      // a fast tap) may have already moved the in-memory value past the
      // persisted one. Only apply hydration results when the cached value
      // has not been touched yet.
      if (_readyAudioHydrated) return;
      _readyAudioEnabled = enabled ?? _defaultReadyAudioEnabled;
      _readyAudioVolume = volume ?? _defaultReadyAudioVolume;
      _readyAudioHydrated = true;
      notifyListeners();
    } catch (_) {
      // Best-effort; defaults above take over.
    }
  }

  /// Test seam. Supply real or mock repositories; any omitted argument gets
  /// an in-memory stand-in from [in_memory_repositories.dart]. Lets widget
  /// and unit tests skip `Hive.init(tempDir)` boilerplate.
  factory AppState.forTest({
    PreferencesRepository? preferences,
    SessionRepository? sessions,
    DrillLogRepository? drillLogs,
    AudioService? audio,
    TtsPort? tts,
  }) {
    return AppState(
      preferences: preferences ?? InMemoryPreferencesRepository(),
      sessions: sessions ?? InMemorySessionRepository(),
      drillLogs: drillLogs ?? InMemoryDrillLogRepository(),
      audio: audio ?? NoopAudioService(),
      tts: tts ?? RecordingTtsPort(),
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
      // Late-arriving target path (§4.C): if DDONE already fired and this
      // target just completed the fleet, fire the chime now. Guarded by
      // _readyChimePlayedForCurrentCycle so it still only plays once.
      if (_discoveryDoneSeenForCurrentCycle) {
        _maybePlayReadyChime();
      }
      return;
    }

    if (decoded is DiscoveryDone) {
      isScanning = false;
      _discoveryDoneSeenForCurrentCycle = true;
      _maybePlayReadyChime();
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
      _onDrillFinished(incomplete: false);
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
        _onDrillFinished(incomplete: true);
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
          _onDrillFinished(incomplete: false);
          _setPhase(DrillPhase.finished);
        }
        notifyListeners();
      }
    }
  }

  Future<void> discoverTargets() async {
    isScanning = true;
    // New discovery cycle: reset the ready-chime guards so a completed
    // fleet can trigger the chime exactly once this cycle (§4.C).
    _readyChimePlayedForCurrentCycle = false;
    _discoveryDoneSeenForCurrentCycle = false;
    for (final t in targets) {
      t.isOnline = false;
    }
    notifyListeners();
    await bleService.write(TransmitterProtocol.encodeDiscovery());
  }

  /// Gate 2 §4.C. Plays the ready chime iff:
  ///   - the user setting is enabled,
  ///   - we haven't already chimed this cycle,
  ///   - all non-removed targets are online,
  ///   - there is at least one non-removed target (empty fleet doesn't
  ///     trigger a "ready" state).
  void _maybePlayReadyChime() {
    if (_readyChimePlayedForCurrentCycle) return;
    if (!_readyAudioEnabled) return;
    final visible = targets
        .where((t) => !_removedTargetIds.contains(t.id))
        .toList(growable: false);
    if (visible.isEmpty) return;
    final allOnline = visible.every((t) => t.isOnline);
    if (!allOnline) return;
    _readyChimePlayedForCurrentCycle = true;
    // Fire-and-forget; AudioService swallows its own failures.
    unawaited(audio.playReady(volume: _readyAudioVolume));
  }

  // ---------------------------------------------- Ready-audio setters (§4.C)

  /// Persist + apply the ready-chime on/off toggle. Source of truth is
  /// [preferences]; the cached [_readyAudioEnabled] snapshot keeps the UI
  /// in sync.
  Future<void> setReadyAudioEnabled(bool enabled) async {
    // Mark hydrated so a still-pending _hydrateReadyAudioPrefs microtask
    // doesn't overwrite this user change.
    _readyAudioHydrated = true;
    if (_readyAudioEnabled == enabled) return;
    _readyAudioEnabled = enabled;
    notifyListeners();
    await preferences.setSetting<bool>(_kReadyAudioEnabled, enabled);
  }

  /// Persist + apply the ready-chime volume (clamped to 0.0–1.0).
  Future<void> setReadyAudioVolume(double volume) async {
    _readyAudioHydrated = true;
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    if ((_readyAudioVolume - clamped).abs() < 1e-6) return;
    _readyAudioVolume = clamped;
    notifyListeners();
    await preferences.setSetting<double>(_kReadyAudioVolume, clamped);
  }

  /// Test seam. Drives a single parsed [TransmitterProtocol] message through
  /// the internal handler without needing a real BLE stream. Only used by
  /// unit tests — production code goes through [BleService.incomingData].
  @visibleForTesting
  void debugInjectRawMessage(String rawMessage) {
    _handleIncomingData(rawMessage);
  }

  Future<void> identifyTarget(int targetId) async {
    await _sendIdentify(targetId);
  }

  // -------------------------------------- Press-and-hold identify (§5.A)

  /// Settings key for the one-shot "hold to flash" coach tooltip. Set to
  /// true the first time the user triggers a press-and-hold; from then on
  /// the tip is suppressed.
  static const String _kIdentifyHoldTipSeen = 'identify_hold_tip_seen';

  /// Press-and-hold repeat cadence (addendum §5.A).
  static const Duration _identifyHoldCadence = Duration(milliseconds: 700);

  /// Walk-the-Range cadence (addendum §5.B).
  static const Duration _walkCadence = Duration(seconds: 3);

  /// Per-target repeat timers. Coalesced — one timer per id.
  final Map<int, Timer> _identifyHoldTimers = <int, Timer>{};

  /// Ids currently being tracked for TX logging / coalescing. Not exposed
  /// outside the class.
  final Set<int> _identifyHoldActiveIds = <int>{};

  /// Test seam — counts every IDENT/ the app emitted (press-and-hold or
  /// Walk-the-Range). Persists across hold starts so tests can assert on
  /// the total volley fired.
  final List<int> _debugSentIdentifyIds = <int>[];

  /// Test-only view of the IDENT/ command log.
  @visibleForTesting
  List<int> get debugSentIdentifyIds =>
      List<int>.unmodifiable(_debugSentIdentifyIds);

  /// True once the first-use tip has been shown (cached after hydration).
  bool _identifyHoldTipSeenCache = false;
  bool _identifyHoldTipCacheHydrated = false;

  Future<void> _hydrateIdentifyHoldTipSeen() async {
    try {
      final seen =
          await preferences.getSetting<bool>(_kIdentifyHoldTipSeen) ?? false;
      if (_identifyHoldTipCacheHydrated) return;
      _identifyHoldTipSeenCache = seen;
      _identifyHoldTipCacheHydrated = true;
    } catch (_) {
      // best-effort
    }
  }

  /// Returns true if the UI should display the "hold to flash" SnackBar
  /// on this press-and-hold (first time per install). Also atomically
  /// flips the flag so subsequent calls return false.
  Future<bool> consumeIdentifyHoldTip() async {
    await _hydrateIdentifyHoldTipSeen();
    if (_identifyHoldTipSeenCache) return false;
    _identifyHoldTipSeenCache = true;
    _identifyHoldTipCacheHydrated = true;
    try {
      await preferences.setSetting<bool>(_kIdentifyHoldTipSeen, true);
    } catch (_) {
      // best-effort — tip may re-show on next launch if persist failed.
    }
    return true;
  }

  /// Begin press-and-hold identify for [targetId]. Sends an immediate
  /// IDENT/, then repeats at 700ms cadence until [identifyHoldEnd] is
  /// called (addendum §5.A). No-op during non-idle drill phases (safety:
  /// don't flash LEDs during live fire).
  void identifyHoldStart(int targetId) {
    if (_phase != DrillPhase.idle) return;
    // Coalesce repeat calls on the same id.
    _identifyHoldTimers[targetId]?.cancel();
    _identifyHoldActiveIds.add(targetId);
    // Immediate first fire so the user gets instant visual feedback.
    _fireIdentify(targetId);
    _identifyHoldTimers[targetId] = Timer.periodic(
      _identifyHoldCadence,
      (_) => _fireIdentify(targetId),
    );
  }

  /// End press-and-hold identify for [targetId]. Cancels the repeat timer.
  /// No explicit "stop identify" command is sent — the target's own LED
  /// timer auto-terminates each 3-flash pulse.
  void identifyHoldEnd(int targetId) {
    _identifyHoldTimers.remove(targetId)?.cancel();
    _identifyHoldActiveIds.remove(targetId);
  }

  void _fireIdentify(int targetId) {
    _debugSentIdentifyIds.add(targetId);
    unawaited(_sendIdentify(targetId));
  }

  Future<void> _sendIdentify(int targetId) async {
    try {
      await bleService.write(TransmitterProtocol.encodeIdentify(targetId));
    } catch (e) {
      // BLE may be disconnected mid-hold; the next tick just retries.
      debugPrint('IDENT/$targetId failed: $e');
    }
  }

  // ------------------------------------------------ Walk-the-Range (§5.B)

  bool _walkActive = false;

  /// True while a Walk-the-Range sequence is in flight. UI flips the button
  /// to "Cancel" when this is true.
  bool get walkTheRangeActive => _walkActive;

  /// Iterate visible online non-removed targets in ascending id order,
  /// firing a single IDENT/ for each with a 3s gap between. If TTS is
  /// available and ready-audio is enabled, announces the resolved name.
  /// No-op when no walk-able targets exist, or phase is non-idle.
  Future<void> walkTheRange() async {
    if (_phase != DrillPhase.idle) return;
    if (_walkActive) return;

    final walkList = visibleTargets
        .where((t) => t.isOnline)
        .toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (walkList.isEmpty) return;

    _walkActive = true;
    notifyListeners();

    final resolver = targetNameResolver;
    try {
      for (var i = 0; i < walkList.length; i++) {
        if (!_walkActive) break;
        final t = walkList[i];
        _fireIdentify(t.id);
        if (_readyAudioEnabled) {
          unawaited(tts.speak(resolver.display(t.id)));
        }
        // Wait 3s before the next iteration, but bail out at the boundary
        // if the user cancelled. No partial-wait timer leaks — a cancelled
        // walk just drops through the for loop.
        if (i < walkList.length - 1) {
          await Future<void>.delayed(_walkCadence);
        }
      }
    } finally {
      _walkActive = false;
      notifyListeners();
    }
  }

  /// Cancel a Walk-the-Range sequence at the next 3s boundary. Safe to
  /// call when no walk is in flight (no-op).
  void cancelWalkTheRange() {
    if (!_walkActive) return;
    _walkActive = false;
    unawaited(tts.stop());
    notifyListeners();
  }

  /// Test seam. Forces the drill phase without driving the real state
  /// machine — used to assert identify-hold / walk-the-range safety gates.
  @visibleForTesting
  void debugSetPhase(DrillPhase phase) {
    _setPhase(phase);
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

  Future<void> startDrill(DrillConfig config, {String? presetName}) async {
    currentSession = DrillSession(config: config, presetName: presetName);
    _persistedDrillIds.remove(currentSession!.drillId);
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
          _onDrillFinished(incomplete: true);
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
    _onDrillFinished(incomplete: true);
    _setPhase(DrillPhase.finished);
  }

  /// Ids of drills that have already been persisted via [_onDrillFinished].
  /// Guards the FIN + STOP_ACK + SNAP_REPLY triple-fire window: whichever
  /// arrives first wins, the others become no-ops.
  final Set<String> _persistedDrillIds = <String>{};

  /// Drill-end persistence pipeline (#16 + #17). Writes the drill log JSON
  /// and appends a session summary. Swallows errors per path — UI must not
  /// block on persistence.
  ///
  /// Skips entirely when the session never saw an ACT (drill aborted during
  /// arming), matching addendum §4.E "only save drills that actually ran".
  void _onDrillFinished({required bool incomplete}) {
    final session = currentSession;
    if (session == null) return;
    if (_persistedDrillIds.contains(session.drillId)) return;

    final activations = session.events
        .where((e) => e.type == EventType.targetActivated)
        .toList(growable: false);
    if (activations.isEmpty) {
      // Drill never armed successfully — nothing meaningful to record.
      return;
    }
    _persistedDrillIds.add(session.drillId);

    final presetName = session.presetName ?? 'Custom';

    // Capture target names at drill-end so historical logs survive renames.
    final targetNames = Map<int, String>.from(_targetNames);

    // 1. Write the JSON log. Errors are surfaced only via debugPrint.
    try {
      final payload = DrillLogCodec.encode(
        session,
        presetName: presetName,
        targetNames: targetNames,
      );
      unawaited(drillLogs.writeLog(session.drillId, payload).catchError((e) {
        debugPrint('drillLogs.writeLog failed: $e');
      }));
    } catch (e) {
      debugPrint('drill log encode failed: $e');
    }

    // 2. Append a summary for Recent Drills.
    try {
      final completions = session.events
          .where((e) => e.type == EventType.targetComplete)
          .length;
      final violations = session.events
          .where((e) => e.type == EventType.noShootViolation)
          .length;
      final lateHits =
          session.events.where((e) => e.type == EventType.lateHit).length;

      final summary = SessionSummary.create(
        drillId: session.drillId,
        presetName: presetName,
        startedAt: session.startTime,
        duration: session.elapsed,
        completions: completions,
        violations: violations,
        lateHits: lateHits,
        incomplete: incomplete,
      );
      unawaited(sessions.appendDrill(summary).catchError((e) {
        debugPrint('sessions.appendDrill failed: $e');
      }));
    } catch (e) {
      debugPrint('session summary build failed: $e');
    }
  }

  // -------------------------------------------------- User-named targets (§4.B)

  /// Persist a custom display name for [targetId] and update the in-memory
  /// snapshot so the resolver returns it immediately. Pass null or empty to
  /// revert to the `T{id}` fallback.
  Future<void> setTargetName(int targetId, String? name) async {
    _targetPrefsHydrated = true;
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _targetNames.remove(targetId);
      await preferences.setTargetName(targetId, null);
    } else {
      _targetNames[targetId] = trimmed;
      await preferences.setTargetName(targetId, trimmed);
    }
    notifyListeners();
  }

  /// Flip [TargetUnit.isNoShoot] in place. Transient drill-setup state;
  /// not persisted (addendum §4.B — cleared on reconnect).
  void toggleNoShoot(int targetId) {
    for (final t in targets) {
      if (t.id == targetId) {
        t.isNoShoot = !t.isNoShoot;
        notifyListeners();
        return;
      }
    }
  }

  /// Soft-delete [targetId] from the fleet. Persisted so removals survive
  /// relaunch; reversible via [restoreTarget] or the AppBar "Show removed"
  /// toggle.
  Future<void> removeTarget(int targetId) async {
    _targetPrefsHydrated = true;
    _removedTargetIds.add(targetId);
    await preferences.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  Future<void> restoreTarget(int targetId) async {
    _targetPrefsHydrated = true;
    _removedTargetIds.remove(targetId);
    await preferences.setRemovedTargetIds(_removedTargetIds);
    notifyListeners();
  }

  /// AppBar overflow toggle: show soft-deleted targets in the chip list.
  void toggleShowRemoved() {
    _showRemoved = !_showRemoved;
    notifyListeners();
  }

  /// Targets filtered through the removed-ids set — what the setup screen
  /// should render. When [showRemoved] is on, all targets are returned
  /// (callers render the REMOVED pill via [isRemoved]).
  List<TargetUnit> get visibleTargets {
    if (_showRemoved) return targets;
    return targets.where((t) => !_removedTargetIds.contains(t.id)).toList();
  }

  bool isRemoved(int targetId) => _removedTargetIds.contains(targetId);

  @override
  void dispose() {
    _armingTimeout?.cancel();
    _stoppingTimeout?.cancel();
    for (final t in _identifyHoldTimers.values) {
      t.cancel();
    }
    _identifyHoldTimers.clear();
    _identifyHoldActiveIds.clear();
    _walkActive = false;
    unawaited(tts.stop());
    _dataSub?.cancel();
    _statusSub?.cancel();
    bleService.dispose();
    super.dispose();
  }
}
