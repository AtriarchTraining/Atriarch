// lib/services/contact_validator.dart
//
// Email format validation + phone E.164 normalization.
// Deliberately permissive: we save invalid inputs as-is (with a UI warning),
// we do not BLOCK the save. These helpers are the warn-check.

class ContactValidator {
  /// Simple RFC-5322-ish check. Not exhaustive; just catches obvious typos.
  static bool isValidEmail(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(trimmed);
  }

  /// Returns the phone in E.164 format (leading `+`, country code, digits).
  /// Returns null if the input can't be reasonably parsed. Rules:
  /// - If already starts with `+`, strip non-digits after the `+` and require
  ///   the result to have 8–15 digits after the `+`.
  /// - If 10 digits, assume US and prefix `+1`.
  /// - If 11 digits starting with `1`, prefix `+`.
  /// - Otherwise null.
  static String? normalizePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+1$digits';
    if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
    return null;
  }
}
