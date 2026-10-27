# ADR 0002: Load UniDic in place

- Status: accepted
- Date: 2026-10-26

## Context

UniDic CWJ 2025.12 is ~1.313 GB (`matrix.bin` alone is ~1.03 GB). Copying it
into app storage doubles the disk requirement and slows first-run setup.
Android scoped storage makes arbitrary filesystem paths unreliable.

## Decision

The user supplies a UniDic directory path. Rikai-Mobile reads the five required
files in place and never writes to that directory. On Android 11+, the app asks
for All Files Access (`MANAGE_EXTERNAL_STORAGE`); if the user declines, they can
place UniDic under the app-specific external directory and enter that path.

MeCab's rc file is supplied by the app from its private storage through the
`-r` option; no `mecabrc` is created in the user's UniDic directory.

## Consequences

- No 1.3 GB copy and no duplicate storage.
- The app must handle permission denial and invalid/removed paths with clear
  recovery UI.
- Google Play distribution would require a different storage strategy (SAF +
  copy or file descriptors); the project currently targets sideload/learning
  distribution.
- External-storage mmap compatibility must be verified in the Phase 0 spike.
