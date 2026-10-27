# Phase 1 status

Date: 2026-10-27
Project root: `C:\Projects\Rikai-Mobile`
Device: `Medium_Phone_API_36.1` (x86_64 emulator, API 36). No arm64 device is
connected, so the timings below are functional smoke-test numbers only.

## Completed

- `Token` model (`lib/core/models/token.dart`) with the documented 29-field
  UniDic mapping, katakana→hiragana readings, content/function classification,
  lookup candidates and UTF-16 offsets.
- CSV-aware MeCab output parser
  (`lib/services/mecab/mecab_output_parser.dart`). UniDic fields such as
  `"動詞%F2@1,形容詞%F4@-2"` contain commas inside double quotes; splitting on
  every comma produced 30–31 fields and disabled readings for 助動詞/助詞.
- `UnidicValidator` (`lib/services/mecab/unidic_validator.dart`): required
  files, `sys.dic` magic/size, version 102, UTF-8, entry count and declared
  length consistency. The UniDic directory is only read.
- `MecabService` (`lib/services/mecab/mecab_service.dart`):
  - validates the directory, creates a private `mecabrc` under the app support
    directory, passes it with `-r "<path>"` through the existing options string;
  - long-lived worker isolate holding one MeCab model (dictionary stays mmap'ed);
  - serial `analyze`, per-line invocation to preserve line breaks, offset
    mapping, error codes, timeouts and graceful disposal.
- All Files Access native channel (`rikai/storage_permission`) in
  `MainActivity.kt`: status, open the system All Files Access page, legacy
  `READ_EXTERNAL_STORAGE` request for API 29 and below, app-details settings.
- Settings page: UniDic path, validate-and-save with metadata display, storage
  permission card, app-private external directory hint, furigana switch and
  reader font size.
- Reader page: text input, tokenization, `ReaderBlock`/`TokenChip`/
  `FuriganaText`, content-word highlighting, furigana toggle, font size, copy
  full text, token detail sheet (dictionary lookup is Phase 2).
- `go_router` navigation; home page wires text input and settings.
- Riverpod 3 provider-level retry disabled for the MeCab service so an invalid
  UniDic does not trigger repeated 1.3 GB initialization attempts.

## Verification

```text
flutter analyze  -> No issues found
flutter test     -> 41 tests passed
flutter build apk --debug -> success
```

Device integration suite (4 tests, all passed):

```text
Storage permission: sdk=36 allFilesAccess=true legacyRead=false
MecabService.open: 246 ms
食べ	たべ	動詞・一般・*・*	食べる	0..2
た	た	助動詞・*・*・*	た	2..3
東京	とうきょう	名詞・固有名詞・地名・一般	トウキョウ	3..5
Analyzed 1100 tokens in 175 ms; non-standard layouts: 0
reader page renders furigana for 食べた東京
```

The integration suite (`integration_test/mecab_android_test.dart`) verifies:

1. the native All Files Access channel inside the app process;
2. real UniDic tokenization/readings/offsets for `食べた東京`, including the
   quoted-comma 助動詞 row;
3. a longer sample with all 29-field layouts intact;
4. the full UI flow: saved path → home → reader → 分词 → furigana for
   `たべ`/`とうきょう`.

Run it with (Git Bash on Windows must disable path conversion; `flutter test`
installs then uninstalls the app, so grant the app-op in a parallel loop):

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/mecab_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_UNIDIC_PATH=/sdcard/Download/unidic-cwj-202512
```

See `docs/dev-setup.md` for the grant loop and push commands.

## Notes and limitations

- Loading the 1.3 GB UniDic from `/sdcard/Download` via mmap works on the
  x86_64 emulator; `MecabService.open` took 246 ms (validation + private rc +
  worker startup). Performance on arm64 still needs a real device.
- `flutter test` (integration) uninstalls the app afterwards, which removes
  `MANAGE_EXTERNAL_STORAGE`; the test waits up to 120 s for the host to grant
  it again.
- UniDic feature rows must be parsed as CSV with quote support. Do not use
  `TokenNode.features` from `mecab_for_dart` for UniDic data.
- Tokenization is per input line. Empty lines are preserved as blank blocks in
  the reader.
- The token detail sheet only shows token metadata and lookup candidates;
  clicking through to MDict entries is Phase 2.

## Next

Phase 2: MDict worker isolate, dictionary registry, lookup/normalization,
`@@@LINK` resolution, offline WebView entry rendering, search page and
dictionary management.
