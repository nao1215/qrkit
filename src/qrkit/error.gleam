//// Public types shared across the qrkit API.

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

/// Errors returned while building a QR code.
pub type EncodeError {
  DataExceedsCapacity(bits_needed: Int, bits_available: Int)
  InvalidVersion(requested: Int)
  UnsupportedCharacter(at_index: Int, character: String)
  EmptyInput
  IncompatibleOptions(reason: String)
}
