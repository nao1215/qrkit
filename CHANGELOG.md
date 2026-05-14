# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Changed

- **Breaking**: `qrkit.with_min_version(N)` is now a strict floor. If the
  payload, the chosen mode, or the chosen ECC level cannot be encoded at
  version N, `qrkit.build` returns `Error(DataExceedsCapacity)` or
  `Error(IncompatibleOptions)` instead of silently promoting to a larger
  version. The historical "smallest fit" default is preserved for callers
  that omit `with_min_version` entirely. This affects all three symbol
  families (Standard QR, Micro QR, rMQR) and `qrkit.encode_split` is
  unaffected (it still picks the smallest version per shard inside the
  caller's `max_version` cap).

### Initial

- Bootstrap the repository as a Gleam package with CI, release
  automation, and baseline QR Code primitives.
