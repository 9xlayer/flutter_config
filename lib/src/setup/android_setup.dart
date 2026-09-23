import 'dart:io';
import 'platform_setup.dart';

/// Automates Android configuration for flutter_config.
class AndroidSetup implements PlatformSetup {
  @override
  final Directory projectDir;

  AndroidSetup(this.projectDir);

  @override
  String get platformName => 'Android';

  @override
  String get flag => 'android';

  Directory get androidDir => Directory('${projectDir.path}/android');

  bool get isAndroidProject => androidDir.existsSync();

  @override
  bool get isApplicable => isAndroidProject;

  @override
  SetupResult run({bool verbose = false}) {
    final messages = <String>[];
    final warnings = <String>[];

    if (!isAndroidProject) {
      return SetupResult(
        success: false,
        error: 'Directory android/ not found. Please run this command from the root of a Flutter project.',
      );
    }

    try {
      // 1. Update android/app/build.gradle
      final gradleResult = _updateAppBuildGradle();
      messages.add(gradleResult);

      // 2. Ensure proguard-rules.pro preserves BuildConfig
      final proguardResult = _ensureProguardRules();
      messages.add(proguardResult);

      return SetupResult(
        success: true,
        messages: messages,
        warnings: warnings,
      );
    } catch (e, stack) {
      return SetupResult(
        success: false,
        error: 'Failed to configure Android: $e\n$stack',
      );
    }
  }

  /// Step 1: Ensure android/app/build.gradle applies dotenv.gradle
  String _updateAppBuildGradle() {
    final buildGradle = File('${androidDir.path}/app/build.gradle');
    final buildGradleKts = File('${androidDir.path}/app/build.gradle.kts');

    if (buildGradle.existsSync()) {
      String content = buildGradle.readAsStringSync();
      const dotenvLine = "apply from: project(':flutter_config').projectDir.getPath() + \"/dotenv.gradle\"";

      if (content.contains('dotenv.gradle')) {
        return 'android/app/build.gradle already applies dotenv.gradle';
      }

      // Insert right after flutter.gradle or com.android.application
      if (content.contains('flutter.gradle"')) {
        content = content.replaceFirst(
          'flutter.gradle"',
          'flutter.gradle"\n$dotenvLine',
        );
      } else if (content.contains("apply plugin: 'com.android.application'")) {
        content = content.replaceFirst(
          "apply plugin: 'com.android.application'",
          "apply plugin: 'com.android.application'\n$dotenvLine",
        );
      } else {
        content = '$dotenvLine\n$content';
      }

      buildGradle.writeAsStringSync(content);
      return 'Added dotenv.gradle to android/app/build.gradle';
    } else if (buildGradleKts.existsSync()) {
      String content = buildGradleKts.readAsStringSync();
      const dotenvKts = 'apply(from = project(":flutter_config").projectDir.path + "/dotenv.gradle")';

      if (content.contains('dotenv.gradle')) {
        return 'android/app/build.gradle.kts already applies dotenv.gradle';
      }

      content = '$content\n$dotenvKts\n';
      buildGradleKts.writeAsStringSync(content);
      return 'Added dotenv.gradle to android/app/build.gradle.kts';
    } else {
      return 'Warning: android/app/build.gradle not found, skipping gradle setup';
    }
  }

  /// Step 2: Ensure proguard-rules.pro preserves BuildConfig from R8 obfuscation
  String _ensureProguardRules() {
    final proguardFile = File('${androidDir.path}/app/proguard-rules.pro');
    const keepRule = '-keep class **.BuildConfig { *; }';

    if (!proguardFile.existsSync()) {
      proguardFile.writeAsStringSync(
        '# Preserves BuildConfig class so flutter_config variables are not stripped or obfuscated in release mode\n$keepRule\n',
      );
      return 'Created android/app/proguard-rules.pro with BuildConfig keep rule';
    } else {
      final content = proguardFile.readAsStringSync();
      if (!content.contains('BuildConfig')) {
        proguardFile.writeAsStringSync('$content\n$keepRule\n');
        return 'Added BuildConfig keep rule to android/app/proguard-rules.pro';
      } else {
        return 'android/app/proguard-rules.pro already contains BuildConfig rule';
      }
    }
  }
}
