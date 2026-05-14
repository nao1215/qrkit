//// Public API for the qrkit package.

import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/error
import qrkit/internal/micro
import qrkit/internal/rmqr
import qrkit/internal/standard
import qrkit/internal/structured_append
import qrkit/internal/util

pub type ErrorCorrection =
  error.ErrorCorrection

pub type Mode =
  error.Mode

pub type ModePreference =
  error.ModePreference

pub type Symbol =
  error.Symbol

pub type EncodeError =
  error.EncodeError

pub opaque type Builder {
  Builder(
    data: String,
    ecc: ErrorCorrection,
    min_version: Int,
    eci: Option(Int),
    symbol: Symbol,
    preference: ModePreference,
  )
}

pub opaque type QrCode {
  QrCode(
    version: Int,
    width: Int,
    height: Int,
    ecc: ErrorCorrection,
    symbol: Symbol,
    rows: List(List(Bool)),
  )
}

/// The package version.
pub fn package_version() -> String {
  "0.1.0"
}

/// Create a new builder from input text.
pub fn new(data: String) -> Builder {
  Builder(data, error.Medium, 1, None, error.Standard, error.Auto)
}

/// Encode input text using the default builder configuration.
pub fn encode(data: String) -> Result(QrCode, EncodeError) {
  new(data) |> build()
}

/// Set the desired error correction level.
pub fn with_ecc(builder: Builder, ecc: ErrorCorrection) -> Builder {
  let Builder(data, _, min_version, eci, symbol, preference) = builder
  Builder(data, ecc, min_version, eci, symbol, preference)
}

/// Set the minimum standard QR version that may be used.
pub fn with_min_version(builder: Builder, min_version: Int) -> Builder {
  let Builder(data, ecc, _, eci, symbol, preference) = builder
  Builder(data, ecc, min_version, eci, symbol, preference)
}

/// Add an optional ECI assignment designator before the data segments.
pub fn with_eci(builder: Builder, designator: Int) -> Builder {
  let Builder(data, ecc, min_version, _, symbol, preference) = builder
  Builder(data, ecc, min_version, Some(designator), symbol, preference)
}

/// Select the symbol family.
pub fn with_symbol(builder: Builder, symbol: Symbol) -> Builder {
  let Builder(data, ecc, min_version, eci, _, preference) = builder
  Builder(data, ecc, min_version, eci, symbol, preference)
}

/// Change the mode optimisation strategy.
pub fn with_mode_preference(
  builder: Builder,
  preference: ModePreference,
) -> Builder {
  let Builder(data, ecc, min_version, eci, symbol, _) = builder
  Builder(data, ecc, min_version, eci, symbol, preference)
}

/// Build a QR code from the accumulated builder configuration.
pub fn build(builder: Builder) -> Result(QrCode, EncodeError) {
  let Builder(data, ecc, min_version, eci, symbol, preference) = builder
  case data == "" {
    True -> Error(error.EmptyInput)
    False ->
      case min_version < 1 || min_version > 40 {
        True -> Error(error.InvalidVersion(min_version))
        False ->
          case symbol {
            error.Standard ->
              case standard.encode(data, ecc, min_version, eci, preference) {
                Ok(encoded) ->
                  Ok(QrCode(
                    standard.version(encoded),
                    standard.width(encoded),
                    standard.height(encoded),
                    ecc,
                    symbol,
                    standard.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
            error.Micro ->
              case
                micro.encode(
                  data,
                  ecc,
                  clamp_micro_version(min_version),
                  preference,
                )
              {
                Ok(encoded) ->
                  Ok(QrCode(
                    micro.version(encoded),
                    micro.width(encoded),
                    micro.height(encoded),
                    ecc,
                    symbol,
                    micro.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
            error.Rectangular ->
              case rmqr.encode(data, ecc, min_version, preference) {
                Ok(encoded) ->
                  Ok(QrCode(
                    rmqr.version(encoded),
                    rmqr.width(encoded),
                    rmqr.height(encoded),
                    ecc,
                    symbol,
                    rmqr.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
          }
      }
  }
}

/// Split data into multiple symbols using Structured Append (ISO/IEC 18004 §8.2).
///
/// Each returned QR carries the 20-bit Structured Append header so a compliant
/// reader can reassemble the original message. When `data` fits in a single QR
/// at `max_version`, the returned list contains exactly one symbol with no SA
/// header.
pub fn encode_split(
  data: String,
  max_version: Int,
) -> Result(List(QrCode), EncodeError) {
  case structured_append.encode(data, max_version, error.Medium) {
    Error(error) -> Error(error)
    Ok(encodes) ->
      Ok(
        list.map(encodes, fn(encoded) {
          QrCode(
            standard.version(encoded),
            standard.width(encoded),
            standard.height(encoded),
            error.Medium,
            error.Standard,
            standard.rows(encoded),
          )
        }),
      )
  }
}

/// Return the standard QR version number.
pub fn version(qr: QrCode) -> Int {
  let QrCode(version, _, _, _, _, _) = qr
  version
}

/// Return the symbol side length in modules.
pub fn size(qr: QrCode) -> Int {
  let QrCode(_, width, _, _, _, _) = qr
  width
}

/// Alias for `size/1` for square symbols.
pub fn side_length(qr: QrCode) -> Int {
  size(qr)
}

/// Return the symbol width in modules.
pub fn width(qr: QrCode) -> Int {
  let QrCode(_, width, _, _, _, _) = qr
  width
}

/// Return the symbol height in modules.
pub fn height(qr: QrCode) -> Int {
  let QrCode(_, _, height, _, _, _) = qr
  height
}

/// Return the symbol dimensions in modules.
pub fn symbol_size(qr: QrCode) -> #(Int, Int) {
  #(width(qr), height(qr))
}

/// Return the error correction level used by this symbol.
pub fn error_correction(qr: QrCode) -> ErrorCorrection {
  let QrCode(_, _, _, ecc, _, _) = qr
  ecc
}

/// Return the canonical single-letter ECC designator.
pub fn error_correction_designator(ecc: ErrorCorrection) -> String {
  case ecc {
    error.Low -> "L"
    error.Medium -> "M"
    error.Quartile -> "Q"
    error.High -> "H"
  }
}

/// Return the symbol family used by this QR code.
pub fn symbol(qr: QrCode) -> Symbol {
  let QrCode(_, _, _, _, symbol, _) = qr
  symbol
}

/// Return a single module from the symbol matrix.
pub fn module_at(qr: QrCode, x: Int, y: Int) -> Bool {
  case rows(qr) |> util.at(y) {
    Ok(row) ->
      case util.at(row, x) {
        Ok(value) -> value
        Error(_) -> False
      }
    Error(_) -> False
  }
}

/// Return the symbol matrix as rows of booleans.
pub fn rows(qr: QrCode) -> List(List(Bool)) {
  let QrCode(_, _, _, _, _, rows) = qr
  rows
}

fn clamp_micro_version(min_version: Int) -> Int {
  case min_version {
    value if value < 1 -> 1
    value if value > 4 -> 4
    value -> value
  }
}
