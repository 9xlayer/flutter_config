import 'dart:io';
import 'package:flutter_config/src/setup/android_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_config_android_test_');
    Directory('${tempDir.path}/android/app').createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AndroidSetup configures Groovy build.gradle, envConfigFiles, buildConfig, and resValue', () {
    // Create flavor env files in root and env/
    File('${tempDir.path}/.env.dev').writeAsStringSync('API_URL=https://dev\n');
    Directory('${tempDir.path}/env').createSync();
    File('${tempDir.path}/env/.env.prd').writeAsStringSync('API_URL=https://prod\n');

    File('${tempDir.path}/android/app/build.gradle').writeAsStringSync('''
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.example.testapp"
    compileSdk flutter.compileSdkVersion

    defaultConfig {
        applicationId "com.example.testapp"
        minSdk flutter.minSdkVersion
    }
}
''');

    final setup = AndroidSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    final buildGradle = File('${tempDir.path}/android/app/build.gradle').readAsStringSync();

    // 1. envConfigFiles mapping configured before android block
    expect(buildGradle, contains('project.ext.envConfigFiles = ['));
    expect(buildGradle, contains('dev: ".env.dev",'));
    expect(buildGradle, contains('prd: "env/.env.prd",'));

    // 2. dotenv.gradle applied
    expect(buildGradle, contains("apply from: project(':flutter_config').projectDir.getPath() + \"/dotenv.gradle\""));

    // 3. buildFeatures.buildConfig true
    expect(buildGradle, contains('buildFeatures {'));
    expect(buildGradle, contains('buildConfig true'));

    // 4. resValue build_config_package
    expect(buildGradle, contains('resValue "string", "build_config_package", "com.example.testapp"'));

    // 5. Proguard keep rule
    final proguard = File('${tempDir.path}/android/app/proguard-rules.pro');
    expect(proguard.existsSync(), isTrue);
    expect(proguard.readAsStringSync(), contains('-keep class **.BuildConfig { *; }'));
  });

  test('AndroidSetup configures Kotlin DSL build.gradle.kts with AGP 8+ features', () {
    // Create flavor env files
    Directory('${tempDir.path}/env').createSync();
    File('${tempDir.path}/env/.env.alpha').writeAsStringSync('API_URL=https://alpha\n');
    File('${tempDir.path}/env/.env.uat').writeAsStringSync('API_URL=https://uat\n');

    File('${tempDir.path}/android/app/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "co.legato.testapp"
    compileSdk = 34

    defaultConfig {
        applicationId = "co.legato.testapp"
        minSdk = 24
    }
}
''');

    final setup = AndroidSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    final buildGradleKts = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();

    // 1. envConfigFiles mapping in Kotlin DSL
    expect(buildGradleKts, contains('project.extra["envConfigFiles"] = mapOf('));
    expect(buildGradleKts, contains('"alpha" to "env/.env.alpha"'));
    expect(buildGradleKts, contains('"uat" to "env/.env.uat"'));

    // 2. dotenv.gradle applied before android {
    expect(buildGradleKts, contains('apply(from = "\${project(":flutter_config").projectDir}/dotenv.gradle")'));
    final dotenvIndex = buildGradleKts.indexOf('dotenv.gradle');
    final androidIndex = buildGradleKts.indexOf('android {');
    expect(dotenvIndex, lessThan(androidIndex));

    // 3. buildFeatures.buildConfig = true
    expect(buildGradleKts, contains('buildFeatures.buildConfig = true'));

    // 4. resValue build_config_package
    expect(buildGradleKts, contains('resValue("string", "build_config_package", "co.legato.testapp")'));

    // 5. Proguard
    final proguard = File('${tempDir.path}/android/app/proguard-rules.pro');
    expect(proguard.existsSync(), isTrue);
    expect(proguard.readAsStringSync(), contains('BuildConfig'));
  });

  test('AndroidSetup is idempotent when run multiple times on Kotlin DSL', () {
    File('${tempDir.path}/.env.dev').writeAsStringSync('API_URL=https://dev\n');
    File('${tempDir.path}/android/app/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
}

android {
    namespace = "com.test"
    defaultConfig {
        applicationId = "com.test"
    }
}
''');

    final setup = AndroidSetup(tempDir);
    final result1 = setup.run();
    expect(result1.success, isTrue);

    final content1 = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
    final proguard1 = File('${tempDir.path}/android/app/proguard-rules.pro').readAsStringSync();

    final result2 = setup.run();
    expect(result2.success, isTrue);

    final content2 = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
    final proguard2 = File('${tempDir.path}/android/app/proguard-rules.pro').readAsStringSync();

    expect(content2, equals(content1));
    expect(proguard2, equals(proguard1));
  });
}
