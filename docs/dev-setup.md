# Development setup

## Toolchain

- Flutter 3.38.9 (Dart 3.10.8), native assets enabled
- Android SDK 36, build-tools 36.1.0, platform android-36
- NDK **28.2.13676358** (installed at `%LOCALAPPDATA%\Android\Sdk\ndk`)
- JDK 17+ (Android Studio JBR 21 works)
- CMake 3.22.1 (only needed if MeCab native assets are replaced by a CMake module)

## Project location

The checkout lives at `C:\Projects\Rikai-Mobile` (ASCII path). A previous copy
under a CJK path required an `android.overridePathCheck=true` / `subst` drive
workaround; that is no longer needed and has been removed.

## Build

```powershell
cd C:\Projects\Rikai-Mobile
flutter pub get
flutter build apk --debug
```

## Gradle cache recovery

If Gradle reports `Could not read workspace metadata ... metadata.bin` or a
missing transform workspace:

```powershell
cd android
.\gradlew --stop
```

Then move the affected script/transform cache folders aside (they are
regenerated; `modules-2` is left untouched because it contains downloaded
dependencies):

```powershell
$c = "$env:USERPROFILE\.gradle\caches\8.14"
Move-Item "$c\kotlin-dsl" "$c\kotlin-dsl.bak"
Move-Item "$c\groovy-dsl" "$c\groovy-dsl.bak"
Move-Item "$c\transforms" "$c\transforms.bak"
Move-Item "$c\generated-gradle-jars" "$c\generated-gradle-jars.bak"
Move-Item "$c\dependencies-accessors" "$c\dependencies-accessors.bak"
```

This cache corruption was observed on this machine after interrupted builds;
clearing the script caches and rebuilding fixed it. A direct
`.\gradlew :app:assembleDebug --no-daemon` is a useful diagnostic.

## Network notes

- Maven Central, dl.google.com, services.gradle.org and pub.dev are reachable.
- `maven.google.com` and github.com direct downloads time out on this machine;
  Gradle's `google()` resolves to `dl.google.com`, which works.
- `huggingface.co` times out; **`hf-mirror.com` works** and is the default model
  mirror in `assets/models/manifest.json`.
- The MangaOCR model can be downloaded from hf-mirror or imported manually in
  the settings page.

## Development data

The app reads UniDic and MDict in place. For an emulator or device:

```bash
adb shell mkdir -p /sdcard/Download
adb push unidic/unidic-cwj-202512 /sdcard/Download/
adb push "mdicts/講談社 日本語大辞典 第二版 双解版" /sdcard/Download/
```

Then grant All Files Access in the app and enter:

- UniDic: `/sdcard/Download/unidic-cwj-202512`
- MDX: `/sdcard/Download/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdx`

Alternatively place files under
`/sdcard/Android/data/com.rikai.mobile/files/`, which needs no special
permission.

## Build commands

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

The debug APK is large (all ABIs, debug runtime). The release APK is arm64-only
and downloads OCR models on demand.

## Emulator

```bash
flutter emulators --launch Medium_Phone_API_36.1
```

The debug APK includes x86_64 ONNX Runtime and MeCab libraries, so OCR and
tokenization can be exercised on the x86_64 emulator (slowly). Final
performance and vertical-text quality require an arm64 device.
