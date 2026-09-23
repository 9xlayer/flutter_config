import 'dart:io';
import 'package:flutter_config/src/setup/android_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_config_android_test_');
    Directory('${tempDir.path}/android/app').createSync(recursive: true);
    File('${tempDir.path}/android/app/build.gradle').writeAsStringSync('''
apply plugin: 'com.android.application'
apply plugin: 'kotlin-android'
apply from: "\$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

android {
    compileSdkVersion 33
}
''');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AndroidSetup configures build.gradle and proguard rules', () {
    final setup = AndroidSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    final buildGradle = File('${tempDir.path}/android/app/build.gradle').readAsStringSync();
    expect(buildGradle, contains('dotenv.gradle'));

    final proguard = File('${tempDir.path}/android/app/proguard-rules.pro');
    expect(proguard.existsSync(), isTrue);
    expect(proguard.readAsStringSync(), contains('BuildConfig'));
  });

  test('AndroidSetup is idempotent', () {
    final setup = AndroidSetup(tempDir);
    final result1 = setup.run();
    expect(result1.success, isTrue);

    final buildGradle1 = File('${tempDir.path}/android/app/build.gradle').readAsStringSync();
    final proguard1 = File('${tempDir.path}/android/app/proguard-rules.pro').readAsStringSync();

    final result2 = setup.run();
    expect(result2.success, isTrue);

    final buildGradle2 = File('${tempDir.path}/android/app/build.gradle').readAsStringSync();
    final proguard2 = File('${tempDir.path}/android/app/proguard-rules.pro').readAsStringSync();

    expect(buildGradle2, equals(buildGradle1));
    expect(proguard2, equals(proguard1));
  });
}
