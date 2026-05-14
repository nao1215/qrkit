//// Configuration enums shared by the qrkit public API and internal modules.
////
//// These intentionally live in a leaf module so that both `qrkit` and every
//// `qrkit/internal/*` module can import them without creating a cycle.

/// QR Code error correction level.
pub type ErrorCorrection {
  Low
  Medium
  Quartile
  High
}

/// Data encoding mode.
pub type Mode {
  Numeric
  Alphanumeric
  Byte
  Kanji
}

/// Encoder strategy hint.
pub type ModePreference {
  Auto
  ForceByte
}

/// Symbol family.
pub type Symbol {
  Standard
  Micro
  Rectangular
}
