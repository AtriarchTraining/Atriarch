import 'package:flutter_test/flutter_test.dart';
import 'package:atriarch/services/contact_validator.dart';

void main() {
  group('ContactValidator.isValidEmail', () {
    test('accepts simple valid addresses', () {
      expect(ContactValidator.isValidEmail('a@b.co'), isTrue);
      expect(ContactValidator.isValidEmail('jeremy.gill@example.com'), isTrue);
      expect(ContactValidator.isValidEmail('a+tag@b.io'), isTrue);
    });

    test('rejects obvious non-emails', () {
      expect(ContactValidator.isValidEmail(''), isFalse);
      expect(ContactValidator.isValidEmail('no-at-sign'), isFalse);
      expect(ContactValidator.isValidEmail('@nolocal.com'), isFalse);
      expect(ContactValidator.isValidEmail('no@domain'), isFalse);
      expect(ContactValidator.isValidEmail('spaces @ok.com'), isFalse);
    });
  });

  group('ContactValidator.normalizePhone', () {
    test('normalizes US-style inputs to E.164', () {
      expect(ContactValidator.normalizePhone('(415) 555-1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('415.555.1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('415-555-1234'), '+14155551234');
      expect(ContactValidator.normalizePhone('4155551234'), '+14155551234');
    });

    test('keeps already-E.164 inputs unchanged', () {
      expect(ContactValidator.normalizePhone('+14155551234'), '+14155551234');
      expect(ContactValidator.normalizePhone('+442071234567'), '+442071234567');
    });

    test('returns null for unparseable inputs', () {
      expect(ContactValidator.normalizePhone(''), isNull);
      expect(ContactValidator.normalizePhone('abc'), isNull);
      expect(ContactValidator.normalizePhone('123'), isNull);
    });
  });
}
