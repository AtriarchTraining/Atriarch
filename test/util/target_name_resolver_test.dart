import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/util/target_name_resolver.dart';

void main() {
  group('TargetNameResolver.display', () {
    test('returns custom name when present', () {
      const resolver = TargetNameResolver({1: 'Flipper', 2: 'Popper'});
      expect(resolver.display(1), 'Flipper');
      expect(resolver.display(2), 'Popper');
    });

    test('returns T/U_## fallback with zero-padding for ids 1-9', () {
      const resolver = TargetNameResolver({});
      expect(resolver.display(1), 'T/U_01');
      expect(resolver.display(7), 'T/U_07');
      expect(resolver.display(9), 'T/U_09');
    });

    test('returns T/U_## fallback for two-digit ids', () {
      const resolver = TargetNameResolver({});
      expect(resolver.display(10), 'T/U_10');
      expect(resolver.display(42), 'T/U_42');
    });

    test('falls back when only some ids have custom names', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.display(1), 'Flipper');
      expect(resolver.display(2), 'T/U_02');
    });

    test('customName returns the stored custom name or null', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.customName(1), 'Flipper');
      expect(resolver.customName(2), isNull);
    });
  });
}
