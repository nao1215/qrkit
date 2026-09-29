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

/// How `build` chooses among the rMQR sizes that hold the payload when no
/// exact version is set.
pub type RectangularPriority {
  /// The fewest modules (width x height); ties go to the lower symbol.
  SmallestArea
  /// The lowest symbol (7 modules first); ties go to the narrower one.
  ShortestHeight
  /// The narrowest symbol (27 modules first); ties go to the lower one.
  NarrowestWidth
}
