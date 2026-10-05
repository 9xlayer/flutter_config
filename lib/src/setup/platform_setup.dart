import 'dart:io';

/// Result status of a platform setup process.
class SetupResult {
  final bool success;
  final List<String> messages;
  final List<String> warnings;
  final String? error;

  SetupResult({
    required this.success,
    this.messages = const [],
    this.warnings = const [],
    this.error,
  });
}

/// Abstract contract for platform-specific setup automation.
abstract class PlatformSetup {
  /// Name of the platform (e.g., 'iOS', 'Android').
  String get platformName;

  /// CLI flag to explicitly target this platform (e.g., 'ios', 'android').
  String get flag;

  /// Directory of the Flutter project.
  Directory get projectDir;

  /// Whether this platform exists in the current project.
  bool get isApplicable;

  /// Executes setup workflow for this platform.
  SetupResult run({bool verbose = false});
}
