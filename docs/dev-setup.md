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

## Fonts

The UI font is **HarmonyOS Sans SC Regular**. The font file is **not** part of
the repository (`.gitignore` excludes `assets/fonts/*.ttf`). Download it from
Huawei's HarmonyOS design resources and place it at:

```text
assets/fonts/HarmonyOS_Sans_SC_Regular.ttf
```

See `assets/fonts/README.md`. `pubspec.yaml` declares the family, so
`flutter pub get`/build fails with a missing-asset error until the file exists.
UI tokens and component rules are in `docs/design-tokens.md`.

## Launcher icon and splash

The source icon is `assets/Rikai_Icon.jpg` (2048×2048). Launcher icons are
generated with `flutter_launcher_icons`; re-run after changing the source:

```bash
dart run flutter_launcher_icons
```

The native launch screen uses `drawable-nodpi/launch_icon.png`; the Flutter
splash (`lib/bootstrap.dart`) shows the same asset and the real initialization
phases. File paths for UniDic/MDict can be chosen through the system directory
picker; note that `file_picker`'s file picker copies files into its cache, so the
app intentionally uses the directory picker to preserve the in-place reading
contract.

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

## MeCab integration test with a real UniDic

`flutter test` installs the app immediately before running the test and
uninstalls it afterwards. Grant `MANAGE_EXTERNAL_STORAGE` in a second shell
while the test is starting:

```bash
# Push the dictionary. Git Bash on Windows rewrites /sdcard paths in every
# command-line argument, including --dart-define, unless path conversion is
# disabled.
export MSYS_NO_PATHCONV=1
adb shell mkdir -p /sdcard/Download
adb push unidic/unidic-cwj-202512 /sdcard/Download/
```

```bash
# Shell A: run the integration test (keep MSYS_NO_PATHCONV=1 exported, or the
# --dart-define value becomes C:/GitBash/sdcard/...).
export MSYS_NO_PATHCONV=1
flutter test integration_test/mecab_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_UNIDIC_PATH=/sdcard/Download/unidic-cwj-202512
```

```bash
# Shell B: grant All Files Access as soon as the app is installed.
while ! adb shell pm list packages | grep -q package:com.rikai.mobile; do
  sleep 0.5
done
adb shell appops set com.rikai.mobile MANAGE_EXTERNAL_STORAGE allow
```

The test waits up to 120 seconds for the dictionary to become readable, so
the grant can land after the test process has started. It verifies the real
29-field UniDic output for `食べた東京`, line offsets and readings, and prints
tokenization timing for a longer sample.

## MDict integration test with the real dictionary

`flutter test` installs and later uninstalls the app, so use the same app-op
grant loop described above. Push the dictionary with ASCII-only file names
(MDD discovery requires the MDX/MDD basenames to match):

```bash
export MSYS_NO_PATHCONV=1
adb shell mkdir -p /sdcard/Download/rikai-mdict
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdx" \
  /sdcard/Download/rikai-mdict/dict.mdx
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdd" \
  /sdcard/Download/rikai-mdict/dict.mdd
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/NihongoDaijiten.css" \
  /sdcard/Download/rikai-mdict/dict.css
```

```bash
# Shell A
export MSYS_NO_PATHCONV=1
flutter test integration_test/mdict_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_MDICT_PATH=/sdcard/Download/rikai-mdict/dict.mdx
```

```bash
# Shell B: grant All Files Access as soon as the app is installed.
while ! adb shell pm list packages | grep -q package:com.rikai.mobile; do
  sleep 0.5
done
adb shell appops set com.rikai.mobile MANAGE_EXTERNAL_STORAGE allow
```

The suite verifies header metadata, `@@@LINK` resolution, hot lookup timing,
prefix suggestions, MDD image bytes, HTML sanitization/CSS injection, the
dictionary registry, and the full search → entry WebView flow. Results are
recorded in `docs/phase2-status.md`.
