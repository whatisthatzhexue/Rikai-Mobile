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

If a debug or integration-test build left `integration_test` in
`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`,
the release compile fails with `パッケージdev.flutter.plugins.integration_testは
存在しません`. Regenerate release tooling once, then build:

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi --config-only
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

`--config-only` rewrites the registrant with release filtering (dev-only plugins
such as `integration_test` are excluded).

On a fresh install the app opens the Phase 5 onboarding guide. Existing installs
with a saved UniDic path skip it automatically; Settings → “重新查看新手引导”
opens it again. Text/photo corpus records live under the application support
directory; Settings → “语料与存储” can clear the corpus or the extracted MDict
resource cache. The release build still signs with the debug keystore
(`android/app/build.gradle.kts` has a TODO) — replace it before distribution.

The current unit/widget suite is 149 tests. It includes onboarding, reader text
saving, photo-block serialization and corpus image resize/JPEG tests; no desktop
SQLite test dependency is used because `sqflite_common_ffi` pulls a native
SQLite download that breaks offline Android builds.

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

## Camera and capture session

The capture page uses the `camera` plugin (CameraX) and the app declares
`android.permission.CAMERA`; image_picker is used only for gallery import.
The emulator's virtual camera is sufficient for a functional smoke test. When
opening the photo set or backgrounding the app, the controller is disposed and
recreated on return; a denied permission shows settings/gallery fallbacks.

Captured/imported photos are copied into the app's temporary
`rikai_capture/` session directory. The photo set survives leaving the capture
page, and the directory is cleared when the app starts with an empty session.
The local corpus database and photo copies live under the app support directory
(`rikai_history.db`, `corpus/images/`).

## OCR model directory

The model page can use the default
`getExternalFilesDir()/models/` or a user-selected directory. Changing the
directory validates read/write/free space and defaults to migrating the models;
“仅切换” leaves the old files in place. The custom mirror field requires a
full `http(s)://host` prefix.

## OCR integration test

The Phase 4.5 suite runs the real PaddleOCR, MangaOCR and orientation models from
public storage and needs All Files Access just like the MeCab suite. Push models
once; `_modelDir` points at the Paddle folder and the test finds the sibling
`manga_ocr/` and `orientation/` folders:

```bash
export MSYS_NO_PATHCONV=1
adb shell mkdir -p /sdcard/Download/rikai-models/paddle_v5 \
  /sdcard/Download/rikai-models/manga_ocr \
  /sdcard/Download/rikai-models/orientation
adb push build/ocr-models/paddle_v5/det.onnx  /sdcard/Download/rikai-models/paddle_v5/
adb push build/ocr-models/paddle_v5/rec.onnx  /sdcard/Download/rikai-models/paddle_v5/
adb push build/ocr-models/paddle_v5/keys.yml  /sdcard/Download/rikai-models/paddle_v5/
adb push build/ocr-models/manga_ocr/.  /sdcard/Download/rikai-models/manga_ocr/
adb push build/ocr-models/orientation/. /sdcard/Download/rikai-models/orientation/
```

```bash
# Shell A
export MSYS_NO_PATHCONV=1
flutter test integration_test/ocr_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_OCR_MODEL_DIR=/sdcard/Download/rikai-models/paddle_v5
```

Use the same app-op grant loop as the MeCab test. The Phase 4.5 suite (8 cases)
renders horizontal/vertical/tilted/90°/270°/upside-down PNGs, verifies
automatic/manual routing, lazy optional sessions, the 90°/270°/180° corrections,
deskew, progress events, cancellation, and prints timing/blocks. Results are
recorded in `docs/phase4.5-status.md`.

Push the seven user-provided regression images to
`/sdcard/Download/rikai-test-images/` and run:

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/ocr_real_images_android_test.dart -d emulator-5554
```

MDict compatibility (Encrypted=2 and MDD resources) uses
`/sdcard/Download/rikai-mdict-compat/{kanjigen,meikyo}/` with ASCII
`dict.mdx`/`dict.mdd`/`dict.css` names:

```bash
flutter test integration_test/mdict_compat_android_test.dart -d emulator-5554
```

For manual app runs without a working model download, a debug build can point
the model manager at a public folder:

```bash
export MSYS_NO_PATHCONV=1
flutter build apk --debug \
  --dart-define=RIKAI_OCR_MODELS_DIR=/sdcard/Download/rikai-models
```

That override is empty in normal builds. The app normally stores models in
`getExternalFilesDir()/models/`. If you stage files with `adb push` into
`Android/data`, launch the app/model manager first so the directory is owned by
the app; shell-created directories under `Android/data` are not readable by the
app on this emulator.

**Important:** `flutter test integration_test/...` replaces
`build/app/outputs/flutter-apk/app-debug.apk` with an APK whose entry point is
the integration test. If you install that file manually it will stop on the
system splash. Always run `flutter build apk --debug` again before installing
the app by hand.
