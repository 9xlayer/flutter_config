import 'dart:io';
import 'package:flutter_config/src/setup/ios_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  const samplePbxproj = '''// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 54;
	objects = {

/* Begin PBXBuildFile section */
		97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = 97C147001CF9000F007C117D /* LaunchScreen.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		97C146EE1CF9000F007C117D /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
		9740EEB21CF90195004384FC /* Debug.xcconfig */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.xcconfig; name = Debug.xcconfig; path = Flutter/Debug.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		9740EEB11CF90186004384FC /* Flutter */ = {
			isa = PBXGroup;
			children = (
				9740EEB21CF90195004384FC /* Debug.xcconfig */,
			);
			name = Flutter;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXResourcesBuildPhase section */
		97C146EC1CF9000F007C117D /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

	};
	rootObject = 97C146E61CF9000F007C117D /* Project object */;
}
''';

  const sampleScheme = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1510"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "97C146ED1CF9000F007C117D"
               BuildableName = "Runner.app"
               BlueprintName = "Runner"
               ReferencedContainer = "container:Runner.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
</Scheme>
''';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flutter_config_ios_test_');

    // Setup mock Flutter iOS structure
    Directory('${tempDir.path}/ios/Flutter').createSync(recursive: true);
    Directory('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes').createSync(recursive: true);

    File('${tempDir.path}/ios/Flutter/Debug.xcconfig').writeAsStringSync('#include "Generated.xcconfig"\n');
    File('${tempDir.path}/ios/Flutter/Release.xcconfig').writeAsStringSync('#include "Generated.xcconfig"\n');
    File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').writeAsStringSync(samplePbxproj);
    File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').writeAsStringSync(sampleScheme);
    File('${tempDir.path}/.gitignore').writeAsStringSync('build/\n.dart_tool/\n');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('IosSetup successfully configures clean iOS project', () {
    final setup = IosSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    // 1. Plist exists
    final plistFile = File('${tempDir.path}/ios/Flutter/GeneratedDotEnv.plist');
    expect(plistFile.existsSync(), isTrue);
    expect(plistFile.readAsStringSync(), contains('<dict/>'));

    // 2. Xcconfigs include tmp.xcconfig
    final debugXcconfig = File('${tempDir.path}/ios/Flutter/Debug.xcconfig').readAsStringSync();
    final releaseXcconfig = File('${tempDir.path}/ios/Flutter/Release.xcconfig').readAsStringSync();
    expect(debugXcconfig, contains('#include? "tmp.xcconfig"'));
    expect(releaseXcconfig, contains('#include? "tmp.xcconfig"'));

    // 3. PBXProj has file references and build phases
    final pbxproj = File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbxproj, contains('/* GeneratedDotEnv.plist in Resources */ = {isa = PBXBuildFile;'));
    expect(pbxproj, contains('/* GeneratedDotEnv.plist */ = {isa = PBXFileReference;'));
    expect(pbxproj, contains('/* GeneratedDotEnv.plist */,'));
    expect(pbxproj, contains('/* GeneratedDotEnv.plist in Resources */,'));

    // 4. Scheme has PreActions
    final scheme = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').readAsStringSync();
    expect(scheme, contains('<PreActions>'));
    expect(scheme, contains('BuildDotenvPlist.rb'));
    expect(scheme, contains('BuildXCConfig.rb'));

    // 5. Gitignore updated
    final gitignore = File('${tempDir.path}/.gitignore').readAsStringSync();
    expect(gitignore, contains('**/ios/Flutter/tmp.xcconfig'));
  });

  test('IosSetup is idempotent when run multiple times', () {
    final setup = IosSetup(tempDir);
    final result1 = setup.run();
    expect(result1.success, isTrue);

    final pbxproj1 = File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final scheme1 = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').readAsStringSync();
    final gitignore1 = File('${tempDir.path}/.gitignore').readAsStringSync();

    final result2 = setup.run();
    expect(result2.success, isTrue);

    final pbxproj2 = File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final scheme2 = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').readAsStringSync();
    final gitignore2 = File('${tempDir.path}/.gitignore').readAsStringSync();

    expect(pbxproj2, equals(pbxproj1));
    expect(scheme2, equals(scheme1));
    expect(gitignore2, equals(gitignore1));
  });

  test('IosSetup auto-detects .env.* files and generates corresponding Xcode flavor schemes', () {
    // Create flavor env files in project root
    File('${tempDir.path}/.env.dev').writeAsStringSync('API_URL=https://dev.api.com\n');
    File('${tempDir.path}/.env.staging').writeAsStringSync('API_URL=https://staging.api.com\n');

    final setup = IosSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    // Verify dev.xcscheme was auto-created and configured
    final devSchemeFile = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme');
    expect(devSchemeFile.existsSync(), isTrue);
    final devSchemeContent = devSchemeFile.readAsStringSync();
    expect(devSchemeContent, contains('.env.dev'));
    expect(devSchemeContent, contains('BuildDotenvPlist.rb'));

    // Verify staging.xcscheme was auto-created and configured
    final stagingSchemeFile = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/staging.xcscheme');
    expect(stagingSchemeFile.existsSync(), isTrue);
    final stagingSchemeContent = stagingSchemeFile.readAsStringSync();
    expect(stagingSchemeContent, contains('.env.staging'));
    expect(stagingSchemeContent, contains('BuildDotenvPlist.rb'));
  });

  test('IosSetup migrates legacy scheme script to latest SPM script', () {
    // Inject old legacy script (only BuildXCConfig, no BuildDotenvPlist) into Runner.xcscheme
    const legacyScheme = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1510" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <PreActions>
         <ExecutionAction ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent title = "Run Script" scriptText = "ruby \${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildXCConfig.rb&#10;">
               <EnvironmentBuildable>
                  <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "97C146ED1CF9000F007C117D" BuildableName = "Runner.app" BlueprintName = "Runner" ReferencedContainer = "container:Runner.xcodeproj"/>
               </EnvironmentBuildable>
            </ActionContent>
         </ExecutionAction>
      </PreActions>
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "97C146ED1CF9000F007C117D" BuildableName = "Runner.app" BlueprintName = "Runner" ReferencedContainer = "container:Runner.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
</Scheme>
''';

    File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').writeAsStringSync(legacyScheme);

    final setup = IosSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);
    expect(result.messages.any((m) => m.contains('Migrated legacy Pre-actions to latest SPM script for scheme: Runner')), isTrue);

    final updatedScheme = File('${tempDir.path}/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme').readAsStringSync();
    expect(updatedScheme, contains('BuildDotenvPlist.rb'));
    expect(updatedScheme, contains('GeneratedDotEnv.plist'));
  });

  test('IosSetup auto-configures BUNDLE_ID, DEVELOPMENT_TEAM in pbxproj and Info.plist', () {
    // Create env file with bundle id, team id, and app name
    Directory('${tempDir.path}/env').createSync();
    File('${tempDir.path}/env/.env.dev').writeAsStringSync('''
BUNDLE_ID=com.example.testapp
APPLE_TEAM_ID=XYZ9876543
APP_NAME=My Test App
''');

    // Create mock Info.plist
    Directory('${tempDir.path}/ios/Runner').createSync(recursive: true);
    File('${tempDir.path}/ios/Runner/Info.plist').writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>\$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleIdentifier</key>
	<string>com.hardcoded.id</string>
</dict>
</plist>
''');

    // Update mock pbxproj with hardcoded bundle id and team id
    final currentPbx = File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final pbxWithSettings = currentPbx.replaceFirst(
      '/* End PBXResourcesBuildPhase section */',
      '''/* End PBXResourcesBuildPhase section */
		97C147031CF9000F007C117D /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				DEVELOPMENT_TEAM = "OLD_TEAM_ID";
				PRODUCT_BUNDLE_IDENTIFIER = "com.old.bundle";
			};
		};''',
    );
    File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').writeAsStringSync(pbxWithSettings);

    final setup = IosSetup(tempDir);
    final result = setup.run();

    expect(result.success, isTrue);

    // Verify pbxproj was updated to variable references
    final updatedPbx = File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(updatedPbx, contains('PRODUCT_BUNDLE_IDENTIFIER = "\${BUNDLE_ID}";'));
    expect(updatedPbx, contains('DEVELOPMENT_TEAM = "\${APPLE_TEAM_ID}";'));

    // Verify Info.plist was updated
    final updatedInfoPlist = File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
    expect(updatedInfoPlist, contains('<key>CFBundleDisplayName</key>'));
    expect(updatedInfoPlist, contains('<string>\$(APP_NAME)</string>'));
    expect(updatedInfoPlist, contains('<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
  });
}
