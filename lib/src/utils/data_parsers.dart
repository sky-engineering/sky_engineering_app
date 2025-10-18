// lib/src/utils/data_parsers.dart
import 'package:cloud_firestore/cloud_firestore.dart';

Map<String, dynamic> mapFrom(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

String readString(
  Map<String, dynamic> data,
  String key, {
  String fallback = '',
}) {
  return parseString(data[key], fallback: fallback);
}

String? readStringOrNull(Map<String, dynamic> data, String key) {
  return parseStringOrNull(data[key]);
}

double readDouble(
  Map<String, dynamic> data,
  String key, {
  double fallback = 0,
}) {
  return parseDouble(data[key], fallback: fallback);
}

double? readDoubleOrNull(Map<String, dynamic> data, String key) {
  return parseDoubleOrNull(data[key]);
}

int? readIntOrNull(Map<String, dynamic> data, String key) {
  return parseIntOrNull(data[key]);
}

bool readBool(Map<String, dynamic> data, String key, {bool fallback = false}) {
  return parseBool(data[key], fallback: fallback);
}

bool? readBoolOrNull(Map<String, dynamic> data, String key) {
  return parseBoolOrNull(data[key]);
}

DateTime? readDateTime(Map<String, dynamic> data, String key) {
  return parseDateTime(data[key]);
}

Map<String, dynamic>? readMapOrNull(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<T>? readListOrNull<T>(
  Map<String, dynamic> data,
  String key,
  T? Function(dynamic value) convert,
) {
  final value = data[key];
  if (value is Iterable) {
    final result = <T>[];
    for (final entry in value) {
      final converted = convert(entry);
      if (converted != null) {
        result.add(converted);
      }
    }
    return result;
  }
  return null;
}

List<String>? readStringListOrNull(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) {
    return null;
  }
  if (value is Iterable) {
    final result = value
        .map((entry) => parseStringOrNull(entry))
        .whereType<String>()
        .toList();
    return result.isEmpty ? null : result;
  }
  final parsed = parseStringOrNull(value);
  if (parsed == null) {
    return null;
  }
  return parsed
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

String parseString(Object? value, {String fallback = ''}) {
  return parseStringOrNull(value) ?? fallback;
}

String? parseStringOrNull(Object? value) {
  if (value == null) return null;
  final text = value is String ? value : value.toString();
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double parseDouble(Object? value, {double fallback = 0}) {
  return parseDoubleOrNull(value) ?? fallback;
}

double? parseDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value.toString().trim());
  return parsed;
}

int? parseIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString().trim());
  return parsed;
}

bool parseBool(Object? value, {bool fallback = false}) {
  return parseBoolOrNull(value) ?? fallback;
}

bool? parseBoolOrNull(Object? value) {
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    switch (normalized) {
      case 'true':
      case 'yes':
      case 'y':
      case '1':
        return true;
      case 'false':
      case 'no':
      case 'n':
      case '0':
        return false;
    }
  }
  return null;
}

DateTime? parseDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num) {
    final millis = value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }
  return null;
}

Timestamp? timestampFromDate(DateTime? value) {
  if (value == null) return null;
  return Timestamp.fromDate(value);
}
