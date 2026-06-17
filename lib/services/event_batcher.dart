// lib/services/event_batcher.dart
//
// Buffers SessionEvents during a live drill; flushes them to onFlush on a
// timer (default 500ms) and on stop(). Keeps the drill-hot path off per-event
// fsync latency.

import 'dart:async';

import '../constants.dart';
import '../models/session_event.dart';

typedef EventFlushCallback = Future<void> Function(List<SessionEvent> events);

class EventBatcher {
  final EventFlushCallback onFlush;
  final Duration flushInterval;

  final List<SessionEvent> _buffer = [];
  Timer? _timer;
  bool _running = false;

  EventBatcher({
    required this.onFlush,
    this.flushInterval = kEventBatchFlushInterval,
  });

  void start() {
    if (_running) return;
    _running = true;
    _buffer.clear();
    _timer = Timer.periodic(flushInterval, (_) => _flush());
  }

  void add(SessionEvent event) {
    if (!_running) return;
    _buffer.add(event);
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final toSend = List<SessionEvent>.unmodifiable(_buffer);
    _buffer.clear();
    await onFlush(toSend);
  }
}
