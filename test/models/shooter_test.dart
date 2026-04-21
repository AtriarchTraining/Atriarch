import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/models/shooter.dart';

void main() {
  group('Shooter', () {
    test('round-trips through toMap / fromMap with all fields', () {
      final s = Shooter(
        id: 'abc-uuid',
        displayName: 'Jeremy',
        contactEmail: 'j@example.com',
        contactPhone: '+14155551234',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1745176800000),
        rangeBuddyUserId: 'rb-123',
      );
      final map = s.toMap();
      final back = Shooter.fromMap(map);
      expect(back.id, s.id);
      expect(back.displayName, s.displayName);
      expect(back.contactEmail, s.contactEmail);
      expect(back.contactPhone, s.contactPhone);
      expect(back.createdAt, s.createdAt);
      expect(back.rangeBuddyUserId, s.rangeBuddyUserId);
    });

    test('round-trips with null optional fields', () {
      final s = Shooter(
        id: 'abc-uuid',
        displayName: 'Jeremy',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1745176800000),
      );
      final back = Shooter.fromMap(s.toMap());
      expect(back.contactEmail, isNull);
      expect(back.contactPhone, isNull);
      expect(back.rangeBuddyUserId, isNull);
    });

    test('equality is value-based', () {
      final a = Shooter(
        id: 'x',
        displayName: 'A',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final b = Shooter(
        id: 'x',
        displayName: 'A',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
