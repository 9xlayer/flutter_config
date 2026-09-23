## Android Setup Guide

### Automated Setup (Recommended)

You can automatically configure your Android project with a single command from your Flutter project root:

```bash
dart run flutter_config:setup --android
```

*(You can also use `dart run flutter_config:setup android` or `dart run flutter_config:setup` to configure both iOS and Android)*

#### What the automated CLI does:
1. **Auto-detects Flavors & Maps `envConfigFiles`**:
   - Scans project root and `env/` directory for `.env.*` files (e.g., `.env.dev`, `.env.staging`, `.env.prd`).
   - Automatically generates the `envConfigFiles` mapping (`project.ext.envConfigFiles = [...]` in Groovy or `project.extra["envConfigFiles"] = mapOf(...)` in Kotlin DSL).
2. **Applies `dotenv.gradle`**:
   - Automatically adds `dotenv.gradle` right before the `android { ... }` block in `build.gradle` or `build.gradle.kts`.
3. **Enables `buildConfig = true` (AGP 8.0+ Compatibility)**:
   - Android Gradle Plugin 8+ disables `BuildConfig` generation by default. The CLI automatically adds `buildFeatures.buildConfig = true` inside `android { ... }`.
4. **Configures `build_config_package`**:
   - Detects the app's `namespace` and adds `resValue "string", "build_config_package", "$namespace"` to `defaultConfig` so `FlutterConfig` can find `BuildConfig` even when flavors use custom `applicationId`s.
5. **R8 / Proguard**:
   - Automatically creates or updates `android/app/proguard-rules.pro` with `-keep class **.BuildConfig { *; }` to prevent env variables from being stripped or obfuscated during release builds.

---

### Manual Setup (Alternative)

If you prefer to configure Android manually instead of using `dart run flutter_config:setup --android`:

#### 1. In `android/app/build.gradle.kts` (Kotlin DSL) or `build.gradle` (Groovy):

**Kotlin DSL (`build.gradle.kts`):**
```kotlin
// If using flavors:
project.extra["envConfigFiles"] = mapOf(
    "dev" to "env/.env.dev",
    "staging" to "env/.env.staging",
    "prd" to "env/.env.prd"
)

apply(from = "${project(":flutter_config").projectDir}/dotenv.gradle")

android {
    namespace = "com.yourcompany.app"
    buildFeatures.buildConfig = true // Required for AGP 8.0+

    defaultConfig {
        ...
        resValue("string", "build_config_package", "com.yourcompany.app")
    }
}
```

**Groovy DSL (`build.gradle`):**
```groovy
// If using flavors:
project.ext.envConfigFiles = [
    dev: "env/.env.dev",
    staging: "env/.env.staging",
    prd: "env/.env.prd",
]

apply from: project(':flutter_config').projectDir.getPath() + "/dotenv.gradle"

android {
    namespace "com.yourcompany.app"
    buildFeatures {
        buildConfig true // Required for AGP 8.0+
    }

    defaultConfig {
        ...
        resValue "string", "build_config_package", "com.yourcompany.app"
    }
}
```

#### 2. Proguard / R8 Configuration
In `android/app/proguard-rules.pro`, add:
```proguard
-keep class **.BuildConfig { *; }
```

---

## Usage in Java/Kotlin Code

Config variables set in `.env` are available to your Java or Kotlin classes via `BuildConfig`:

```kotlin
fun getApiClient(): HttpURLConnection {
    val url = URL(BuildConfig.API_URL)
    // ...
}
```

## Usage in Gradle

You can read environment variables in your Gradle configuration:

```groovy
defaultConfig {
    applicationId project.env.get("APP_ID")
}
```

## Usage in AndroidManifest.xml

You can use env variables to configure libraries in `AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="@string/GOOGLE_MAPS_API_KEY" />
```

## Kotlin Compatibility (Flutter 3.47+ & Legacy KGP)

`flutter_config` defaults to **Built-in Kotlin** (`android.builtInKotlin=true`) to be ready for **Flutter 3.47+** and **Android Gradle Plugin 9.0+**.

- **Modern Flutter (3.47+ / AGP 9.0+)**: No extra configuration needed. Built-in Kotlin is active by default.
- **Legacy Flutter Projects (using KGP / AGP < 9.0)**: Ensure your `android/gradle.properties` contains:
  ```properties
  android.builtInKotlin=false
  ```
  `flutter_config` will automatically detect this flag and fall back to the legacy `kotlin-android` plugin.

