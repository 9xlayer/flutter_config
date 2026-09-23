# Config Variables for your Flutter apps

Plugin that exposes environment variables to your Dart code in Flutter as well as to your native code in iOS and Android.

Inspired by [react-native-config](https://github.com/luggit/react-native-config)

## Basic Usage

Create a new file `.env` in the root of your Flutter app:

```
API_URL=https://myapi.com
FABRIC_ID=abcdefgh
```

load all environment varibles in `main.dart`

```dart
import 'package:flutter_config/flutter_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required by FlutterConfig
  await FlutterConfig.loadEnvVariables();

  runApp(MyApp());
}
```

Now you can access your environment varibles anywhere in your app.

```dart
import 'package:flutter_config/flutter_config.dart';

FlutterConfig.get('FABRIC_ID') // returns 'abcdefgh'
```

Keep in mind this module doesn't obfuscate or encrypt secrets for packaging, so **do not store sensitive keys in `.env`**. It's [basically impossible to prevent users from reverse engineering mobile app secrets](https://rammic.github.io/2015/07/28/hiding-secrets-in-android-apps/), so design your app (and APIs) with that in mind.

<br/>

### Load Environment Varibles in Swift

First import the plugin
```Swift
import flutter_config
```
Then you can use the .env Variable, replace `ENV_API_KEY` with yours.
```Swift
flutter_config.FlutterConfigPlugin.env(for: "ENV_API_KEY")
```


## Getting Started

1. Add `flutter_config` to your `pubspec.yaml` (or run `flutter pub add flutter_config`).
2. Run the automated setup tool from your Flutter project root:

```bash
dart run flutter_config:setup
```

*(You can also target specific platforms: `dart run flutter_config:setup --ios` or `dart run flutter_config:setup --android`)*

This command automatically configures:
- **iOS**: Creates `GeneratedDotEnv.plist` placeholder, registers it in `Runner.xcodeproj` (Copy Bundle Resources), injects `tmp.xcconfig` into `Debug`/`Release.xcconfig`, and configures Pre-actions in Xcode schemes.
- **Android**: Applies `dotenv.gradle` in `android/app/build.gradle` and adds R8 `BuildConfig` keep rules to `proguard-rules.pro`.

For manual setup and advanced configurations:
- [iOS Setup Guide](./doc/IOS.md) (SPM, CocoaPods, Flavors, Info.plist)
- [Android Setup Guide](./doc/ANDROID.md) (Flavors, Gradle, Proguard)

## Testing

Whenever you need to use `FlutterConfig` in your tests, simply use the method `loadValueForTesting`

```dart
import 'package:flutter_config/flutter_config.dart';

void main() {
  FlutterConfig.loadValueForTesting({'BASE_URL': 'https://www.mockurl.com'});
  
  test('mock http client test', () {
    final client = HttpClient(
      baseUrl: FlutterConfig.get('BASE_URL')
    );
  });
}
```
