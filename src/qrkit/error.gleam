//// Errors returned by qrkit's public API.

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

/// Errors returned by `qrkit/decode`.
pub type DecodeError {
  /// The matrix is not rectangular, or its size matches no Standard QR,
  /// Micro QR or rMQR symbol (after the quiet zone is removed).
  NotASymbol(width: Int, height: Int)
  /// Neither copy of the format information is within the BCH code's
  /// correction distance of a valid value, in any orientation.
  UnreadableFormatInformation
  /// A Reed-Solomon block has more errors than it can correct.
  TooManyErrors
  /// The corrected data does not follow the symbol's bit stream grammar
  /// (unknown mode, truncated segment, out-of-range digit group, or a Kanji
  /// value outside JIS X 0208).
  MalformedData(reason: String)
}
