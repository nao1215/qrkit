//// Errors produced by the internal encoders and decoder. `qrkit` converts
//// them into its public `EncodeError` and `DecodeError`.

import qrkit/internal/types.{type ErrorCorrection, type Symbol}

pub type EncodeError {
  DataExceedsCapacity(bits_needed: Int, bits_available: Int)
  InvalidVersion(requested: Int)
  InvalidEciDesignator(designator: Int)
  UnsupportedCharacter(at_index: Int, character: String)
  EmptyInput
  ErrorCorrectionNotSupported(symbol: Symbol, error_correction: ErrorCorrection)
}

pub type DecodeError {
  NotASymbol(width: Int, height: Int)
  UnreadableFormatInformation
  TooManyErrors
  MalformedData
}
