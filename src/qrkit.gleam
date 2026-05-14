//// Public API for the qrkit package.

import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/error
import qrkit/internal/micro
import qrkit/internal/rmqr
import qrkit/internal/standard
import qrkit/internal/structured_append
import qrkit/internal/util
import qrkit/types

/// Type alias for [`qrkit/types.ErrorCorrection`](./qrkit/types.html#ErrorCorrection).
/// To pattern-match on `Low | Medium | Quartile | High`, `import qrkit/types`.
pub type ErrorCorrection =
  types.ErrorCorrection

/// Type alias for [`qrkit/types.Mode`](./qrkit/types.html#Mode).
/// To pattern-match on `Numeric | Alphanumeric | Byte | Kanji`, `import qrkit/types`.
pub type Mode =
  types.Mode

/// Type alias for [`qrkit/types.ModePreference`](./qrkit/types.html#ModePreference).
/// To pattern-match on `Auto | ForceByte`, `import qrkit/types`.
pub type ModePreference =
  types.ModePreference

/// Type alias for [`qrkit/types.Symbol`](./qrkit/types.html#Symbol).
/// To pattern-match on `Standard | Micro | Rectangular`, `import qrkit/types`.
pub type Symbol =
  types.Symbol

/// Type alias for [`qrkit/error.EncodeError`](./qrkit/error.html#EncodeError).
/// To pattern-match on `EmptyInput | InvalidVersion(..) | DataExceedsCapacity(..) | UnsupportedCharacter(..) | IncompatibleOptions(..)`, `import qrkit/error`.
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
    mask: Int,
    rows: List(List(Bool)),
  )
}

/// The package version.
pub fn package_version() -> String {
  "0.1.0"
}

/// Create a new builder from input text.
pub fn new(data: String) -> Builder {
  Builder(data, types.Medium, 1, None, types.Standard, types.Auto)
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

/// Set the minimum symbol version. The value is interpreted relative to the
/// active symbol family: Standard QR accepts 1..40, Micro QR accepts 1..4 (M1..M4),
/// and rMQR accepts 1..32 (R7x43..R17x139).
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
      case validate_min_version(min_version, symbol) {
        Error(error) -> Error(error)
        Ok(Nil) ->
          case symbol {
            types.Standard ->
              case standard.encode(data, ecc, min_version, eci, preference) {
                Ok(encoded) ->
                  Ok(QrCode(
                    standard.version(encoded),
                    standard.width(encoded),
                    standard.height(encoded),
                    ecc,
                    symbol,
                    standard.mask(encoded),
                    standard.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
            types.Micro ->
              case micro.encode(data, ecc, min_version, preference) {
                Ok(encoded) ->
                  Ok(QrCode(
                    micro.version(encoded),
                    micro.width(encoded),
                    micro.height(encoded),
                    ecc,
                    symbol,
                    micro.mask(encoded),
                    micro.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
            types.Rectangular ->
              case rmqr.encode(data, ecc, min_version, preference) {
                Ok(encoded) ->
                  Ok(QrCode(
                    rmqr.version(encoded),
                    rmqr.width(encoded),
                    rmqr.height(encoded),
                    ecc,
                    symbol,
                    rmqr.mask(encoded),
                    rmqr.rows(encoded),
                  ))
                Error(encode_error) -> Error(encode_error)
              }
          }
      }
  }
}

fn validate_min_version(
  min_version: Int,
  symbol: Symbol,
) -> Result(Nil, EncodeError) {
  let upper = case symbol {
    types.Standard -> 40
    types.Micro -> 4
    types.Rectangular -> 32
  }
  case min_version < 1 || min_version > upper {
    True -> Error(error.InvalidVersion(min_version))
    False -> Ok(Nil)
  }
}

/// Split data into multiple symbols using Structured Append (ISO/IEC 18004 §8.2).
///
/// Each returned QR carries the 20-bit Structured Append header so a compliant
/// reader can reassemble the original message. When `data` fits in a single QR
/// at `max_version`, the returned list contains exactly one symbol with no SA
/// header. Uses the Medium error correction level — call `encode_split_with`
/// for a different level.
pub fn encode_split(
  data: String,
  max_version: Int,
) -> Result(List(QrCode), EncodeError) {
  encode_split_with(data, max_version, types.Medium)
}

/// Same as `encode_split` but with a caller-chosen error correction level.
pub fn encode_split_with(
  data: String,
  max_version: Int,
  ecc: ErrorCorrection,
) -> Result(List(QrCode), EncodeError) {
  case structured_append.encode(data, max_version, ecc) {
    Error(error) -> Error(error)
    Ok(encodes) ->
      Ok(
        list.map(encodes, fn(encoded) {
          QrCode(
            standard.version(encoded),
            standard.width(encoded),
            standard.height(encoded),
            ecc,
            types.Standard,
            standard.mask(encoded),
            standard.rows(encoded),
          )
        }),
      )
  }
}

/// Return the symbol version number. Standard QR returns 1..40, Micro QR 1..4
/// (M1..M4), and rMQR 1..32 (R7x43..R17x139).
pub fn version(qr: QrCode) -> Int {
  let QrCode(version, _, _, _, _, _, _) = qr
  version
}

/// Return the symbol side length in modules. For non-square rMQR symbols this
/// is the width; use `width` and `height` for the explicit dimensions.
pub fn size(qr: QrCode) -> Int {
  let QrCode(_, width, _, _, _, _, _) = qr
  width
}

/// Return the symbol width in modules.
pub fn width(qr: QrCode) -> Int {
  let QrCode(_, width, _, _, _, _, _) = qr
  width
}

/// Return the symbol height in modules.
pub fn height(qr: QrCode) -> Int {
  let QrCode(_, _, height, _, _, _, _) = qr
  height
}

/// Return the symbol dimensions in modules.
pub fn symbol_size(qr: QrCode) -> #(Int, Int) {
  #(width(qr), height(qr))
}

/// Return the error correction level used by this symbol.
pub fn error_correction(qr: QrCode) -> ErrorCorrection {
  let QrCode(_, _, _, ecc, _, _, _) = qr
  ecc
}

/// Return the canonical single-letter ECC designator.
pub fn error_correction_designator(ecc: ErrorCorrection) -> String {
  case ecc {
    types.Low -> "L"
    types.Medium -> "M"
    types.Quartile -> "Q"
    types.High -> "H"
  }
}

/// Return the symbol family used by this QR code.
pub fn symbol(qr: QrCode) -> Symbol {
  let QrCode(_, _, _, _, symbol, _, _) = qr
  symbol
}

/// Return the mask pattern that was applied. Standard QR returns 0..7,
/// Micro QR 0..3, and rMQR always 4 (rMQR uses a single fixed mask).
pub fn mask(qr: QrCode) -> Int {
  let QrCode(_, _, _, _, _, mask, _) = qr
  mask
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
  let QrCode(_, _, _, _, _, _, rows) = qr
  rows
}
