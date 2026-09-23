## iOS Setup Guide

`flutter_config` supports both **Swift Package Manager (SPM)** (default in Flutter 3.44+) and **CocoaPods**.

### Basic Usage with Swift Package Manager (SPM)

Under Swift Package Manager, variables are securely passed into the app bundle at build time using a binary property list (`GeneratedDotEnv.plist`), **without requiring any `.env` files in `pubspec.yaml` `assets:`**. This prevents exposing raw `.env` files or leaking cross-flavor secrets.

1. In the Xcode menu, go to **Product > Scheme > Edit Scheme...**.

   ![Product > Scheme > Edit Scheme](./pic2.png)

2. Under **Build > Pre-actions**, click the **+** button at the bottom and select **New Run Script Action** (do this twice to create 2 Run Script blocks).

   ![New Run Script Action in Pre-actions](./pic3.png)

3. In each **Run Script** box, you will see:
   - **Shell**: Leave as `/bin/sh`.
   - **Provide build settings from**: Select `Runner` (or keep `None`).
   - **Text editor area (the large dark box with line numbers `1, 2...`)**: **Paste the script code here.**

   ---

   **First Run Script Box (Action 1 - Specify .env file):**
   Paste into the code editor of the first block:
   ```bash
   echo ".env" > $(dirname $WORKSPACE_PATH)/.envfile
   ```

   **Second Run Script Box (Action 2 - Generate tmp.xcconfig & GeneratedDotEnv.plist):**
   Paste into the code editor of the second block:
   ```bash
   SRCROOT=$(dirname $WORKSPACE_PATH)
   
   # 1. Generate tmp.xcconfig for Info.plist & Build Settings
   SCRIPT_XC="${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildXCConfig.rb"
   if [ ! -f "$SCRIPT_XC" ]; then SCRIPT_XC="${SRCROOT}/Flutter/ephemeral/Packages/.packages/flutter_config/Sources/flutter_config/BuildXCConfig.rb"; fi
   if [ ! -f "$SCRIPT_XC" ]; then SCRIPT_XC=$(find "$BUILD_DIR/../../SourcePackages" -name "BuildXCConfig.rb" 2>/dev/null | head -n 1); fi
   if [ ! -f "$SCRIPT_XC" ]; then SCRIPT_XC="${SRCROOT}/../../ios/Classes/BuildXCConfig.rb"; fi
   if [ -f "$SCRIPT_XC" ]; then ruby "$SCRIPT_XC" "${SRCROOT}/" "${SRCROOT}/Flutter/tmp.xcconfig"; fi

   # 2. Generate GeneratedDotEnv.plist for SwiftPM Native & Dart
   SCRIPT_PLIST="${SRCROOT}/.symlinks/plugins/flutter_config/ios/Classes/BuildDotenvPlist.rb"
   if [ ! -f "$SCRIPT_PLIST" ]; then SCRIPT_PLIST="${SRCROOT}/Flutter/ephemeral/Packages/.packages/flutter_config/Sources/flutter_config/BuildDotenvPlist.rb"; fi
   if [ ! -f "$SCRIPT_PLIST" ]; then SCRIPT_PLIST=$(find "$BUILD_DIR/../../SourcePackages" -name "BuildDotenvPlist.rb" 2>/dev/null | head -n 1); fi
   if [ ! -f "$SCRIPT_PLIST" ]; then SCRIPT_PLIST="${SRCROOT}/../../ios/Classes/BuildDotenvPlist.rb"; fi
   if [ -f "$SCRIPT_PLIST" ]; then ruby "$SCRIPT_PLIST" "${SRCROOT}/" "${SRCROOT}/Flutter/GeneratedDotEnv.plist"; fi
   ```

   > **Tip:** You can also combine both scripts into a single Run Script block if you prefer.

   After pasting, your **Pre-actions** panel will look exactly like this:

   ![Pre-actions Run Script Setup](./pic5.png)

4. Ensure `Flutter/GeneratedDotEnv.plist` is included in **Runner > Build Phases > Copy Bundle Resources** (drag it into Xcode).
5. Make sure you select `Runner` from the `Provide build settings from` dropdown in Pre-actions (or leave as `None` if using `$WORKSPACE_PATH`).

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

1. Under `Runner/Flutter` in Xcode's project navigator:
   Add the following line to both `Debug.xcconfig` and `Release.xcconfig`:

   ```objective-c
   #include? "tmp.xcconfig"
   ```

   ![Xcode Project Navigator - Debug and Release xcconfig](./pic1.png)

   Add this file to `.gitignore`:
   ```text
   **/ios/Flutter/tmp.xcconfig
   **/ios/Flutter/GeneratedDotEnv.plist
   ```

---

### Different Environments (Flavors)

To alternate between different environments (e.g. `.env.staging`, `.env.production`):

1. In Xcode, duplicate the Runner scheme (e.g., "staging" or "production").
2. In **Build > Pre-actions** for that scheme, change the first script action:
   ```bash
   echo ".env.staging" > $(dirname $WORKSPACE_PATH)/.envfile
   ```

   ![Flavors Pre-actions Setup](./pic4.png)

3. That's it! When building that scheme:
   - Only `.env.staging` will be read and bundled as `GeneratedDotEnv.plist`.
   - Production keys or other flavor keys will **never** be included in that build.
