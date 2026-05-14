//// Encoding errors returned by qrkit's public API.

/// Errors returned while building a QR code.
pub type EncodeError {
  DataExceedsCapacity(bits_needed: Int, bits_available: Int)
  InvalidVersion(requested: Int)
  InvalidEciDesignator(designator: Int)
  UnsupportedCharacter(at_index: Int, character: String)
  EmptyInput
  IncompatibleOptions(reason: String)
}

/// Errors returned while reading individual modules from a QR matrix.
pub type MatrixAccessError {
  ModuleOutOfBounds(x: Int, y: Int, width: Int, height: Int)
}
