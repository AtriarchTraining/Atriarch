import '../models/drill_config.dart';
import '../models/session_event.dart';

class TransmitterProtocol {
  static String encodeDiscovery() => 'DISC/';
  static String encodeIdentify(int targetId) => 'IDENT/$targetId/';
  static String encodeStop() => 'STOP/';

  static String encodeDrillStart(DrillConfig config) {
    if (config.programType == ProgramType.programA) {
      return _encodeProgramA(config);
    } else {
      return _encodeProgramB(config);
    }
  }

  static String _encodeProgramA(DrillConfig config) {
    final buf = StringBuffer('A/');
    buf.write('${config.startMin}/${config.startMax}/');
    buf.write('${config.delayMin}/${config.delayMax}/');
    buf.write('${config.hitsMin}/${config.hitsMax}/');

    for (int g = 0; g < 5; g++) {
      if (g < config.groups.length && config.groups[g].targetIds.isNotEmpty) {
        buf.write(config.groups[g].targetIds.join(','));
      } else {
        buf.write('0');
      }
      buf.write('/');
    }

    if (config.noShootIds.isNotEmpty) {
      buf.write(config.noShootIds.join(','));
    } else {
      buf.write('0');
    }
    buf.write('/');
    buf.write('${config.iterations}/');
    return buf.toString();
  }

  static String _encodeProgramB(DrillConfig config) {
    final buf = StringBuffer('B/');
    buf.write('${config.startMin}/${config.startMax}/');
    buf.write('${config.delayMin}/${config.delayMax}/');
    buf.write('${config.hitsMin}/${config.hitsMax}/');
    buf.write(config.targetIds.join(','));
    buf.write('/');
    if (config.noShootIds.isNotEmpty) {
      buf.write(config.noShootIds.join(','));
    } else {
      buf.write('0');
    }
    buf.write('/');
    buf.write('${config.iterations}/');
    return buf.toString();
  }

  static dynamic decodeTelemetry(String message) {
    final msg = message.trim();

    if (msg.startsWith('D/') && msg != 'DDONE/') {
      final parts = msg.split('/');
      final id = int.tryParse(parts[1]);
      if (id != null) return DiscoveredTarget(id);
    }
    if (msg == 'DDONE/') return DiscoveryDone();

    if (msg.startsWith('ACT/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.targetActivated,
        targetId: int.tryParse(parts[1]),
      );
    }
    if (msg.startsWith('HIT/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.hitDetected,
        targetId: int.tryParse(parts[1]),
        hitNumber: int.tryParse(parts[2]),
        requiredHits: int.tryParse(parts[3]),
      );
    }
    if (msg.startsWith('DONE/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.targetComplete,
        targetId: int.tryParse(parts[1]),
        totalTimeMs: int.tryParse(parts[2]),
      );
    }
    if (msg.startsWith('NS/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.noShootViolation,
        targetId: int.tryParse(parts[1]),
      );
    }
    if (msg.startsWith('LATE/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.lateHit,
        targetId: int.tryParse(parts[1]),
      );
    }
    if (msg == 'FIN/') return SessionEvent(type: EventType.drillFinished);

    if (msg.startsWith('ERR/')) {
      final parts = msg.split('/');
      return SessionEvent(
        type: EventType.error,
        errorDetail: parts.sublist(1).join('/'),
      );
    }

    return null;
  }
}

class DiscoveredTarget {
  final int id;
  DiscoveredTarget(this.id);
}

class DiscoveryDone {}
