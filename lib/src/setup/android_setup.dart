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
        error:
            'Directory android/ not found. Please run this command from the root of a Flutter project.',
      );
    }

    try {
      // 1. Scan for flavor env files (.env.*)
      final flavorEnvFiles = _scanFlavorEnvFiles();

      // 2. Update android/app/build.gradle or build.gradle.kts
      final gradleResults = _updateAppBuildGradle(flavorEnvFiles);
      messages.addAll(gradleResults);

      // 3. Ensure proguard-rules.pro preserves BuildConfig from R8 obfuscation
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

  /// Scans projectDir and projectDir/env for .env.* files.
  /// Returns a map of flavorName -> relativeFilePath (e.g. dev -> env/.env.dev).
  Map<String, String> _scanFlavorEnvFiles() {
    final flavorMap = <String, String>{};

    for (final dir in [projectDir, Directory('${projectDir.path}/env')]) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final filename = file.uri.pathSegments.last;
        if (!filename.startsWith('.env.') ||
            filename.endsWith('.example') ||
            filename.endsWith('.sample') ||
            filename.endsWith('.template') ||
            filename.endsWith('.bak')) {
          continue;
        }

        final flavor = filename.substring('.env.'.length).toLowerCase();
        if (flavor.isEmpty) continue;

        // Relative path from projectDir
        final relPath = file.path.startsWith(projectDir.path)
            ? file.path.substring(projectDir.path.length + 1)
            : filename;

        flavorMap[flavor] = relPath;
      }
    }

    return flavorMap;
  }

  /// Updates android/app/build.gradle or build.gradle.kts
  List<String> _updateAppBuildGradle(Map<String, String> flavorEnvFiles) {
    final results = <String>[];
    final buildGradle = File('${androidDir.path}/app/build.gradle');
    final buildGradleKts = File('${androidDir.path}/app/build.gradle.kts');

    if (buildGradleKts.existsSync()) {
      results.addAll(_updateKotlinDsl(buildGradleKts, flavorEnvFiles));
    } else if (buildGradle.existsSync()) {
      results.addAll(_updateGroovyDsl(buildGradle, flavorEnvFiles));
    } else {
      results.add('Warning: android/app/build.gradle not found, skipping gradle setup');
    }

    return results;
  }

  /// Configures Kotlin DSL (build.gradle.kts)
  List<String> _updateKotlinDsl(File file, Map<String, String> flavorEnvFiles) {
    final results = <String>[];
    String content = file.readAsStringSync();
    bool modified = false;

    final androidBlockRegex = RegExp(r'(^|\n)\s*android\s*\{', multiLine: true);
    final match = androidBlockRegex.firstMatch(content);
    if (match == null) {
      results.add('Warning: android { ... } block not found in build.gradle.kts');
      return results;
    }
    final androidIndex = match.start;

    // 1. Inject envConfigFiles mapping if multiple flavor env files exist
    if (flavorEnvFiles.isNotEmpty && !content.contains('envConfigFiles')) {
      final entries = flavorEnvFiles.entries
          .map((e) => '    "${e.key}" to "${e.value}"')
          .join(',\n');
      final envConfigFilesBlock =
          'project.extra["envConfigFiles"] = mapOf(\n$entries\n)\n\n';

      content = content.substring(0, androidIndex) +
          envConfigFilesBlock +
          content.substring(androidIndex);
      modified = true;
      results.add(
          'Configured project.extra["envConfigFiles"] for flavors: ${flavorEnvFiles.keys.join(', ')}');
    } else if (content.contains('envConfigFiles')) {
      results.add('project.extra["envConfigFiles"] already configured');
    }

    // 2. Apply dotenv.gradle right before android { ... }
    if (!content.contains('dotenv.gradle')) {
      const applyDotenv =
          'apply(from = "\${project(":flutter_config").projectDir}/dotenv.gradle")\n\n';
      // Find android block again after potential envConfigFiles insertion
      final newAndroidMatch = androidBlockRegex.firstMatch(content)!;
      final newAndroidIndex = newAndroidMatch.start;

      content = content.substring(0, newAndroidIndex) +
          applyDotenv +
          content.substring(newAndroidIndex);
      modified = true;
      results.add('Applied dotenv.gradle in android/app/build.gradle.kts');
    } else {
      results.add('android/app/build.gradle.kts already applies dotenv.gradle');
    }

    // 3. Ensure buildFeatures.buildConfig = true (required for AGP 8.0+)
    if (!content.contains('buildConfig = true') && !content.contains('buildConfig(true)')) {
      if (content.contains(RegExp(r'buildFeatures\s*\{'))) {
        content = content.replaceFirstMapped(
          RegExp(r'(buildFeatures\s*\{)'),
          (m) => '${m.group(1)}\n        buildConfig = true',
        );
      } else {
        content = content.replaceFirstMapped(
          RegExp(r'(android\s*\{)'),
          (m) => '${m.group(1)}\n    buildFeatures.buildConfig = true',
        );
      }
      modified = true;
      results.add('Enabled buildFeatures.buildConfig = true in build.gradle.kts');
    } else {
      results.add('buildFeatures.buildConfig already enabled');
    }

    // 4. Ensure resValue("string", "build_config_package", namespace) in defaultConfig
    final namespace = _resolveNamespace(content);
    if (namespace != null && !content.contains('build_config_package')) {
      final defaultConfigRegex = RegExp(r'(defaultConfig\s*\{)');
      if (defaultConfigRegex.hasMatch(content)) {
        content = content.replaceFirstMapped(
          defaultConfigRegex,
          (m) =>
              '${m.group(1)}\n        resValue("string", "build_config_package", "$namespace")',
        );
        modified = true;
        results.add(
            'Added resValue("string", "build_config_package", "$namespace") to defaultConfig');
      }
    } else if (content.contains('build_config_package')) {
      results.add('build_config_package already configured in defaultConfig');
    }

    if (modified) {
      file.writeAsStringSync(content);
    }

    return results;
  }

  /// Configures Groovy DSL (build.gradle)
  List<String> _updateGroovyDsl(File file, Map<String, String> flavorEnvFiles) {
    final results = <String>[];
    String content = file.readAsStringSync();
    bool modified = false;

    final androidBlockRegex = RegExp(r'(^|\n)\s*android\s*\{', multiLine: true);
    final match = androidBlockRegex.firstMatch(content);
    if (match == null) {
      results.add('Warning: android { ... } block not found in build.gradle');
      return results;
    }
    final androidIndex = match.start;

    // 1. Inject envConfigFiles mapping if multiple flavor env files exist
    if (flavorEnvFiles.isNotEmpty && !content.contains('envConfigFiles')) {
      final entries = flavorEnvFiles.entries
          .map((e) => '    ${e.key}: "${e.value}",')
          .join('\n');
      final envConfigFilesBlock =
          'project.ext.envConfigFiles = [\n$entries\n]\n\n';

      content = content.substring(0, androidIndex) +
          envConfigFilesBlock +
          content.substring(androidIndex);
      modified = true;
      results.add(
          'Configured project.ext.envConfigFiles for flavors: ${flavorEnvFiles.keys.join(', ')}');
    } else if (content.contains('envConfigFiles')) {
      results.add('project.ext.envConfigFiles already configured');
    }

    // 2. Apply dotenv.gradle right before android { ... }
    if (!content.contains('dotenv.gradle')) {
      const applyDotenv =
          'apply from: project(\':flutter_config\').projectDir.getPath() + "/dotenv.gradle"\n\n';
      final newAndroidMatch = androidBlockRegex.firstMatch(content)!;
      final newAndroidIndex = newAndroidMatch.start;

      content = content.substring(0, newAndroidIndex) +
          applyDotenv +
          content.substring(newAndroidIndex);
      modified = true;
      results.add('Applied dotenv.gradle in android/app/build.gradle');
    } else {
      results.add('android/app/build.gradle already applies dotenv.gradle');
    }

    // 3. Ensure buildFeatures { buildConfig true } (required for AGP 8.0+)
    if (!content.contains('buildConfig true') && !content.contains('buildConfig = true')) {
      if (content.contains(RegExp(r'buildFeatures\s*\{'))) {
        content = content.replaceFirstMapped(
          RegExp(r'(buildFeatures\s*\{)'),
          (m) => '${m.group(1)}\n        buildConfig true',
        );
      } else {
        content = content.replaceFirstMapped(
          RegExp(r'(android\s*\{)'),
          (m) => '${m.group(1)}\n    buildFeatures {\n        buildConfig true\n    }',
        );
      }
      modified = true;
      results.add('Enabled buildFeatures { buildConfig true } in build.gradle');
    } else {
      results.add('buildFeatures.buildConfig already enabled');
    }

    // 4. Ensure resValue "string", "build_config_package", namespace in defaultConfig
    final namespace = _resolveNamespace(content);
    if (namespace != null && !content.contains('build_config_package')) {
      final defaultConfigRegex = RegExp(r'(defaultConfig\s*\{)');
      if (defaultConfigRegex.hasMatch(content)) {
        content = content.replaceFirstMapped(
          defaultConfigRegex,
          (m) =>
              '${m.group(1)}\n        resValue "string", "build_config_package", "$namespace"',
        );
        modified = true;
        results.add(
            'Added resValue "string", "build_config_package", "$namespace" to defaultConfig');
      }
    } else if (content.contains('build_config_package')) {
      results.add('build_config_package already configured in defaultConfig');
    }

    if (modified) {
      file.writeAsStringSync(content);
    }

    return results;
  }

  /// Resolves the app package/namespace:
  /// 1. From android { namespace = "..." } or namespace "..."
  /// 2. From android/app/src/main/AndroidManifest.xml package attribute
  String? _resolveNamespace(String gradleContent) {
    // 1. From gradle namespace
    final namespaceMatch = RegExp(r'namespace\s*=?\s*["\x27]([^"\x27]+)["\x27]')
        .firstMatch(gradleContent);
    if (namespaceMatch != null) {
      return namespaceMatch.group(1);
    }

    // 2. From AndroidManifest.xml
    final manifestFile =
        File('${androidDir.path}/app/src/main/AndroidManifest.xml');
    if (manifestFile.existsSync()) {
      try {
        final manifestContent = manifestFile.readAsStringSync();
        final packageMatch =
            RegExp(r'package\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(manifestContent);
        if (packageMatch != null) {
          return packageMatch.group(1);
        }
      } catch (_) {}
    }

    return null;
  }

  /// Step 3: Ensure proguard-rules.pro preserves BuildConfig from R8 obfuscation
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
