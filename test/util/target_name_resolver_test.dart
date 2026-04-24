import 'package:atriarch/util/target_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TargetNameResolver', () {
    test('display() returns the custom name when saved', () {
      const resolver = TargetNameResolver({1: 'Flipper', 3: 'Runner'});
      expect(resolver.display(1), 'Flipper');
      expect(resolver.display(3), 'Runner');
    });

    test('display() falls back to T{id} when no custom name is saved', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.display(2), 'T2');
      expect(resolver.display(7), 'T7');
    });

    test('display() falls back for an empty map', () {
      const resolver = TargetNameResolver(<int, String>{});
      expect(resolver.display(0), 'T0');
      expect(resolver.display(42), 'T42');
    });

    test('customName() returns the string or null', () {
      const resolver = TargetNameResolver({1: 'Flipper'});
      expect(resolver.customName(1), 'Flipper');
      expect(resolver.customName(2), isNull);
    });
  });
}
