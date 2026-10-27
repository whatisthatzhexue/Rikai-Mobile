# ADR 0003: MDict through dict_reader

- Status: accepted
- Date: 2026-10-26

## Context

The development dictionary is MDict v2.0 UTF-8, 463,312 entries, 33.8 MB MDX,
6.2 MB MDD, unencrypted, zlib-compressed, with an external CSS file.
`dict_reader` 1.6.1 is MIT, pure Dart, uses `RandomAccessFile` + block caches,
and exposes `locate`, `locateAll`, `readOneMdx`, `readOneMdd`, and prefix
`search`.

Its limitations are LZO compression, record-block encryption, checksum
verification, and incomplete v3 support.

## Decision

Use `dict_reader` in a long-lived worker isolate. Load dictionaries in place
from user-supplied paths. Validate the MDX header and compression/encryption at
import time and reject unsupported files with a concrete error.

If a real dictionary proves too slow or unsupported, the fallback is a
SQLite key index or a Rust/native MDict reader; the repository/facade boundary
keeps this replaceable.

## Consequences

- No dictionary content is copied or redistributed.
- The 463k-key index is held in memory per open dictionary; measure and cache
  if needed.
- HTML must be sanitized and rendered in an offline WebView; MDD resources are
  extracted lazily and rewritten to local file URLs.
