# Modifications to mecab_for_dart

Vendored from `mecab_for_dart` 2.0.5 (BSD-3-Clause, Copyright 2024 CaptainDario)
for Rikai-Mobile.

Changes:

- `src/dart_ffi.cpp` — `generateArgs()` now only passes `-r <dicdir>/mecabrc`
  when that file exists. Rikai-Mobile loads a user-supplied, read-only UniDic
  directory that has no `mecabrc`; the app passes its own private rc file via
  the existing `options` string instead of writing into the user's directory.
- `analysis_options.yaml` — disabled `avoid_print` and
  `curly_braces_in_flow_control_structures` for this vendored package so
  `flutter analyze` stays clean without rewriting upstream source.
- Added this file and `THIRD_PARTY_NOTICES.md`.

No other source changes. The upstream BSD license in `LICENSE` is retained.
