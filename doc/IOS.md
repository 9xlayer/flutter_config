## iOS Setup Guide

`flutter_config` supports both **Swift Package Manager (SPM)** (default in Flutter 3.44+) and **CocoaPods**.

### Basic Usage with Swift Package Manager (SPM)

Under Swift Package Manager, variables are securely passed into the app bundle at build time using a binary property list (`GeneratedDotEnv.plist`), **without requiring any `.env` files in `pubspec.yaml` `assets:`**. This prevents exposing raw `.env` files or leaking cross-flavor secrets.

1. In the Xcode menu, go to **Product > Scheme > Edit Scheme**.
2. Under **Build > Pre-actions**, add the following run script actions:

   ```bash
   echo ".env" > $(dirname $WORKSPACE_PATH)/.envfile
   ```

   ```bash
   SRCROOT=$(dirname $WORKSPACE_PATH)
   
   # 1. Generate tmp.xcconfig for Info.plist & Build Settings
   SCRIPT_XC="${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildXCConfig.rb"
   if [ ! -f "$SCRIPT_XC" ]; then SCRIPT_XC=$(find "$BUILD_DIR/../../SourcePackages" -name "BuildXCConfig.rb" 2>/dev/null | head -n 1); fi
   if [ ! -f "$SCRIPT_XC" ]; then SCRIPT_XC="${SRCROOT}/../../ios/Classes/BuildXCConfig.rb"; fi
   if [ -f "$SCRIPT_XC" ]; then ruby "$SCRIPT_XC" "${SRCROOT}/" "${SRCROOT}/Flutter/tmp.xcconfig"; fi

   # 2. Generate GeneratedDotEnv.plist for SwiftPM Native & Dart
   SCRIPT_PLIST="${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildDotenvPlist.rb"
   if [ ! -f "$SCRIPT_PLIST" ]; then SCRIPT_PLIST=$(find "$BUILD_DIR/../../SourcePackages" -name "BuildDotenvPlist.rb" 2>/dev/null | head -n 1); fi
   if [ ! -f "$SCRIPT_PLIST" ]; then SCRIPT_PLIST="${SRCROOT}/../../ios/Classes/BuildDotenvPlist.rb"; fi
   if [ -f "$SCRIPT_PLIST" ]; then ruby "$SCRIPT_PLIST" "${SRCROOT}/" "${SRCROOT}/Flutter/GeneratedDotEnv.plist"; fi
   ```

3. Ensure `Flutter/GeneratedDotEnv.plist` is included in **Runner > Build Phases > Copy Bundle Resources** (drag it into Xcode).
4. Make sure you select `Runner` from the `Provide build settings from` dropdown in Pre-actions.

---

### Usage with CocoaPods (Legacy / Existing Projects)

If your iOS project is still using CocoaPods:
- **No additional setup is required** if you only read environment variables from Dart or native Obj-C/Swift code.
- CocoaPods automatically executes the plugin's code generation (`s.script_phase`) during build to compile variables directly into machine code.
- If you also need variables available inside `Info.plist`, see the section below.

---

### Reading Variables in Native Code

**Objective-C:**
```objective-c
// import header
#import "FlutterConfigPlugin.h"

// read individual keys:
NSString *apiUrl = [FlutterConfigPlugin envFor:@"API_URL"];

// or fetch the whole config:
NSDictionary *config = [FlutterConfigPlugin env];
```

**Swift:**
```swift
import flutter_config

let apiUrl = flutter_config.FlutterConfigPlugin.env(for: "API_URL")
let config = flutter_config.FlutterConfigPlugin.env()
```

---

### Availability in Build Settings and Info.plist

To read env variables in your `Info.plist` file:

1. Under `Runner/Flutter`:
   Add the following line to both `Debug.xcconfig` and `Release.xcconfig`:

   ```objective-c
   #include? "tmp.xcconfig"
   ```

   Add this file to `.gitignore`:
   ```text
   **/ios/Flutter/tmp.xcconfig
   **/ios/Flutter/GeneratedDotEnv.plist
   ```

---

### Different Environments (Flavors)

To alternate between different environments (e.g. `.env.staging`, `.env.production`):

1. In Xcode, duplicate the Runner scheme (e.g., "Runner (staging)").
2. In **Build > Pre-actions** for that scheme, change the first script action:
   ```bash
   echo ".env.staging" > $(dirname $WORKSPACE_PATH)/.envfile
   ```
3. That's it! When building that scheme:
   - Only `.env.staging` will be read and bundled as `GeneratedDotEnv.plist`.
   - Production keys or other flavor keys will **never** be included in that build.
