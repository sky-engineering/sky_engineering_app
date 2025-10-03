// lib/src/utils/phone_utils.dart
import 'package:flutter/services.dart';

/// Extract digits from [input].
String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

String _formatDigits(String digits, {bool allowPartial = false}) {
  if (digits.isEmpty) return '';
  final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
  final buffer = StringBuffer();
  final len = limited.length;

  buffer.write('(');
  if (len >= 1) {
    buffer.write(limited.substring(0, len >= 3 ? 3 : len));
  }

  if (len >= 3) {
    buffer.write(')');
  }

  if (len > 3) {
    buffer.write(' ');
    final secondChunkEnd = len >= 6 ? 6 : len;
    buffer.write(limited.substring(3, secondChunkEnd));
    if (len >= 7) {
      buffer.write('-');
      buffer.write(limited.substring(6, len));
    }
  } else if (allowPartial) {
    // Leave space as user types the fourth digit even if dash not ready yet.
  }

  final extra = digits.length > 10 ? digits.substring(10) : '';
  if (extra.isNotEmpty) {
    buffer.write(' x$extra');
  }

  return buffer.toString();
}

/// Format a phone number using US pattern "(123) 456-7890".
/// Accepts partial input for live typing.
String formatPhoneForInput(String value) {
  final digits = _digitsOnly(value);
  if (digits.isEmpty) return '';
  return _formatDigits(digits, allowPartial: true);
}

/// Format a stored phone number for display.
String formatPhoneForDisplay(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  final digits = _digitsOnly(value);
  if (digits.isEmpty) return value.trim();
  return _formatDigits(digits, allowPartial: false);
}

/// Normalize a phone input to just digits (max 10). Returns null when empty.
String? normalizePhone(String? value) {
  if (value == null) return null;
  final digits = _digitsOnly(value);
  if (digits.isEmpty) return null;
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

class UsPhoneInputFormatter extends TextInputFormatter {
  const UsPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digitsOnly(newValue.text);
    final limited = digits.length > 10 ? digits.substring(0, 10) : digits;
    final formatted = _formatDigits(limited, allowPartial: true);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
