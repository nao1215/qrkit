//// Configuration enums shared by the internal encoders and decoder. `qrkit`
//// converts its public types into these.

pub type ErrorCorrection {
  Low
  Medium
  Quartile
  High
}

/// Data encoding mode the segmenter chose for part of the payload.
pub type Mode {
  Numeric
  Alphanumeric
  Byte
  Kanji
}

pub type ModePreference {
  Auto
  ForceByte
}

pub type Symbol {
  Standard
  Micro
  Rectangular
}

pub type RectangularPriority {
  SmallestArea
  ShortestHeight
  NarrowestWidth
}
