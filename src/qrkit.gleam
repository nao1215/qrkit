//// Encode text as a QR code, render it for a terminal, as SVG or as PNG,
//// read a module matrix back, and build common payload strings.
////
//// ```gleam
//// import qrkit
////
//// pub fn main() {
////   let assert Ok(qr) = qrkit.encode("https://example.com")
////   qrkit.to_svg(qr, qrkit.default_image_options())
//// }
//// ```

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import qrkit/internal/decode as internal_decode
import qrkit/internal/error as internal_error
import qrkit/internal/matrix
import qrkit/internal/micro
import qrkit/internal/png
import qrkit/internal/rmqr
import qrkit/internal/standard
import qrkit/internal/structured_append
import qrkit/internal/svg
import qrkit/internal/terminal
import qrkit/internal/types

// Encoding -------------------------------------------------------------------

/// How much of the symbol can be damaged and still be read: about 7%
/// (`Low`), 15% (`Medium`), 25% (`Quartile`) or 30% (`High`).
pub type ErrorCorrection {
  Low
  Medium
  Quartile
  High
}

/// The symbol family: square QR codes, the smaller Micro QR (M1..M4), or
/// rectangular rMQR.
pub type Symbol {
  Standard
  Micro
  Rectangular
}

/// How the encoder picks data modes: `Auto` mixes Numeric, Alphanumeric,
/// Byte and Kanji segments to keep the symbol small, `ForceByte` writes one
/// Byte segment.
pub type ModePreference {
  Auto
  ForceByte
}

/// Which rMQR size to prefer when several hold the payload.
pub type RectangularPriority {
  /// The fewest modules (width x height); ties go to the lower symbol.
  SmallestArea
  /// The lowest symbol (7 modules first); ties go to the narrower one.
  ShortestHeight
  /// The narrowest symbol (27 modules first); ties go to the lower one.
  NarrowestWidth
}

/// Settings for `encode_with`. Start from `default_encode_options` and
/// update the fields you need.
pub type EncodeOptions {
  EncodeOptions(
    error_correction: ErrorCorrection,
    symbol: Symbol,
    /// `Some(n)` pins the version (Standard 1..40, Micro 1..4, rMQR 1..32);
    /// `None` picks the smallest version that holds the text.
    version: Option(Int),
    /// An ECI designator (0..999999) written before the data. Standard QR
    /// only. Byte data is always UTF-8, so `Some(26)` is the designator that
    /// matches it; other values only change the header.
    eci: Option(Int),
    mode: ModePreference,
    /// Used only when `symbol` is `Rectangular` and `version` is `None`.
    rectangular_priority: RectangularPriority,
  )
}

/// An encoded symbol. `rows` holds the modules row by row, `True` for dark.
pub type QrCode {
  QrCode(
    symbol: Symbol,
    /// Standard 1..40, Micro 1..4 (M1..M4), rMQR 1..32 (R7x43..R17x139).
    version: Int,
    error_correction: ErrorCorrection,
    /// Standard 0..7, Micro 0..3, rMQR always 4.
    mask: Int,
    width: Int,
    height: Int,
    rows: List(List(Bool)),
  )
}

/// Why `encode`, `encode_with` or `encode_split` failed.
pub type EncodeError {
  /// The text is empty.
  EmptyInput
  /// The requested version is outside the symbol family's range.
  InvalidVersion(requested: Int)
  /// The ECI designator is outside 0..999999.
  InvalidEciDesignator(designator: Int)
  /// The text does not fit in the requested or largest version.
  DataExceedsCapacity(bits_needed: Int, bits_available: Int)
  /// A pinned Micro QR version has no mode for this character. `at_index`
  /// counts Unicode code points from 0.
  UnsupportedCharacter(at_index: Int, character: String)
  /// The symbol family has no such error correction level (rMQR takes
  /// Medium and High; Micro QR has no High, M1 only Low, M2 and M3 no
  /// Quartile).
  ErrorCorrectionNotSupported(symbol: Symbol, error_correction: ErrorCorrection)
  /// ECI is only available for Standard QR.
  EciNotSupported(symbol: Symbol)
}

/// Returns the options `encode` uses: Medium error correction, a Standard
/// QR of the smallest version that fits, no ECI, `Auto` modes and
/// `SmallestArea` for rMQR.
///
/// ## Examples
///
/// ```gleam
/// let options =
///   qrkit.EncodeOptions(..qrkit.default_encode_options(), symbol: qrkit.Micro)
/// ```
///
pub fn default_encode_options() -> EncodeOptions {
  EncodeOptions(
    error_correction: Medium,
    symbol: Standard,
    version: None,
    eci: None,
    mode: Auto,
    rectangular_priority: SmallestArea,
  )
}

/// Encodes `text` with `default_encode_options()`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(qr) = qrkit.encode("https://example.com")
/// assert qr.version == 2
/// ```
///
/// ```gleam
/// assert qrkit.encode("") == Error(qrkit.EmptyInput)
/// ```
///
pub fn encode(text: String) -> Result(QrCode, EncodeError) {
  encode_with(text, default_encode_options())
}

/// Encodes `text` with the given options. A pinned version that is too
/// small returns `DataExceedsCapacity` instead of growing.
///
/// ## Examples
///
/// ```gleam
/// let micro =
///   qrkit.EncodeOptions(..qrkit.default_encode_options(), symbol: qrkit.Micro)
/// let assert Ok(qr) = qrkit.encode_with("12345", micro)
/// assert qr.width == 13
/// ```
///
/// ```gleam
/// let micro_high = qrkit.EncodeOptions(..micro, error_correction: qrkit.High)
/// assert qrkit.encode_with("12345", micro_high)
///   == Error(qrkit.ErrorCorrectionNotSupported(qrkit.Micro, qrkit.High))
/// ```
///
pub fn encode_with(
  text: String,
  options: EncodeOptions,
) -> Result(QrCode, EncodeError) {
  let EncodeOptions(
    error_correction:,
    symbol:,
    version:,
    eci:,
    mode:,
    rectangular_priority:,
  ) = options
  use <- bool.guard(when: text == "", return: Error(EmptyInput))
  use _ <- result.try(validate_version(version, symbol))
  use _ <- result.try(validate_eci(eci, symbol))
  let ecc = error_correction_to_internal(error_correction)
  let preference = case mode {
    Auto -> types.Auto
    ForceByte -> types.ForceByte
  }
  case symbol {
    Standard -> standard.encode(text, ecc, version, eci, preference)
    Micro -> micro.encode(text, ecc, version, preference)
    Rectangular ->
      rmqr.encode(text, ecc, version, preference, case rectangular_priority {
        SmallestArea -> types.SmallestArea
        ShortestHeight -> types.ShortestHeight
        NarrowestWidth -> types.NarrowestWidth
      })
  }
  |> result.map(from_encoded(_, symbol, error_correction))
  |> result.map_error(encode_error_from_internal)
}

/// Splits `text` over up to 16 Standard QR symbols of at most `max_version`
/// that a reader joins back together (Structured Append). Text that fits in
/// one symbol gives a list of one ordinary symbol.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(symbols) =
///   qrkit.encode_split(
///     string.repeat("0123456789", 8),
///     max_version: 2,
///     error_correction: qrkit.Medium,
///   )
/// assert list.length(symbols) == 2
/// ```
///
pub fn encode_split(
  text: String,
  max_version max_version: Int,
  error_correction error_correction: ErrorCorrection,
) -> Result(List(QrCode), EncodeError) {
  structured_append.encode(
    text,
    max_version,
    error_correction_to_internal(error_correction),
  )
  |> result.map(list.map(_, from_encoded(_, Standard, error_correction)))
  |> result.map_error(encode_error_from_internal)
}

fn validate_version(
  version: Option(Int),
  symbol: Symbol,
) -> Result(Nil, EncodeError) {
  case version {
    None -> Ok(Nil)
    Some(value) -> {
      let upper = case symbol {
        Standard -> 40
        Micro -> 4
        Rectangular -> 32
      }
      case value < 1 || value > upper {
        True -> Error(InvalidVersion(value))
        False -> Ok(Nil)
      }
    }
  }
}

fn validate_eci(eci: Option(Int), symbol: Symbol) -> Result(Nil, EncodeError) {
  case eci {
    None -> Ok(Nil)
    Some(designator) if designator < 0 || designator > 999_999 ->
      Error(InvalidEciDesignator(designator))
    Some(_) ->
      case symbol {
        Standard -> Ok(Nil)
        Micro | Rectangular -> Error(EciNotSupported(symbol))
      }
  }
}

fn from_encoded(
  encoded: matrix.Encoded,
  symbol: Symbol,
  error_correction: ErrorCorrection,
) -> QrCode {
  let matrix.Encoded(version:, width:, height:, mask:, rows:) = encoded
  QrCode(symbol:, version:, error_correction:, mask:, width:, height:, rows:)
}

fn error_correction_to_internal(
  error_correction: ErrorCorrection,
) -> types.ErrorCorrection {
  case error_correction {
    Low -> types.Low
    Medium -> types.Medium
    Quartile -> types.Quartile
    High -> types.High
  }
}

fn error_correction_from_internal(
  error_correction: types.ErrorCorrection,
) -> ErrorCorrection {
  case error_correction {
    types.Low -> Low
    types.Medium -> Medium
    types.Quartile -> Quartile
    types.High -> High
  }
}

fn symbol_from_internal(symbol: types.Symbol) -> Symbol {
  case symbol {
    types.Standard -> Standard
    types.Micro -> Micro
    types.Rectangular -> Rectangular
  }
}

fn encode_error_from_internal(
  error: internal_error.EncodeError,
) -> EncodeError {
  case error {
    internal_error.EmptyInput -> EmptyInput
    internal_error.InvalidVersion(requested:) -> InvalidVersion(requested:)
    internal_error.InvalidEciDesignator(designator:) ->
      InvalidEciDesignator(designator:)
    internal_error.DataExceedsCapacity(bits_needed:, bits_available:) ->
      DataExceedsCapacity(bits_needed:, bits_available:)
    internal_error.UnsupportedCharacter(at_index:, character:) ->
      UnsupportedCharacter(at_index:, character:)
    internal_error.ErrorCorrectionNotSupported(symbol:, error_correction:) ->
      ErrorCorrectionNotSupported(
        symbol: symbol_from_internal(symbol),
        error_correction: error_correction_from_internal(error_correction),
      )
  }
}

// Rendering ------------------------------------------------------------------

/// How `to_terminal` draws modules.
pub type TerminalStyle {
  /// Two full blocks per dark module, two spaces per light one.
  Blocks
  /// `Blocks` with dark and light swapped, for dark-on-light terminals.
  InvertedBlocks
  /// Half blocks, two module rows per line of text.
  HalfBlocks
}

/// Settings for `to_svg` and `to_png`. Start from `default_image_options`
/// and update the fields you need.
pub type ImageOptions {
  ImageOptions(
    /// Pixels per module. Values below 1 are treated as 1.
    module_size: Int,
    /// Quiet zone in modules. Negative values are treated as 0.
    margin: Int,
    /// SVG takes any CSS colour; PNG reads `#rgb`, `#rrggbb` or
    /// `#rrggbbaa` (alpha ignored) and falls back to black.
    dark_color: String,
    /// `None` leaves the background transparent. PNG falls back to white
    /// for unreadable colours.
    light_color: Option(String),
  )
}

/// Renders `qr` as text with a quiet zone of `margin` modules (negative
/// values are treated as 0). Scanners need a margin of 4.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(qr) = qrkit.encode("hello")
/// io.println(qrkit.to_terminal(qr, style: qrkit.HalfBlocks, margin: 4))
/// ```
///
pub fn to_terminal(
  qr: QrCode,
  style style: TerminalStyle,
  margin margin: Int,
) -> String {
  let margin = int.max(margin, 0)
  case style {
    Blocks -> terminal.blocks(qr.rows, margin:, dark: "██", light: "  ")
    InvertedBlocks -> terminal.blocks(qr.rows, margin:, dark: "  ", light: "██")
    HalfBlocks -> terminal.half_blocks(qr.rows, margin:)
  }
}

/// Returns 8 px modules, a 4-module quiet zone, and black on white.
pub fn default_image_options() -> ImageOptions {
  ImageOptions(
    module_size: 8,
    margin: 4,
    dark_color: "#000000",
    light_color: Some("#ffffff"),
  )
}

/// Renders `qr` as an SVG document. The size comes from `qr.rows`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(qr) = qrkit.encode("hello")
/// let options =
///   qrkit.ImageOptions(..qrkit.default_image_options(), light_color: None)
/// let svg = qrkit.to_svg(qr, options)
/// ```
///
pub fn to_svg(qr: QrCode, options: ImageOptions) -> String {
  let ImageOptions(module_size:, margin:, dark_color:, light_color:) = options
  svg.render(
    qr.rows,
    module_size: int.max(module_size, 1),
    margin: int.max(margin, 0),
    dark_color:,
    light_color:,
  )
}

/// Renders `qr` as PNG bytes with a two-colour palette. The size comes from
/// `qr.rows`.
pub fn to_png(qr: QrCode, options: ImageOptions) -> BitArray {
  let ImageOptions(module_size:, margin:, dark_color:, light_color:) = options
  png.render(
    qr.rows,
    module_size: int.max(module_size, 1),
    margin: int.max(margin, 0),
    dark_color:,
    light_color:,
  )
}

// Decoding -------------------------------------------------------------------

/// The Structured Append header of one symbol of a split message: its
/// 0-based `position`, the `total` number of symbols, and the `parity` byte
/// of the whole message.
pub type StructuredAppend {
  StructuredAppend(position: Int, total: Int, parity: Int)
}

/// A symbol read by `decode`.
pub type Decoded {
  Decoded(
    text: String,
    symbol: Symbol,
    /// Numbered as in `QrCode.version`.
    version: Int,
    error_correction: ErrorCorrection,
    mask: Int,
    /// How many codewords Reed-Solomon error correction repaired.
    errors_corrected: Int,
    /// The last ECI designator in the data, if any.
    eci: Option(Int),
    structured_append: Option(StructuredAppend),
  )
}

/// Why `decode` failed.
pub type DecodeError {
  /// The rows are not rectangular, or the size matches no Standard QR,
  /// Micro QR or rMQR symbol after the quiet zone is removed.
  NotASymbol(width: Int, height: Int)
  /// Neither copy of the format information could be corrected, in any
  /// orientation.
  UnreadableFormatInformation
  /// A Reed-Solomon block has more errors than it can correct.
  TooManyErrors
  /// The corrected data does not follow the symbol's bit stream grammar.
  MalformedData
}

/// Reads a Standard QR, Micro QR or rMQR symbol from rows of modules, `True`
/// for dark, such as `QrCode.rows`. A light quiet zone is removed first,
/// and the symbol may be rotated or mirrored. This reads a grid of modules,
/// not a photo.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(qr) = qrkit.encode("hello")
/// let assert Ok(decoded) = qrkit.decode(qr.rows)
/// assert decoded.text == "hello"
/// ```
///
/// ```gleam
/// assert qrkit.decode([[False]]) == Error(qrkit.NotASymbol(0, 0))
/// ```
///
pub fn decode(rows: List(List(Bool))) -> Result(Decoded, DecodeError) {
  case internal_decode.decode(rows) {
    Ok(decoded) -> Ok(decoded_from_internal(decoded))
    Error(internal_error.NotASymbol(width:, height:)) ->
      Error(NotASymbol(width:, height:))
    Error(internal_error.UnreadableFormatInformation) ->
      Error(UnreadableFormatInformation)
    Error(internal_error.TooManyErrors) -> Error(TooManyErrors)
    Error(internal_error.MalformedData) -> Error(MalformedData)
  }
}

fn decoded_from_internal(decoded: internal_decode.Decoded) -> Decoded {
  let internal_decode.Decoded(
    text:,
    symbol:,
    version:,
    error_correction:,
    mask:,
    errors_corrected:,
    eci:,
    structured_append:,
  ) = decoded
  Decoded(
    text:,
    symbol: symbol_from_internal(symbol),
    version:,
    error_correction: error_correction_from_internal(error_correction),
    mask:,
    errors_corrected:,
    eci:,
    structured_append: option.map(structured_append, fn(header) {
      let internal_decode.StructuredAppend(position:, total:, parity:) = header
      StructuredAppend(position:, total:, parity:)
    }),
  )
}

// Payloads -------------------------------------------------------------------

/// The security of a WiFi network, with its password.
pub type WifiSecurity {
  Open
  Wep(password: String)
  Wpa(password: String)
  Wpa2(password: String)
  Wpa3(password: String)
}

/// Builds a `WIFI:` payload that phones read as "join this network".
///
/// ## Examples
///
/// ```gleam
/// assert qrkit.wifi(ssid: "home", security: qrkit.Wpa2("secret"), hidden: False)
///   == "WIFI:T:WPA2;S:home;P:secret;;"
/// ```
///
pub fn wifi(
  ssid ssid: String,
  security security: WifiSecurity,
  hidden hidden: Bool,
) -> String {
  let #(kind, password) = case security {
    Open -> #("nopass", "")
    Wep(password:) -> #("WEP", password)
    Wpa(password:) -> #("WPA", password)
    Wpa2(password:) -> #("WPA2", password)
    Wpa3(password:) -> #("WPA3", password)
  }
  let base =
    "WIFI:T:"
    <> kind
    <> ";S:"
    <> escape_wifi(ssid)
    <> ";P:"
    <> escape_wifi(password)
    <> ";"
  case hidden {
    True -> base <> "H:true;;"
    False -> base <> ";"
  }
}

/// A contact card for `vcard_to_string`.
pub type VCard {
  VCard(
    /// The formatted name. `""` writes empty `N` and `FN` properties.
    name: String,
    phone: Option(String),
    email: Option(String),
    url: Option(String),
    organization: Option(String),
    title: Option(String),
    address: Option(String),
  )
}

/// Returns a card with only a name.
pub fn vcard(name: String) -> VCard {
  VCard(
    name:,
    phone: None,
    email: None,
    url: None,
    organization: None,
    title: None,
    address: None,
  )
}

/// Renders a vCard 3.0 payload: CRLF line ends, lines folded at 75 octets,
/// and `\`, `,`, `;` and newlines escaped.
///
/// ## Examples
///
/// ```gleam
/// let card = qrkit.VCard(..qrkit.vcard("Ada"), email: Some("ada@example.com"))
/// let payload = qrkit.vcard_to_string(card)
/// ```
///
pub fn vcard_to_string(card: VCard) -> String {
  let VCard(name:, phone:, email:, url:, organization:, title:, address:) = card
  let #(n_value, fn_value) = case name {
    "" -> #(";;;;", "")
    _ -> #(escape_text(name), escape_text(name))
  }
  [
    Some("BEGIN:VCARD"),
    Some("VERSION:3.0"),
    Some("N:" <> n_value),
    Some("FN:" <> fn_value),
    option_line_with("ORG", organization, escape_text),
    option_line_with("TITLE", title, escape_text),
    option_line_with("TEL", phone, escape_text),
    option_line_with("EMAIL", email, escape_text),
    option_line_with("URL", url, escape_text),
    option_line_with("ADR", address, escape_text),
    Some("END:VCARD"),
  ]
  |> option.values
  |> list.map(fold_line)
  |> string.join(with: "\r\n")
  |> append_crlf
}

/// When a calendar event happens.
pub type EventTime {
  /// From `start` to `end`, written in UTC.
  Timed(start: timestamp.Timestamp, end: timestamp.Timestamp)
  /// Whole days from `first` to `last`, both included.
  AllDay(first: calendar.Date, last: calendar.Date)
}

/// An event for `calendar_event_to_string`.
pub type CalendarEvent {
  CalendarEvent(
    title: String,
    time: EventTime,
    location: Option(String),
    description: Option(String),
  )
}

/// Returns an event with no location or description.
pub fn calendar_event(title: String, time: EventTime) -> CalendarEvent {
  CalendarEvent(title:, time:, location: None, description: None)
}

/// Renders an iCalendar payload with one event. `UID` is derived from the
/// title and times, and `DTSTAMP` is the start, so the same event always
/// gives the same text. Years outside 1..9999 are clamped.
pub fn calendar_event_to_string(event: CalendarEvent) -> String {
  let CalendarEvent(title:, time:, location:, description:) = event
  let #(start, end, start_line, end_line) = case time {
    Timed(start:, end:) -> #(
      start,
      end,
      "DTSTART:" <> format_timestamp(start),
      "DTEND:" <> format_timestamp(end),
    )
    AllDay(first:, last:) -> {
      let start = midnight(first)
      let end = midnight(last)
      let #(day_after, _) =
        timestamp.add(end, duration.hours(24))
        |> timestamp.to_calendar(calendar.utc_offset)
      #(
        start,
        end,
        "DTSTART;VALUE=DATE:" <> format_date(first),
        "DTEND;VALUE=DATE:" <> format_date(day_after),
      )
    }
  }
  [
    Some("BEGIN:VCALENDAR"),
    Some("VERSION:2.0"),
    Some("PRODID:-//nao1215//qrkit//EN"),
    Some("BEGIN:VEVENT"),
    Some("UID:" <> synthesise_uid(title, start, end)),
    Some("DTSTAMP:" <> format_timestamp(start)),
    Some("SUMMARY:" <> escape_text(title)),
    Some(start_line),
    Some(end_line),
    option_line_with("LOCATION", location, escape_text),
    option_line_with("DESCRIPTION", description, escape_text),
    Some("END:VEVENT"),
    Some("END:VCALENDAR"),
  ]
  |> option.values
  |> list.map(fold_line)
  |> string.join(with: "\r\n")
  |> append_crlf
}

/// Builds a `mailto:` payload. The subject and body are percent-encoded.
///
/// ## Examples
///
/// ```gleam
/// assert qrkit.email(to: "a@example.com", subject: "Hi there", body: "x")
///   == "mailto:a@example.com?subject=Hi%20there&body=x"
/// ```
///
pub fn email(
  to to: String,
  subject subject: String,
  body body: String,
) -> String {
  "mailto:"
  <> encode_addr_spec(to)
  <> "?subject="
  <> uri.percent_encode(subject)
  <> "&body="
  <> uri.percent_encode(body)
}

/// Builds an `SMSTO:` payload. The body is written as given.
pub fn sms(to to: String, body body: String) -> String {
  "SMSTO:" <> to <> ":" <> body
}

/// Builds a `tel:` URI from the number as given.
pub fn phone(number: String) -> String {
  "tel:" <> number
}

/// Builds a `geo:` URI in plain decimal notation. The coordinates are not
/// range-checked.
///
/// ## Examples
///
/// ```gleam
/// assert qrkit.geo(latitude: 35.0, longitude: 139.5) == "geo:35.0,139.5"
/// ```
///
pub fn geo(latitude latitude: Float, longitude longitude: Float) -> String {
  "geo:" <> decimal(latitude) <> "," <> decimal(longitude)
}

fn midnight(date: calendar.Date) -> timestamp.Timestamp {
  timestamp.from_calendar(
    date:,
    time: calendar.TimeOfDay(hours: 0, minutes: 0, seconds: 0, nanoseconds: 0),
    offset: calendar.utc_offset,
  )
}

fn format_timestamp(time: timestamp.Timestamp) -> String {
  let #(date, calendar.TimeOfDay(hours:, minutes:, seconds:, nanoseconds: _)) =
    timestamp.to_calendar(time, calendar.utc_offset)
  format_date(date)
  <> "T"
  <> pad(hours, 2)
  <> pad(minutes, 2)
  <> pad(seconds, 2)
  <> "Z"
}

fn format_date(date: calendar.Date) -> String {
  let calendar.Date(year:, month:, day:) = date
  pad(clamp_year(year), 4)
  <> pad(calendar.month_to_int(month), 2)
  <> pad(day, 2)
}

fn synthesise_uid(
  title: String,
  start: timestamp.Timestamp,
  end: timestamp.Timestamp,
) -> String {
  // Deterministic UID: a hash of the title (see `string_hash`) combined
  // with the two times in whole Unix seconds. Scanning the same event
  // twice should not produce a new UID.
  let #(start_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(start)
  let #(end_seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(end)
  int.to_string(string_hash(title))
  <> "-"
  <> int.to_string(start_seconds)
  <> "-"
  <> int.to_string(end_seconds)
  <> "@qrkit.nao1215"
}

// `float.to_string` without exponent notation: Erlang writes `1.0e-7` and
// JavaScript `1e-7`, which geo readers do not accept.
fn decimal(value: Float) -> String {
  let text = float.to_string(value)
  case string.split_once(text, "e") {
    Error(Nil) -> text
    Ok(#(mantissa, exponent)) -> {
      let #(sign, mantissa) = case mantissa {
        "-" <> rest -> #("-", rest)
        _ -> #("", mantissa)
      }
      let #(whole, fraction) = case string.split_once(mantissa, ".") {
        Ok(parts) -> parts
        Error(Nil) -> #(mantissa, "")
      }
      let digits = whole <> fraction
      let point = string.length(whole) + result.unwrap(int.parse(exponent), 0)
      let length = string.length(digits)
      let #(whole, fraction) = case point <= 0, point >= length {
        True, _ -> #("0", string.repeat("0", -point) <> digits)
        _, True -> #(digits <> string.repeat("0", point - length), "")
        _, _ -> #(
          string.slice(digits, 0, point),
          string.drop_start(digits, point),
        )
      }
      let fraction = case trim_trailing_zeros(fraction) {
        "" -> "0"
        trimmed -> trimmed
      }
      sign <> whole <> "." <> fraction
    }
  }
}

fn trim_trailing_zeros(digits: String) -> String {
  case string.ends_with(digits, "0") {
    True -> trim_trailing_zeros(string.drop_end(digits, 1))
    False -> digits
  }
}

fn append_crlf(s: String) -> String {
  // RFC 5545 §3.1 / RFC 2426 §2.1: every content line — including
  // the final BEGIN/END boundary — is terminated by CRLF. Without
  // this, the trailing END:VCALENDAR / END:VCARD line has no
  // terminator and strict consumers reject the document.
  s <> "\r\n"
}

fn string_hash(value: String) -> Int {
  // Java-style rolling 31x hash with explicit modulo per step so
  // intermediate values stay below JavaScript's 2^53 safe-integer
  // ceiling. The modulus is the Mersenne prime 2^31 - 1, giving
  // ~32-bit-wide UIDs that match on both Erlang and JavaScript
  // targets without depending on bitwise primitives the BEAM
  // exposes one way and JS another.
  let codepoints = string.to_utf_codepoints(value)
  list.fold(codepoints, 0, fn(acc, codepoint) {
    let byte = string.utf_codepoint_to_int(codepoint)
    int.modulo(acc * 31 + byte, by: 2_147_483_647) |> result.unwrap(0)
  })
}

fn escape_wifi(value: String) -> String {
  // Per the Apple Engineering / ZXing WIFI URI grammar, the reserved characters
  // are backslash, semicolon, comma, colon, and double quote. Escape backslash
  // first to avoid double-escaping the prefixes we add below.
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: ";", with: "\\;")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ":", with: "\\:")
  |> string.replace(each: "\"", with: "\\\"")
}

fn option_line_with(
  key: String,
  value: Option(String),
  escape: fn(String) -> String,
) -> Option(String) {
  case value {
    Some(value) -> Some(key <> ":" <> escape(value))
    None -> None
  }
}

fn encode_addr_spec(value: String) -> String {
  // RFC 6068 §2 addr-spec encoder for the `to` field of a `mailto:`
  // URI. The `@` separator between local-part and domain, the `,`
  // separator between addr-specs, and the `some-delims` set
  // (`!` / `$` / `'` / `(` / `)` / `*` / `+` / `;` / `:`) are kept
  // literal; only characters that would actually break URI parsing
  // in this position — space, `?`, `&`, `#`, `<`, `>`, control bytes,
  // and any non-ASCII codepoint — are percent-encoded. Encoding goes
  // codepoint-by-codepoint so the same output is produced on both the
  // Erlang and JavaScript targets, and so multi-byte UTF-8 sequences
  // are expanded to one `%XX` per UTF-8 byte (RFC 3986 §2.5).
  value
  |> string.to_utf_codepoints
  |> list.map(encode_addr_spec_codepoint)
  |> string.concat
}

fn encode_addr_spec_codepoint(codepoint: UtfCodepoint) -> String {
  let cp = string.utf_codepoint_to_int(codepoint)
  case cp < 128 && is_addr_spec_literal_ascii(cp) {
    True -> codepoint_to_string(codepoint)
    False -> percent_encode_codepoint_utf8(cp)
  }
}

fn codepoint_to_string(codepoint: UtfCodepoint) -> String {
  string.from_utf_codepoints([codepoint])
}

fn is_addr_spec_literal_ascii(cp: Int) -> Bool {
  // ALPHA / DIGIT / unreserved (`-` `.` `_` `~`) plus the structural
  // separators of RFC 6068 §2 addr-spec list (`@`, `,`) and the
  // some-delims set (`!`, `$`, `'`, `(`, `)`, `*`, `+`, `;`, `:`)
  // stay literal. Everything else — including space, `?`, `&`, `#`,
  // `<`, `>`, `"`, `[`, `]`, `\`, `/`, `=`, and any control byte —
  // is percent-encoded.
  is_alpha(cp)
  || is_digit(cp)
  || is_unreserved_punct(cp)
  || is_addr_spec_separator(cp)
  || is_some_delim(cp)
}

fn is_alpha(cp: Int) -> Bool {
  { cp >= 0x41 && cp <= 0x5A } || { cp >= 0x61 && cp <= 0x7A }
}

fn is_digit(cp: Int) -> Bool {
  cp >= 0x30 && cp <= 0x39
}

fn is_unreserved_punct(cp: Int) -> Bool {
  // RFC 3986 §2.3 unreserved punctuation: `-` `.` `_` `~`.
  cp == 0x2D || cp == 0x2E || cp == 0x5F || cp == 0x7E
}

fn is_addr_spec_separator(cp: Int) -> Bool {
  // RFC 6068 §2: `@` separates local-part from domain, `,` separates
  // addr-specs in a list.
  cp == 0x40 || cp == 0x2C
}

fn is_some_delim(cp: Int) -> Bool {
  // RFC 6068 §2 some-delims = "!" / "$" / "'" / "(" / ")" / "*" /
  // "+" / ";" / ":". (`,` and `@` are handled by
  // `is_addr_spec_separator` above so this set is the rest.)
  cp == 0x21
  || cp == 0x24
  || cp == 0x27
  || cp == 0x28
  || cp == 0x29
  || cp == 0x2A
  || cp == 0x2B
  || cp == 0x3B
  || cp == 0x3A
}

fn percent_encode_codepoint_utf8(cp: Int) -> String {
  // Expand the codepoint to its UTF-8 bytes (RFC 3629) and emit
  // `%XX` for each. ASCII (`cp < 0x80`) falls through the 1-byte
  // branch so the same routine handles both ASCII characters that
  // need escaping (e.g. space → `%20`) and non-ASCII codepoints.
  case cp < 0x80, cp < 0x800, cp < 0x10000 {
    True, _, _ -> to_hex_byte(cp)
    _, True, _ -> to_hex_byte(0xC0 + cp / 64) <> to_hex_byte(0x80 + cp % 64)
    _, _, True ->
      to_hex_byte(0xE0 + cp / 4096)
      <> to_hex_byte(0x80 + cp / 64 % 64)
      <> to_hex_byte(0x80 + cp % 64)
    _, _, _ ->
      to_hex_byte(0xF0 + cp / 262_144)
      <> to_hex_byte(0x80 + cp / 4096 % 64)
      <> to_hex_byte(0x80 + cp / 64 % 64)
      <> to_hex_byte(0x80 + cp % 64)
  }
}

fn to_hex_byte(byte: Int) -> String {
  "%" <> string.pad_start(int.to_base16(byte), to: 2, with: "0")
}

fn escape_text(value: String) -> String {
  // vCard (RFC 2426 §2.4.2) and iCalendar (RFC 5545 §3.3.11) share the
  // TEXT-value rules. Strip raw CR and NUL, which neither allows, then
  // escape the four reserved characters, backslash first so the later
  // escapes are not escaped again.
  value
  |> string.replace(each: "\r", with: "")
  |> string.replace(each: "\u{0000}", with: "")
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\n", with: "\\n")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ";", with: "\\;")
}

// Splits a line longer than 75 octets into runs joined by CRLF and a space,
// at grapheme boundaries so a UTF-8 sequence is never cut.
fn fold_line(line: String) -> String {
  case string.byte_size(line) <= 75 {
    True -> line
    False -> fold_line_loop(string.to_graphemes(line), 0, [], [])
  }
}

fn fold_line_loop(
  graphemes: List(String),
  current_bytes: Int,
  current_acc: List(String),
  folded_acc: List(String),
) -> String {
  case graphemes {
    [] -> {
      let last = string.concat(list.reverse(current_acc))
      let parts = list.reverse([last, ..folded_acc])
      string.join(parts, with: "\r\n ")
    }
    [head, ..tail] -> {
      let head_bytes = string.byte_size(head)
      case current_bytes + head_bytes > 75 {
        True -> {
          let chunk = string.concat(list.reverse(current_acc))
          fold_line_loop(tail, head_bytes, [head], [chunk, ..folded_acc])
        }
        False ->
          fold_line_loop(
            tail,
            current_bytes + head_bytes,
            [head, ..current_acc],
            folded_acc,
          )
      }
    }
  }
}

fn clamp_year(year: Int) -> Int {
  // RFC 5545 §3.3.5 fixes the year at 4 digits. Values outside
  // `[1, 9999]` are clamped rather than emitted with a 5-digit or
  // negative year that breaks the fixed-width format.
  case year < 1, year > 9999 {
    True, _ -> 1
    _, True -> 9999
    _, _ -> year
  }
}

fn pad(value: Int, width: Int) -> String {
  string.pad_start(int.to_string(value), to: width, with: "0")
}
