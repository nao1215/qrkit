//// Encoding errors returned by qrkit's public API.

/// Errors returned while building a QR code.
pub type EncodeError {
  DataExceedsCapacity(bits_needed: Int, bits_available: Int)
  InvalidVersion(requested: Int)
  UnsupportedCharacter(at_index: Int, character: String)
  EmptyInput
  IncompatibleOptions(reason: String)
}
