# Phase 2 status

Date: 2026-10-28
Project root: `C:\Projects\Rikai-Mobile`
Device: `Medium_Phone_API_36.1` (x86_64 emulator, API 36). No arm64 device.

## Completed

### MDict worker and registry

- `lib/services/mdict/mdict_worker.dart` — long-lived worker isolate with one
  lazily opened `DictReader` per dictionary. Commands: `probe`, `lookup`,
  `resource`, `close`, `dispose`.
  - Preflight rejects MDict 3.0, encrypted dictionaries, LZO/unsupported
    blocks (via `dict_reader` init errors) with explicit messages.
  - `lookup` expands candidates, uses `locateAll`/`readOneMdx`, resolves
    `@@@LINK=` up to 3 levels, de-duplicates by record location, limits entries
    per dictionary (default 3), and returns prefix suggestions when nothing
    matches.
  - `resource` resolves MDD keys with leading-backslash and slash/backslash
    variants, returning PNG/font bytes.
- `lib/core/models/dict_info.dart` — `DictionaryInfo` registry model with a
  stable path hash id, metadata, enabled/order, validation time/error.
- `lib/services/storage/dictionary_store.dart` — JSON registry in
  SharedPreferences; only paths/metadata are stored.
- `lib/state/providers.dart` — `MdictServiceNotifier`,
  `DictionaryRepositoryNotifier`, `enabledDictionariesProvider`; add/remove/
  enable/order/revalidate; sibling `.mdd` (same basename) and `.css`
  (all in the directory) discovery. No copying.
- `lib/core/utils/text_normalizer.dart` — NFKC, full/half width, ASCII case,
  hiragana/katakana and stripkey candidates.
- `lib/services/mdict/mdd_key.dart` — MDD key normalization
  (`3913.png` → `\3913.png`, `JC_Z24Z/A471.png` → `\JC_Z24Z\A471.png`,
  file:// and percent-encoded keys).

### Entry rendering and UI

- `lib/services/mdict/entry_renderer.dart` — `package:html` sanitizer:
  removes scripts/iframes/objects/forms/links/meta, `on*` and `javascript:`
  attributes, strips CSS style/script breakouts; injects dictionary CSS;
  rewrites `src`/`url()` to local cache files; blocks network images;
  placeholders for missing MDD resources; multiple entries separated by a
  divider.
- `lib/features/lookup/entry_web_view.dart` — `flutter_inappwebview` with
  JavaScript disabled, network loads blocked, local file access only.
  `entry://` links are routed back to a new lookup; external URLs are blocked.
- `lib/features/lookup/entry_page.dart` — one tab per dictionary, rendered
  asynchronously into a cache directory.
- `lib/features/lookup/lookup_sheet.dart` — token lookup from the reader:
  token/reading/POS header, dictionary filter chips, grouped hits, suggestions,
  and a manage-dictionary path.
- `lib/features/lookup/search_page.dart` — manual search with dictionary
  filters, suggestions, errors, and entry navigation.
- `lib/features/settings/dictionary_page.dart` — add (path dialog), enable,
  reorder, revalidate, delete (does not delete files); shows entry count,
  encoding/version, MDD/CSS counts and path errors.
- Settings page and home cards now link to dictionary management and search.
- Reader token taps open the lookup sheet instead of the placeholder detail
  sheet.

### Design tokens

- `docs/design-tokens.md` — normative UI specification: blue/white palette
  (`#0052D9` primary), 3x design sizes 72/48/36 → Flutter 24/16/12sp, 4pt
  spacing, compact 40dp controls, 12dp cards, TDesign variable mapping.
- `lib/core/theme/app_tokens.dart` — all colors, typography, spacing, radii,
  sizes and `AppTheme.light()`; every existing screen was migrated to this
  theme (light-only v1).
- HarmonyOS Sans SC Regular is declared in `pubspec.yaml` but **not committed**
  (`.gitignore`); users download it to
  `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf` per `assets/fonts/README.md`.

## Verification

```text
flutter analyze  -> No issues found
flutter test     -> 67 tests passed
flutter build apk --debug -> success
```

Device integration suite (`integration_test/mdict_android_test.dart`, 5 tests,
all passed with the real 講談社 dictionary):

```text
MdictService.open=716ms probe=675ms title=講談社 日本語大辞典 第二版 双解版
entries=463312 encoding=UTF-8 version=2.0
lookup 東京=425ms matched=東京 headword=とうきょう【東京】 html=724 candidates=1
hot lookup 東京=1ms
suggestions=[とうきょうえき, とうきょうえき【東京駅】]
resource JC_Z24Z/A471.png -> 334 bytes
rendered 2 entries, html=19273
repository: 講談社 日本語大辞典 第二版 双解版 463312 entries
search page opens a dictionary entry with the real MDict
```

The 425 ms first lookup includes opening/initializing the 463,312-entry MDX in
the worker; the second lookup is 1 ms. The Phase 1 MeCab device suite (4 tests)
is unchanged and still passes.

Run the MDict suite (Git Bash must disable path conversion; `flutter test`
installs then uninstalls the app, so grant the app-op in a parallel loop):

```bash
export MSYS_NO_PATHCONV=1
adb shell mkdir -p /sdcard/Download/rikai-mdict
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdx" \
  /sdcard/Download/rikai-mdict/dict.mdx
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdd" \
  /sdcard/Download/rikai-mdict/dict.mdd
adb push "mdicts/講談社 日本語大辞典 第二版 双解版/NihongoDaijiten.css" \
  /sdcard/Download/rikai-mdict/dict.css

flutter test integration_test/mdict_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_MDICT_PATH=/sdcard/Download/rikai-mdict/dict.mdx
```

See `docs/dev-setup.md` for the All Files Access grant loop.

## Notes and limitations

- Files are read in place; the registry only stores paths. External SD card
  removal results in a per-dictionary path error and a revalidate action.
- MDD keys in the test dictionary are `\JC_Z24Z\A471.png` while HTML uses
  `JC_Z24Z/A471.png`, hence the key-variant resolver.
- WebView dictionary content uses the system Japanese font and dictionary CSS;
  app chrome uses HarmonyOS Sans SC. Dark mode is not part of v1.
- CSS discovery currently includes every `.css` file next to the MDX; there is
  no per-dictionary CSS selection UI yet.
- Up to 3 entries per dictionary are returned. Homographs (e.g. 猫) are rendered
  in one page separated by a divider.
- MDD cache files are not cleaned up yet (Phase 5).
- No fuzzy/edit-distance search or full-text search.
- The UI uses Material 3 mapped to the design tokens; TDesign is documented as
  an allowed future component library but is not adopted in this phase.
- x86_64 timings are functional smoke results; arm64 performance remains to be
  measured.

## Next

Phase 3: extract the PaddleOCR ONNX detection/recognition pipeline, add
`ModelManager`, camera/gallery input, and connect horizontal OCR to the reader
and lookup flow. Complete the ORT model smoke test first (see `CLAUDE.md` §4).
