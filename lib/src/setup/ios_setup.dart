import 'dart:io';
import 'dart:math';
import 'platform_setup.dart';

/// Automates iOS configuration for flutter_config (Swift Package Manager & CocoaPods).
class IosSetup implements PlatformSetup {
  @override
  final Directory projectDir;

  IosSetup(this.projectDir);

  @override
  String get platformName => 'iOS';

  @override
  String get flag => 'ios';

  Directory get iosDir => Directory('${projectDir.path}/ios');

  bool get isIosProject => iosDir.existsSync();

  @override
  bool get isApplicable => isIosProject;

  /// Runs the full iOS setup workflow.
  SetupResult run({bool verbose = false}) {
    final messages = <String>[];
    final warnings = <String>[];

    if (!isIosProject) {
      return SetupResult(
        success: false,
        error: 'Directory ios/ not found. Please run this command from the root of a Flutter project.',
      );
    }

    try {
      // 1. Ensure GeneratedDotEnv.plist placeholder exists
      final plistResult = _ensurePlaceholderPlist();
      messages.add(plistResult);

      // 2. Ensure #include? "tmp.xcconfig" in Debug.xcconfig and Release.xcconfig
      final xcconfigResult = _updateXcconfigs();
      messages.addAll(xcconfigResult);

      // 3. Inject GeneratedDotEnv.plist into Runner.xcodeproj/project.pbxproj
      final pbxResult = _injectPbxproj();
      messages.add(pbxResult);

      // 4. Update PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM in project.pbxproj
      final buildSettingsResults = _updatePbxprojBuildSettings();
      messages.addAll(buildSettingsResults);

      // 5. Ensure Info.plist uses xcconfig variables for display name and bundle ID
      final infoPlistResults = _updateInfoPlist();
      messages.addAll(infoPlistResults);

      // 6. Configure Pre-actions in Xcode schemes
      final schemeResults = _configureSchemes();
      messages.addAll(schemeResults);

      // 7. Update .gitignore
      final gitignoreResult = _updateGitignore();
      if (gitignoreResult != null) {
        messages.add(gitignoreResult);
      }

      return SetupResult(
        success: true,
        messages: messages,
        warnings: warnings,
      );
    } catch (e, stack) {
      return SetupResult(
        success: false,
        error: 'Failed to configure iOS: $e\n$stack',
      );
    }
  }

  /// Step 1: Ensure ios/Flutter/GeneratedDotEnv.plist exists as a valid XML plist placeholder.
  String _ensurePlaceholderPlist() {
    final flutterDir = Directory('${iosDir.path}/Flutter');
    if (!flutterDir.existsSync()) {
      flutterDir.createSync(recursive: true);
    }

    final plistFile = File('${flutterDir.path}/GeneratedDotEnv.plist');
    if (!plistFile.existsSync() || plistFile.lengthSync() == 0) {
      const defaultContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
''';
      plistFile.writeAsStringSync(defaultContent);
      return 'Created placeholder ios/Flutter/GeneratedDotEnv.plist';
    } else {
      return 'ios/Flutter/GeneratedDotEnv.plist already exists';
    }
  }

  /// Step 2: Ensure Debug.xcconfig and Release.xcconfig include tmp.xcconfig
  List<String> _updateXcconfigs() {
    final results = <String>[];
    const includeLine = '#include? "tmp.xcconfig"';

    for (final filename in ['Debug.xcconfig', 'Release.xcconfig']) {
      final file = File('${iosDir.path}/Flutter/$filename');
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (!content.contains('tmp.xcconfig')) {
          file.writeAsStringSync('$content\n$includeLine\n');
          results.add('Added $includeLine to ios/Flutter/$filename');
        } else {
          results.add('ios/Flutter/$filename already includes tmp.xcconfig');
        }
      }
    }

    return results;
  }

  /// Step 3: Inject GeneratedDotEnv.plist into ios/Runner.xcodeproj/project.pbxproj
  String _injectPbxproj() {
    final pbxFile = File('${iosDir.path}/Runner.xcodeproj/project.pbxproj');
    if (!pbxFile.existsSync()) {
      return 'Warning: Runner.xcodeproj/project.pbxproj not found, skipping pbxproj injection';
    }

    String content = pbxFile.readAsStringSync();

    // 1. Locate the Runner native target's Resources build phase ID
    String? runnerResourcesId;
    final runnerTargetMatch = RegExp(
      r'/\*\s*Runner\s*\*/\s*=\s*\{\s*isa\s*=\s*PBXNativeTarget;[\s\S]*?buildPhases\s*=\s*\(([\s\S]*?)\);',
    ).firstMatch(content);

    if (runnerTargetMatch != null) {
      final phases = runnerTargetMatch.group(1)!;
      final phaseMatch = RegExp(r'([0-9A-F]{24})\s*/\*\s*Resources\s*\*/').firstMatch(phases);
      if (phaseMatch != null) {
        runnerResourcesId = phaseMatch.group(1);
      }
    }

    // Fallback: look for PBXResourcesBuildPhase containing AppFrameworkInfo.plist, LaunchScreen, or Main.storyboard
    if (runnerResourcesId == null) {
      final fallbackPhaseMatch = RegExp(
        r'([0-9A-F]{24})\s*/\*\s*Resources\s*\*/\s*=\s*\{\s*isa\s*=\s*PBXResourcesBuildPhase;[\s\S]*?(?:AppFrameworkInfo\.plist|LaunchScreen|Main\.storyboard)[\s\S]*?files\s*=\s*\(',
      ).firstMatch(content);
      if (fallbackPhaseMatch != null) {
        runnerResourcesId = fallbackPhaseMatch.group(1);
      }
    }

    // Locate the Runner Resources build phase block in content
    RegExpMatch? runnerResourcesPhaseMatch;
    if (runnerResourcesId != null) {
      runnerResourcesPhaseMatch = RegExp(
        '($runnerResourcesId\\s*/\\*\\s*Resources\\s*\\*/\\s*=\\s*\\{\\s*isa\\s*=\\s*PBXResourcesBuildPhase;[\\s\\S]*?files\\s*=\\s*\\()([\\s\\S]*?)(\\);)',
      ).firstMatch(content);
    }
    // Fallback: search for Resources phase with standard Flutter assets
    runnerResourcesPhaseMatch ??= RegExp(
      r'([0-9A-F]{24}\s*/\*\s*Resources\s*\*/\s*=\s*\{\s*isa\s*=\s*PBXResourcesBuildPhase;[\s\S]*?(?:AppFrameworkInfo\.plist|LaunchScreen|Main\.storyboard)[\s\S]*?files\s*=\s*\()([\s\S]*?)(\);)',
    ).firstMatch(content);
    // Last resort generic match
    runnerResourcesPhaseMatch ??= RegExp(
      r'(\/\*\s*Resources\s*\*\/ = \{\s*isa = PBXResourcesBuildPhase;[\s\S]*?files = \()([\s\S]*?)(\);)',
    ).firstMatch(content);

    if (runnerResourcesPhaseMatch == null) {
      return 'Warning: Could not locate PBXResourcesBuildPhase in project.pbxproj';
    }

    // Check if the Runner Resources phase already contains GeneratedDotEnv.plist
    final existingFilesInRunner = runnerResourcesPhaseMatch.group(2)!;
    final alreadyInRunner = existingFilesInRunner.contains('GeneratedDotEnv.plist in Resources');

    if (alreadyInRunner && content.contains('GeneratedDotEnv.plist */ = {isa = PBXFileReference')) {
      return 'project.pbxproj already contains GeneratedDotEnv.plist in Runner Resources';
    }

    // Collect existing IDs to avoid collisions
    final idRegex = RegExp(r'\b[0-9A-F]{24}\b');
    final existingIds = idRegex.allMatches(content).map((m) => m.group(0)!).toSet();

    // Check if fileRef or buildFile already exist
    final fileRefMatch = RegExp(r'([0-9A-F]{24})\s*/\*\s*GeneratedDotEnv\.plist\s*\*/\s*=\s*\{isa\s*=\s*PBXFileReference').firstMatch(content);
    final fileRefId = fileRefMatch?.group(1) ?? _generatePbxId('FC02', existingIds);

    final buildFileMatch = RegExp(r'([0-9A-F]{24})\s*/\*\s*GeneratedDotEnv\.plist in Resources\s*\*/\s*=\s*\{isa\s*=\s*PBXBuildFile').firstMatch(content);
    final buildFileId = buildFileMatch?.group(1) ?? _generatePbxId('FC01', existingIds);

    // 1. Add to PBXBuildFile if not present
    if (!content.contains('GeneratedDotEnv.plist in Resources */ = {isa = PBXBuildFile')) {
      const buildFileHeader = '/* Begin PBXBuildFile section */';
      final buildFileIndex = content.indexOf(buildFileHeader);
      if (buildFileIndex != -1) {
        final insertPos = buildFileIndex + buildFileHeader.length;
        final newEntry = '\n\t\t$buildFileId /* GeneratedDotEnv.plist in Resources */ = {isa = PBXBuildFile; fileRef = $fileRefId /* GeneratedDotEnv.plist */; };';
        content = content.substring(0, insertPos) + newEntry + content.substring(insertPos);
      }
    }

    // 2. Add to PBXFileReference if not present
    if (!content.contains('GeneratedDotEnv.plist */ = {isa = PBXFileReference')) {
      const fileRefHeader = '/* Begin PBXFileReference section */';
      final fileRefIndex = content.indexOf(fileRefHeader);
      if (fileRefIndex != -1) {
        final insertPos = fileRefIndex + fileRefHeader.length;
        final newEntry = '\n\t\t$fileRefId /* GeneratedDotEnv.plist */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.plist.xml; name = GeneratedDotEnv.plist; path = Flutter/GeneratedDotEnv.plist; sourceTree = "<group>"; };';
        content = content.substring(0, insertPos) + newEntry + content.substring(insertPos);
      }
    }

    // 3. Add fileRef to PBXGroup (Flutter group preferred) if not present
    if (!content.contains('$fileRefId /* GeneratedDotEnv.plist */,')) {
      final flutterGroupMatch = RegExp(r'(\/\*\s*Flutter\s*\*\/ = \{\s*isa = PBXGroup;\s*children = \()([\s\S]*?)(\);)')
          .firstMatch(content);

      if (flutterGroupMatch != null) {
        final prefix = flutterGroupMatch.group(1)!;
        final existingChildren = flutterGroupMatch.group(2)!;
        final suffix = flutterGroupMatch.group(3)!;
        final newChildren = '\n\t\t\t\t$fileRefId /* GeneratedDotEnv.plist */,$existingChildren';
        content = content.replaceFirst(flutterGroupMatch.group(0)!, '$prefix$newChildren$suffix');
      } else {
        final genericGroupMatch = RegExp(r'(children = \(\s*(?:[^\)]*?Debug\.xcconfig[^\)]*?)\);)').firstMatch(content);
        if (genericGroupMatch != null) {
          final original = genericGroupMatch.group(0)!;
          final updated = original.replaceFirst('children = (', 'children = (\n\t\t\t\t$fileRefId /* GeneratedDotEnv.plist */,');
          content = content.replaceFirst(original, updated);
        }
      }
    }

    // 4. Remove GeneratedDotEnv.plist from any wrong resources build phase (e.g. RunnerTests)
    if (!alreadyInRunner && content.contains('GeneratedDotEnv.plist in Resources')) {
      final wrongPhaseEntry = RegExp(r'\n?\t+[0-9A-F]{24}\s*/\*\s*GeneratedDotEnv\.plist in Resources\s*\*/,');
      content = content.replaceFirst(wrongPhaseEntry, '');
    }

    // 5. Add buildFile to the Runner target PBXResourcesBuildPhase
    if (!alreadyInRunner) {
      if (runnerResourcesId != null) {
        runnerResourcesPhaseMatch = RegExp(
          '($runnerResourcesId\\s*/\\*\\s*Resources\\s*\\*/\\s*=\\s*\\{\\s*isa\\s*=\\s*PBXResourcesBuildPhase;[\\s\\S]*?files\\s*=\\s*\\()([\\s\\S]*?)(\\);)',
        ).firstMatch(content);
      }
      runnerResourcesPhaseMatch ??= RegExp(
        r'([0-9A-F]{24}\s*/\*\s*Resources\s*\*/\s*=\s*\{\s*isa\s*=\s*PBXResourcesBuildPhase;[\s\S]*?(?:AppFrameworkInfo\.plist|LaunchScreen|Main\.storyboard)[\s\S]*?files\s*=\s*\()([\s\S]*?)(\);)',
      ).firstMatch(content);
      runnerResourcesPhaseMatch ??= RegExp(
        r'(\/\*\s*Resources\s*\*\/ = \{\s*isa = PBXResourcesBuildPhase;[\s\S]*?files = \()([\s\S]*?)(\);)',
      ).firstMatch(content);

      if (runnerResourcesPhaseMatch != null) {
        final prefix = runnerResourcesPhaseMatch.group(1)!;
        final existingFiles = runnerResourcesPhaseMatch.group(2)!;
        final suffix = runnerResourcesPhaseMatch.group(3)!;
        final newFiles = '\n\t\t\t\t$buildFileId /* GeneratedDotEnv.plist in Resources */,$existingFiles';
        content = content.replaceFirst(runnerResourcesPhaseMatch.group(0)!, '$prefix$newFiles$suffix');
      }
    }

    pbxFile.writeAsStringSync(content);
    return 'Added GeneratedDotEnv.plist to Runner target Resources in project.pbxproj';
  }

  /// Step 4: Configure Pre-actions for Xcode schemes
  List<String> _configureSchemes() {
    final results = <String>[];
    final schemesDir = Directory('${iosDir.path}/Runner.xcodeproj/xcshareddata/xcschemes');

    if (!schemesDir.existsSync()) {
      schemesDir.createSync(recursive: true);
    }

    var schemeFiles = schemesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.xcscheme')).toList();

    // If no shared schemes exist, check user schemes
    if (schemeFiles.isEmpty) {
      final userDataDir = Directory('${iosDir.path}/Runner.xcodeproj/xcuserdata');
      if (userDataDir.existsSync()) {
        final userSchemes = userDataDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.xcscheme'))
            .toList();

        for (final userScheme in userSchemes) {
          final targetFile = File('${schemesDir.path}/${userScheme.uri.pathSegments.last}');
          userScheme.copySync(targetFile.path);
          results.add('Copied user scheme ${userScheme.uri.pathSegments.last} to xcshareddata/xcschemes');
        }
      }
      schemeFiles = schemesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.xcscheme')).toList();
    }

    // If still no scheme file, create standard Runner.xcscheme
    if (schemeFiles.isEmpty) {
      final defaultScheme = File('${schemesDir.path}/Runner.xcscheme');
      defaultScheme.writeAsStringSync(_createDefaultRunnerScheme());
      schemeFiles.add(defaultScheme);
      results.add('Created default Runner.xcscheme in xcshareddata/xcschemes');
    }

    // Scan for .env.* files in projectDir (root + env/ subdir) to auto-generate missing flavor schemes
    final envFiles = [
      ...projectDir.listSync().whereType<File>(),
      if (Directory('${projectDir.path}/env').existsSync())
        ...Directory('${projectDir.path}/env').listSync().whereType<File>(),
    ].where((f) {
      final name = f.uri.pathSegments.last;
      return name.startsWith('.env.') &&
          !name.endsWith('.example') &&
          !name.endsWith('.sample') &&
          !name.endsWith('.bak');
    }).toList();

    // De-duplicate by flavor suffix (root takes priority over env/ subdir)
    final seenFlavors = <String>{};
    final uniqueEnvFiles = envFiles.where((f) {
      final flavor = f.uri.pathSegments.last.substring(5); // strip '.env.'
      return seenFlavors.add(flavor.toLowerCase());
    }).toList();

    for (final envFile in uniqueEnvFiles) {
      final envFileName = envFile.uri.pathSegments.last;
      final flavor = envFileName.substring(5); // e.g. "dev", "staging", "prod"

      // Check if a scheme matching this flavor already exists (case-insensitive)
      final existingScheme = schemeFiles.any((f) {
        final name = f.uri.pathSegments.last.replaceAll('.xcscheme', '').toLowerCase();
        return name == flavor.toLowerCase();
      });

      if (!existingScheme) {
        final runnerSchemeFile = File('${schemesDir.path}/Runner.xcscheme');
        final templateContent = runnerSchemeFile.existsSync()
            ? runnerSchemeFile.readAsStringSync()
            : _createDefaultRunnerScheme();

        // Strip existing PreActions from template so we start clean
        final cleanContent = templateContent.replaceAll(
          RegExp(r'\s*<PreActions>[\s\S]*?<\/PreActions>'),
          '',
        );

        final newSchemeFile = File('${schemesDir.path}/$flavor.xcscheme');
        newSchemeFile.writeAsStringSync(cleanContent);
        schemeFiles.add(newSchemeFile);
        results.add('Auto-created Xcode scheme "$flavor.xcscheme" for $envFileName');
      }
    }

    for (final schemeFile in schemeFiles) {
      final schemeName = schemeFile.uri.pathSegments.last.replaceAll('.xcscheme', '');
      final status = _injectPreActionIntoScheme(schemeFile, schemeName);
      if (status == 'configured') {
        results.add('Configured Pre-actions for scheme: $schemeName');
      } else if (status == 'migrated') {
        results.add('Migrated legacy Pre-actions to latest SPM script for scheme: $schemeName');
      } else {
        results.add('Scheme $schemeName already has latest Pre-actions configured');
      }
    }

    return results;
  }

  /// Injects or migrates PreActions in a specific .xcscheme file.
  /// Returns 'configured' (fresh), 'migrated' (updated old script), or 'alreadyConfigured' (up-to-date).
  String _injectPreActionIntoScheme(File schemeFile, String schemeName) {
    String content = schemeFile.readAsStringSync();

    // Detect target env file for this scheme dynamically.
    // Scans actual env files in the project root and 'env/' subdirectory,
    // then picks the best match based on the scheme name.
    String envTarget = '.env';
    final lowerName = schemeName.toLowerCase();

    // Collect all .env.* files from root and env/ subdir with their relative paths
    final candidates = <String, String>{}; // suffix → relative path
    for (final searchDir in [
      projectDir,
      Directory('${projectDir.path}/env'),
    ]) {
      if (!searchDir.existsSync()) continue;
      for (final entity in searchDir.listSync().whereType<File>()) {
        final name = entity.uri.pathSegments.last;
        // Match .env.xxx or .env (plain)
        final match = RegExp(r'^\.env(\.[\w-]+)?$').firstMatch(name);
        if (match == null) continue;
        final suffix = (match.group(1) ?? '').replaceFirst('.', ''); // e.g. 'dev', 'prd', ''
        final relative = searchDir.path == projectDir.path
            ? name
            : 'env/$name';
        candidates[suffix] = relative;
      }
    }

    // Priority: exact match on suffix, then partial/fuzzy match
    if (lowerName == 'runner') {
      // Runner scheme uses the dev env as default
      envTarget = candidates['dev'] ?? candidates['development'] ?? candidates[''] ?? '.env';
    } else if (candidates.containsKey(lowerName)) {
      // Exact match: scheme 'dev' → suffix 'dev'
      envTarget = candidates[lowerName]!;
    } else {
      // Fuzzy: find a suffix that is a substring of the scheme name or vice versa
      final fuzzy = candidates.entries.where((e) =>
          e.key.isNotEmpty &&
          (lowerName.contains(e.key) || e.key.contains(lowerName)),
      );
      if (fuzzy.isNotEmpty) {
        // Prefer the longest (most specific) match
        envTarget = fuzzy.reduce((a, b) => a.key.length >= b.key.length ? a : b).value;
      } else {
        envTarget = candidates[''] ?? '.env'; // fall back to plain .env
      }
    }

    // Extract BuildableReference from existing scheme if available
    final buildableRefMatch = RegExp(r'(<BuildableReference[\s\S]*?BlueprintIdentifier = "([A-F0-9]+)"[\s\S]*?BlueprintName = "Runner"[\s\S]*?<\/BuildableReference>)')
        .firstMatch(content);

    final blueprintId = buildableRefMatch != null ? buildableRefMatch.group(2)! : '97C146ED1CF9000F007C117D';

    final preActionXml = '''         <ExecutionAction
            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent
               title = "Run Script"
               scriptText = "echo &quot;$envTarget&quot; &gt; \$(dirname \$WORKSPACE_PATH)/.envfile&#10;">
               <EnvironmentBuildable>
                  <BuildableReference
                     BuildableIdentifier = "primary"
                     BlueprintIdentifier = "$blueprintId"
                     BuildableName = "Runner.app"
                     BlueprintName = "Runner"
                     ReferencedContainer = "container:Runner.xcodeproj">
                  </BuildableReference>
               </EnvironmentBuildable>
            </ActionContent>
         </ExecutionAction>
         <ExecutionAction
            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent
               title = "Run Script"
               scriptText = "SRCROOT=\$(dirname \$WORKSPACE_PATH)&#10;if [ -z &quot;\$SRCROOT&quot; ] || [ &quot;\$SRCROOT&quot; = &quot;.&quot; ]; then SRCROOT=&quot;\${PROJECT_DIR}&quot;; fi&#10;&#10;# 1. Generate tmp.xcconfig for Info.plist &amp; Build Settings&#10;SCRIPT_XC=&quot;\${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildXCConfig.rb&quot;&#10;if [ ! -f &quot;\$SCRIPT_XC&quot; ]; then SCRIPT_XC=&quot;\${SRCROOT}/Flutter/ephemeral/Packages/.packages/flutter_config/Sources/flutter_config/BuildXCConfig.rb&quot;; fi&#10;if [ ! -f &quot;\$SCRIPT_XC&quot; ]; then SCRIPT_XC=\$(find &quot;\$BUILD_DIR/../../SourcePackages&quot; -name &quot;BuildXCConfig.rb&quot; 2&gt;/dev/null | head -n 1); fi&#10;if [ ! -f &quot;\$SCRIPT_XC&quot; ]; then SCRIPT_XC=&quot;\${SRCROOT}/../../ios/Classes/BuildXCConfig.rb&quot;; fi&#10;if [ -f &quot;\$SCRIPT_XC&quot; ]; then ruby &quot;\$SCRIPT_XC&quot; &quot;\${SRCROOT}/&quot; &quot;\${SRCROOT}/Flutter/tmp.xcconfig&quot;; fi&#10;&#10;# 2. Generate GeneratedDotEnv.plist for SwiftPM Native &amp; Dart&#10;SCRIPT_PLIST=&quot;\${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildDotenvPlist.rb&quot;&#10;if [ ! -f &quot;\$SCRIPT_PLIST&quot; ]; then SCRIPT_PLIST=&quot;\${SRCROOT}/Flutter/ephemeral/Packages/.packages/flutter_config/Sources/flutter_config/BuildDotenvPlist.rb&quot;; fi&#10;if [ ! -f &quot;\$SCRIPT_PLIST&quot; ]; then SCRIPT_PLIST=\$(find &quot;\$BUILD_DIR/../../SourcePackages&quot; -name &quot;BuildDotenvPlist.rb&quot; 2&gt;/dev/null | head -n 1); fi&#10;if [ ! -f &quot;\$SCRIPT_PLIST&quot; ]; then SCRIPT_PLIST=&quot;\${SRCROOT}/../../ios/Classes/BuildDotenvPlist.rb&quot;; fi&#10;if [ -f &quot;\$SCRIPT_PLIST&quot; ]; then ruby &quot;\$SCRIPT_PLIST&quot; &quot;\${SRCROOT}/&quot; &quot;\${SRCROOT}/Flutter/GeneratedDotEnv.plist&quot;; fi&#10;">
               <EnvironmentBuildable>
                  <BuildableReference
                     BuildableIdentifier = "primary"
                     BlueprintIdentifier = "$blueprintId"
                     BuildableName = "Runner.app"
                     BlueprintName = "Runner"
                     ReferencedContainer = "container:Runner.xcodeproj">
                  </BuildableReference>
               </EnvironmentBuildable>
            </ActionContent>
         </ExecutionAction>''';

    // Check if flutter_config actions already exist in this scheme
    final actionRegex = RegExp(r'<ExecutionAction\b[\s\S]*?<\/ExecutionAction>');
    final existingActions = actionRegex.allMatches(content).toList();

    final flutterConfigActions = existingActions.where((m) {
      final text = m.group(0)!;
      return text.contains('BuildXCConfig') || text.contains('BuildDotenvPlist') || text.contains('.envfile');
    }).toList();

    if (flutterConfigActions.isNotEmpty) {
      // Check if it already has the latest SPM-compatible script with BuildDotenvPlist and correct envTarget
      final allText = flutterConfigActions.map((m) => m.group(0)!).join();
      final isUpToDate = allText.contains('BuildDotenvPlist.rb') &&
          allText.contains('ephemeral') &&
          allText.contains('echo &quot;$envTarget&quot;');

      if (isUpToDate) {
        return 'alreadyConfigured';
      }

      // Migrate: remove old flutter_config actions and replace with latest
      for (final action in flutterConfigActions) {
        content = content.replaceFirst(action.group(0)!, '');
      }

      if (content.contains('<PreActions>')) {
        content = content.replaceFirst('</PreActions>', '$preActionXml\n      </PreActions>');
      } else {
        content = content.replaceFirst('<BuildActionEntries>', '<PreActions>\n$preActionXml\n      </PreActions>\n      <BuildActionEntries>');
      }

      schemeFile.writeAsStringSync(content);
      return 'migrated';
    }

    if (content.contains('<PreActions>')) {
      content = content.replaceFirst('</PreActions>', '$preActionXml\n      </PreActions>');
    } else if (content.contains('<BuildActionEntries>')) {
      content = content.replaceFirst('<BuildActionEntries>', '<PreActions>\n$preActionXml\n      </PreActions>\n      <BuildActionEntries>');
    } else {
      // Find <BuildAction ...>
      final buildActionMatch = RegExp(r'(<BuildAction[^>]*>)').firstMatch(content);
      if (buildActionMatch != null) {
        final buildActionTag = buildActionMatch.group(0)!;
        content = content.replaceFirst(buildActionTag, '$buildActionTag\n      <PreActions>\n$preActionXml\n      </PreActions>');
      }
    }

    schemeFile.writeAsStringSync(content);
    return 'configured';
  }

  /// Step 4: Update PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM in project.pbxproj
  /// to use xcconfig variable references instead of hardcoded values.
  /// Idempotent: skips any entry that already uses a ${VAR} reference.
  List<String> _updatePbxprojBuildSettings() {
    final results = <String>[];
    final pbxFile = File('${iosDir.path}/Runner.xcodeproj/project.pbxproj');
    if (!pbxFile.existsSync()) return results;

    // Detect which env keys are actually present in env files
    final envKeys = _scanEnvKeys();
    final bundleIdKey = _findKey(envKeys, ['BUNDLE_ID', 'APP_BUNDLE_ID', 'BUNDLE_IDENTIFIER']);
    final teamIdKey = _findKey(envKeys, ['APPLE_TEAM_ID', 'TEAM_ID', 'DEVELOPMENT_TEAM_ID']);

    if (bundleIdKey == null && teamIdKey == null) {
      results.add('No BUNDLE_ID or APPLE_TEAM_ID found in env files — skipping pbxproj build settings update');
      return results;
    }

    String content = pbxFile.readAsStringSync();
    bool modified = false;

    // Replace PRODUCT_BUNDLE_IDENTIFIER for Runner target (not RunnerTests)
    if (bundleIdKey != null) {
      // Match entries that are NOT already using a variable (no ${ or $( prefix)
      final bundlePattern = RegExp(
        r'(PRODUCT_BUNDLE_IDENTIFIER = )"([^"$][^"]*)"(;)',
      );
      final updated = content.replaceAllMapped(bundlePattern, (m) {
        final value = m.group(2)!;
        // Skip RunnerTests entries (they use a suffix pattern we preserve)
        if (value.contains('RunnerTests')) return m.group(0)!;
        return '${m.group(1)}"\${$bundleIdKey}"${m.group(3)}';
      });
      if (updated != content) {
        content = updated;
        modified = true;
        results.add('Updated PRODUCT_BUNDLE_IDENTIFIER to "\${$bundleIdKey}" in project.pbxproj');
      } else {
        results.add('PRODUCT_BUNDLE_IDENTIFIER already uses a variable — skipped');
      }
    }

    // Replace DEVELOPMENT_TEAM (non-conditional, non-sdk-specific entries)
    if (teamIdKey != null) {
      // Only replace bare DEVELOPMENT_TEAM = "..."; (not the [sdk=iphoneos*] conditional)
      final teamPattern = RegExp(
        r'(\t+DEVELOPMENT_TEAM = )"([^"]*)"(;)',
      );
      final updated = content.replaceAllMapped(teamPattern, (m) {
        final value = m.group(2)!;
        // Skip if already a variable
        if (value.startsWith(r'${') || value.startsWith(r'$(')) return m.group(0)!;
        return '${m.group(1)}"\${$teamIdKey}"${m.group(3)}';
      });
      if (updated != content) {
        content = updated;
        modified = true;
        results.add('Updated DEVELOPMENT_TEAM to "\${$teamIdKey}" in project.pbxproj');
      } else {
        results.add('DEVELOPMENT_TEAM already uses a variable — skipped');
      }
    }

    if (modified) pbxFile.writeAsStringSync(content);
    return results;
  }

  /// Step 5: Ensure Info.plist uses xcconfig variable references for
  /// CFBundleDisplayName and CFBundleIdentifier.
  List<String> _updateInfoPlist() {
    final results = <String>[];
    final infoPlist = File('${iosDir.path}/Runner/Info.plist');
    if (!infoPlist.existsSync()) return results;

    final envKeys = _scanEnvKeys();
    final appNameKey = _findKey(envKeys, ['APP_NAME', 'APP_DISPLAY_NAME', 'APPLICATION_NAME']);

    String content = infoPlist.readAsStringSync();
    bool modified = false;

    // Ensure CFBundleDisplayName exists and uses the app name key
    if (appNameKey != null) {
      if (!content.contains('CFBundleDisplayName')) {
        // Insert after CFBundleDevelopmentRegion or after <dict>
        final insertAfter = content.contains('CFBundleDevelopmentRegion')
            ? RegExp(r'(<key>CFBundleDevelopmentRegion<\/key>\s*<string>[^<]*<\/string>)')
            : RegExp(r'(<dict>)');
        final match = insertAfter.firstMatch(content);
        if (match != null) {
          final insertion =
              '\n\t\t<key>CFBundleDisplayName</key>\n\t\t<string>\$($appNameKey)</string>';
          content = content.replaceFirst(match.group(0)!, '${match.group(0)!}$insertion');
          modified = true;
          results.add('Added CFBundleDisplayName = \$($appNameKey) to Info.plist');
        }
      } else if (!content.contains('CFBundleDisplayName</key>\n\t\t<string>\$(')) {
        // Update existing CFBundleDisplayName if it's hardcoded
        final displayNamePattern = RegExp(
          r'(<key>CFBundleDisplayName<\/key>\s*<string>)([^$<][^<]*?)(<\/string>)',
        );
        final updated = content.replaceFirstMapped(displayNamePattern, (m) {
          return '${m.group(1)}\$($appNameKey)${m.group(3)}';
        });
        if (updated != content) {
          content = updated;
          modified = true;
          results.add('Updated CFBundleDisplayName to \$($appNameKey) in Info.plist');
        } else {
          results.add('CFBundleDisplayName already uses a variable — skipped');
        }
      } else {
        results.add('CFBundleDisplayName already configured in Info.plist');
      }
    }

    // Ensure CFBundleIdentifier uses PRODUCT_BUNDLE_IDENTIFIER (standard Flutter pattern)
    if (!content.contains('PRODUCT_BUNDLE_IDENTIFIER')) {
      final idPattern = RegExp(
        r'(<key>CFBundleIdentifier<\/key>\s*<string>)([^<]*)(<\/string>)',
      );
      final updated = content.replaceFirstMapped(idPattern, (m) {
        final val = m.group(2)!;
        if (val.startsWith(r'$(')) return m.group(0)!; // already a variable
        return '${m.group(1)}\$(PRODUCT_BUNDLE_IDENTIFIER)${m.group(3)}';
      });
      if (updated != content) {
        content = updated;
        modified = true;
        results.add('Updated CFBundleIdentifier to \$(PRODUCT_BUNDLE_IDENTIFIER) in Info.plist');
      }
    } else {
      results.add('CFBundleIdentifier already uses PRODUCT_BUNDLE_IDENTIFIER');
    }

    if (modified) infoPlist.writeAsStringSync(content);
    return results;
  }

  /// Scans all .env.* files in project root and env/ subdirectory,
  /// returns the union of all key names defined across all files.
  Set<String> _scanEnvKeys() {
    final keys = <String>{};
    final envPattern = RegExp(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=', multiLine: true);
    for (final dir in [projectDir, Directory('${projectDir.path}/env')]) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.startsWith('.env') || name.endsWith('.example') || name.endsWith('.sample')) {
          continue;
        }
        try {
          final raw = file.readAsStringSync();
          for (final m in envPattern.allMatches(raw)) {
            keys.add(m.group(1)!);
          }
        } catch (_) {}
      }
    }
    return keys;
  }

  /// Returns the first key from [candidates] that exists in [envKeys], or null.
  String? _findKey(Set<String> envKeys, List<String> candidates) {
    for (final k in candidates) {
      if (envKeys.contains(k)) return k;
    }
    return null;
  }

  /// Step 5 (gitignore): Update .gitignore
  String? _updateGitignore() {
    final gitignoreFile = File('${projectDir.path}/.gitignore');
    if (gitignoreFile.existsSync()) {
      final content = gitignoreFile.readAsStringSync();
      const ignoreLine = '**/ios/Flutter/tmp.xcconfig';
      if (!content.contains('tmp.xcconfig')) {
        gitignoreFile.writeAsStringSync('$content\n$ignoreLine\n');
        return 'Added $ignoreLine to .gitignore';
      }
    }
    return null;
  }

  /// Generates a 24-char hex Xcode object ID with given prefix.
  String _generatePbxId(String prefix, Set<String> existingIds) {
    final random = Random();
    const hexChars = '0123456789ABCDEF';
    while (true) {
      final suffixLength = 24 - prefix.length;
      final sb = StringBuffer(prefix);
      for (int i = 0; i < suffixLength; i++) {
        sb.write(hexChars[random.nextInt(hexChars.length)]);
      }
      final id = sb.toString();
      if (!existingIds.contains(id)) {
        existingIds.add(id);
        return id;
      }
    }
  }

  /// Default Runner.xcscheme template when no schemes exist.
  String _createDefaultRunnerScheme() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
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
  }
}
