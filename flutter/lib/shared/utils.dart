/// Shared helpers — port of `src/lib/utils.ts`.
library;

import 'package:uuid/uuid.dart';

/// Generate a v4-style UUID (crypto-random via the uuid package).
String generateId() => const Uuid().v4();

/// Redact secrets from error messages and log strings.
String redactLogSecrets(String text) {
  return text
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{20,}'), 'sk-***REDACTED***')
      .replaceAll(RegExp(r'gsk_[A-Za-z0-9_-]{20,}'), 'gsk_***REDACTED***')
      .replaceAll(RegExp(r'AIza[A-Za-z0-9_-]{30,}'), 'AIza***REDACTED***')
      .replaceAllMapped(
        RegExp(r'(Bearer\s+)[A-Za-z0-9._-]{20,}', caseSensitive: false),
        (m) => '${m.group(1)}***REDACTED***',
      )
      .replaceAllMapped(
        RegExp(r'(key=)[A-Za-z0-9._-]{20,}', caseSensitive: false),
        (m) => '${m.group(1)}***REDACTED***',
      )
      .replaceAllMapped(
        RegExp(r'(api[_-]?key[=:]\s*)[^"]{20,}', caseSensitive: false),
        (m) => '${m.group(1)}***REDACTED***',
      );
}