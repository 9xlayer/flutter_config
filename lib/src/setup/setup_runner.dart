import 'dart:io';
import 'android_setup.dart';
import 'ios_setup.dart';
import 'platform_setup.dart';

/// Orchestrates setup automation across platforms.
class SetupRunner {
  final Directory projectDir;

  SetupRunner(this.projectDir);

  List<PlatformSetup> get supportedPlatforms => [
        IosSetup(projectDir),
        AndroidSetup(projectDir),
      ];

  void run(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      _printHelp();
      exit(0);
    }

    final targetPlatforms = _resolveTargetPlatforms(args);

    if (targetPlatforms.isEmpty) {
      print('❌ No applicable platforms found (neither ios/ nor android/ directories exist).');
      print('   Please run this command from the root of a Flutter project.\n');
      exit(1);
    }

    print('\n⚡ Running flutter_config setup for: ${targetPlatforms.map((p) => p.platformName).join(', ')}...\n');

    bool allSuccess = true;

    for (final platform in targetPlatforms) {
      print('📦 [${platform.platformName}]');
      final result = platform.run();

      for (final msg in result.messages) {
        print('  ✔ $msg');
      }

      for (final warn in result.warnings) {
        print('  ⚠ $warn');
      }

      if (!result.success) {
        allSuccess = false;
        print('\n❌ ${platform.platformName} setup failed:');
        print('   ${result.error}\n');
      } else {
        print('');
      }
    }

    if (allSuccess) {
      print('✨ Setup completed successfully! 🎉');
      print('   You can now run:');
      print('     flutter run\n');
    } else {
      print('⚠️  Setup finished with some errors.\n');
      exit(1);
    }
  }

  List<PlatformSetup> _resolveTargetPlatforms(List<String> args) {
    final platforms = supportedPlatforms;

    // Explicit flags or positional arguments
    final hasIosFlag = args.contains('--ios') || args.contains('-i') || args.contains('ios');
    final hasAndroidFlag = args.contains('--android') || args.contains('-a') || args.contains('android');

    if (hasIosFlag || hasAndroidFlag) {
      return platforms.where((p) {
        if (hasIosFlag && p.flag == 'ios') return true;
        if (hasAndroidFlag && p.flag == 'android') return true;
        return false;
      }).toList();
    }

    // Default: auto-detect all applicable platforms
    return platforms.where((p) => p.isApplicable).toList();
  }

  void _printHelp() {
    print('''
flutter_config setup tool

Usage:
  dart run flutter_config:setup [options]

Options:
  --ios       Configure iOS project only
  --android   Configure Android project only
  --help, -h  Show this help message

Default behavior:
  Auto-detects available platforms (ios/ and android/ directories)
  and configures all found platforms automatically.

What this command does:
  • iOS:
    1. Creates placeholder ios/Flutter/GeneratedDotEnv.plist
    2. Ensures #include? "tmp.xcconfig" in Debug & Release xcconfigs
    3. Registers GeneratedDotEnv.plist in Runner.xcodeproj (Copy Bundle Resources)
    4. Configures Scheme Pre-actions to generate .plist & .xcconfig at build time
    5. Updates .gitignore for tmp.xcconfig

  • Android:
    1. Applies dotenv.gradle in android/app/build.gradle
    2. Configures proguard-rules.pro to preserve BuildConfig in release mode
''');
  }
}
