//// Domain-specific helpers that produce QR-ready payload strings.
////
//// iCalendar and vCard renderers in this module follow RFC 5545 and
//// RFC 2426 to the byte level:
////
//// - Lines are terminated with `CRLF` (`\r\n`) (RFC 5545 §3.1,
////   RFC 2426 §2.1).
//// - Lines longer than 75 octets are folded with `CRLF<space>`
////   (RFC 5545 §3.1, RFC 2426 §2.6). Folding is byte-based and
////   does not split inside a multi-byte UTF-8 sequence.
//// - TEXT-value escape helpers strip raw `CR` and `NUL` and escape
////   `\`, `\n`, `,`, `;` (RFC 5545 §3.3.11, RFC 2426 §2.4.2).
//// - `event_to_string` emits the RFC-required `PRODID` (VCALENDAR-
////   level) plus `UID` and `DTSTAMP` (VEVENT-level). `UID` is
////   derived deterministically from the event's title and timestamps
////   so the same event produces the same UID across runs; `DTSTAMP`
////   defaults to the event's `start_unix` (no clock is available in
////   a pure rendering function).
//// - `event_to_string` in `all_day` mode bumps `DTEND` to
////   `start_date + 1 day` when the caller passed `end_unix ==
////   start_unix`, matching RFC 5545 §3.6.1's non-inclusive-end
////   requirement for DATE-valued events.
//// - `vcard_to_string` always emits the RFC 2426 MANDATORY `N` and
////   `FN` properties; when the caller did not set a name they are
////   emitted with empty values (`N:;;;;` and `FN:`) so the
////   structure is still RFC-conformant.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri

/// Return a URL payload unchanged.
pub fn url(href: String) -> String {
  href
}

pub type WifiSecurity {
  Open
  Wep
  Wpa
  Wpa2
  Wpa3
}

/// Build a WiFi payload string.
pub fn wifi(
  ssid ssid: String,
  password password: String,
  security security: WifiSecurity,
  hidden hidden: Bool,
) -> String {
  let base =
    "WIFI:T:"
    <> wifi_security_name(security)
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

pub opaque type VCard {
  VCard(
    name: Option(String),
    phone: Option(String),
    email: Option(String),
    url: Option(String),
    organization: Option(String),
    title: Option(String),
    address: Option(String),
  )
}

/// Create an empty vCard builder.
pub fn vcard() -> VCard {
  VCard(None, None, None, None, None, None, None)
}

/// Set the display name.
pub fn with_name(card: VCard, name: String) -> VCard {
  let VCard(_, phone, email, url, organization, title, address) = card
  VCard(Some(name), phone, email, url, organization, title, address)
}

/// Set the phone number.
pub fn with_phone(card: VCard, phone: String) -> VCard {
  let VCard(name, _, email, url, organization, title, address) = card
  VCard(name, Some(phone), email, url, organization, title, address)
}

/// Set the e-mail address.
pub fn with_email(card: VCard, email: String) -> VCard {
  let VCard(name, phone, _, url, organization, title, address) = card
  VCard(name, phone, Some(email), url, organization, title, address)
}

/// Set the URL field.
pub fn with_url(card: VCard, url: String) -> VCard {
  let VCard(name, phone, email, _, organization, title, address) = card
  VCard(name, phone, email, Some(url), organization, title, address)
}

/// Set the organization field.
pub fn with_organization(card: VCard, org: String) -> VCard {
  let VCard(name, phone, email, url, _, title, address) = card
  VCard(name, phone, email, url, Some(org), title, address)
}

/// Set the title field.
pub fn with_title(card: VCard, title: String) -> VCard {
  let VCard(name, phone, email, url, organization, _, address) = card
  VCard(name, phone, email, url, organization, Some(title), address)
}

/// Set the address field.
pub fn with_address(card: VCard, address: String) -> VCard {
  let VCard(name, phone, email, url, organization, title, _) = card
  VCard(name, phone, email, url, organization, title, Some(address))
}

/// Render the vCard as a text payload, RFC 2426 conformant.
///
/// The mandatory `N` and `FN` properties are always emitted —
/// when no name was set via [`with_name`](#with_name) they are
/// emitted with empty values (`N:;;;;` and `FN:`) so the structure
/// matches RFC 2426 §3.1.1 / §3.1.2. Lines are CRLF-terminated and
/// folded at 75 octets per RFC 2426 §2.1 / §2.6.
pub fn vcard_to_string(card: VCard) -> String {
  let VCard(name, phone, email, url, organization, title, address) = card
  let n_value = case name {
    Some(n) -> escape_vcard(n)
    None -> ";;;;"
  }
  let fn_value = case name {
    Some(n) -> escape_vcard(n)
    None -> ""
  }
  [
    Some("BEGIN:VCARD"),
    Some("VERSION:3.0"),
    Some("N:" <> n_value),
    Some("FN:" <> fn_value),
    option_line_with("ORG", organization, escape_vcard),
    option_line_with("TITLE", title, escape_vcard),
    option_line_with("TEL", phone, escape_vcard),
    option_line_with("EMAIL", email, escape_vcard),
    option_line_with("URL", url, escape_vcard),
    option_line_with("ADR", address, escape_vcard),
    Some("END:VCARD"),
  ]
  |> present_lines([])
  |> list.map(fold_line)
  |> string.join(with: "\r\n")
}

/// Build a `mailto:` payload, percent-encoding every parameter
/// including the `to` addr-spec.
pub fn email(
  to to: String,
  subject subject: String,
  body body: String,
) -> String {
  "mailto:"
  <> percent_encode(to)
  <> "?subject="
  <> percent_encode(subject)
  <> "&body="
  <> percent_encode(body)
}

/// Build an SMS payload.
pub fn sms(to to: String, body body: String) -> String {
  "SMSTO:" <> to <> ":" <> body
}

/// Build a geo URI.
pub fn geo(latitude latitude: Float, longitude longitude: Float) -> String {
  "geo:" <> float.to_string(latitude) <> "," <> float.to_string(longitude)
}

/// Build a phone URI.
pub fn phone(number: String) -> String {
  "tel:" <> number
}

pub opaque type CalendarEvent {
  CalendarEvent(
    title: String,
    start_unix: Int,
    end_unix: Int,
    location: Option(String),
    description: Option(String),
    all_day: Bool,
  )
}

/// Create a calendar event payload builder.
pub fn event(
  title title: String,
  start_unix start_unix: Int,
  end_unix end_unix: Int,
) -> CalendarEvent {
  CalendarEvent(title, start_unix, end_unix, None, None, False)
}

/// Set the event location.
pub fn with_location(event: CalendarEvent, loc: String) -> CalendarEvent {
  let CalendarEvent(title, start_unix, end_unix, _, description, all_day) =
    event
  CalendarEvent(title, start_unix, end_unix, Some(loc), description, all_day)
}

/// Set the event description.
pub fn with_description(event: CalendarEvent, desc: String) -> CalendarEvent {
  let CalendarEvent(title, start_unix, end_unix, location, _, all_day) = event
  CalendarEvent(title, start_unix, end_unix, location, Some(desc), all_day)
}

/// Toggle all-day rendering.
pub fn with_all_day(event: CalendarEvent, all_day: Bool) -> CalendarEvent {
  let CalendarEvent(title, start_unix, end_unix, location, description, _) =
    event
  CalendarEvent(title, start_unix, end_unix, location, description, all_day)
}

/// Render a calendar event as an iCalendar payload, RFC 5545
/// conformant. Includes the required `PRODID` / `UID` / `DTSTAMP`
/// properties (#14). In `all_day` mode `DTEND` is bumped to
/// `start + 1 day` when the caller passed `end_unix == start_unix`
/// so the resulting DATE range is non-inclusive per §3.6.1 (#16).
/// Unix timestamps before the epoch are floor-divided so negative
/// inputs format correctly (#9), and the year is clamped to
/// `[1, 9999]` to preserve the 4-digit-year fixed-width format
/// (#10).
pub fn event_to_string(event: CalendarEvent) -> String {
  let CalendarEvent(title, start_unix, end_unix, location, description, all_day) =
    event
  let effective_end = adjust_end_for_all_day(start_unix, end_unix, all_day)
  let start_value = format_datetime(start_unix, all_day)
  let end_value = format_datetime(effective_end, all_day)
  let start_key = case all_day {
    True -> "DTSTART;VALUE=DATE"
    False -> "DTSTART"
  }
  let end_key = case all_day {
    True -> "DTEND;VALUE=DATE"
    False -> "DTEND"
  }
  let uid = synthesise_uid(title, start_unix, end_unix)
  let dtstamp = format_datetime(start_unix, False)
  [
    Some("BEGIN:VCALENDAR"),
    Some("VERSION:2.0"),
    Some("PRODID:-//nao1215//qrkit//EN"),
    Some("BEGIN:VEVENT"),
    Some("UID:" <> uid),
    Some("DTSTAMP:" <> dtstamp),
    Some("SUMMARY:" <> escape_ical(title)),
    Some(start_key <> ":" <> start_value),
    Some(end_key <> ":" <> end_value),
    option_line_with("LOCATION", location, escape_ical),
    option_line_with("DESCRIPTION", description, escape_ical),
    Some("END:VEVENT"),
    Some("END:VCALENDAR"),
  ]
  |> present_lines([])
  |> list.map(fold_line)
  |> string.join(with: "\r\n")
}

fn adjust_end_for_all_day(start_unix: Int, end_unix: Int, all_day: Bool) -> Int {
  case all_day && end_unix <= start_unix {
    True -> start_unix + 86_400
    False -> end_unix
  }
}

fn synthesise_uid(title: String, start_unix: Int, end_unix: Int) -> String {
  // Deterministic UID: title hash (Erlang :phash2-compatible mix in
  // pure Gleam) combined with the two timestamps. Stable across runs
  // for the same input, which is what a QR-payload caller wants —
  // scanning the same event twice should not produce a new UID.
  let title_hash = string_hash(title)
  int.to_string(title_hash)
  <> "-"
  <> int.to_string(start_unix)
  <> "-"
  <> int.to_string(end_unix)
  <> "@qrkit.nao1215"
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
    modulo(acc * 31 + byte, 2_147_483_647)
  })
}

fn modulo(value: Int, m: Int) -> Int {
  let r = value % m
  case r < 0 {
    True -> r + m
    False -> r
  }
}

fn wifi_security_name(security: WifiSecurity) -> String {
  case security {
    Open -> "nopass"
    Wep -> "WEP"
    Wpa -> "WPA"
    Wpa2 -> "WPA2"
    Wpa3 -> "WPA3"
  }
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

fn present_lines(lines: List(Option(String)), acc: List(String)) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [Some(line), ..rest] -> present_lines(rest, [line, ..acc])
    [None, ..rest] -> present_lines(rest, acc)
  }
}

fn percent_encode(value: String) -> String {
  uri.percent_encode(value)
}

fn escape_vcard(value: String) -> String {
  // Strip raw CR and NUL (RFC 2426 §2.4.2 forbids them in TEXT
  // values), then escape the four reserved characters in spec
  // order — backslash first so subsequent escapes are not
  // double-escaped.
  value
  |> string.replace(each: "\r", with: "")
  |> string.replace(each: "\u{0000}", with: "")
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\n", with: "\\n")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ";", with: "\\;")
}

fn escape_ical(value: String) -> String {
  // Same TEXT-value rules as vCard (RFC 5545 §3.3.11): strip raw CR
  // and NUL before escaping the reserved set.
  value
  |> string.replace(each: "\r", with: "")
  |> string.replace(each: "\u{0000}", with: "")
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\n", with: "\\n")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ";", with: "\\;")
}

/// Fold one logical content line per RFC 5545 §3.1 / RFC 2426 §2.6:
/// a line longer than 75 octets is split into 75-octet runs joined
/// by `CRLF<space>`. Folding is performed at grapheme boundaries
/// rather than raw bytes so multi-byte UTF-8 sequences are never
/// split. The single-line case is a fast path that returns the
/// input unchanged.
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

fn format_datetime(unix: Int, all_day: Bool) -> String {
  let #(year, month, day, hour, minute, second) = unix_to_utc(unix)
  let year_clamped = clamp_year(year)
  case all_day {
    True -> pad(year_clamped, 4) <> pad(month, 2) <> pad(day, 2)
    False ->
      pad(year_clamped, 4)
      <> pad(month, 2)
      <> pad(day, 2)
      <> "T"
      <> pad(hour, 2)
      <> pad(minute, 2)
      <> pad(second, 2)
      <> "Z"
  }
}

fn clamp_year(year: Int) -> Int {
  // RFC 5545 §3.3.5 fixes the year at 4 digits. Values outside
  // `[1, 9999]` are clamped rather than emitted with a 5-digit
  // year that breaks the fixed-width format (#10). Negative-input
  // overflow (#9) is bounded by `floor_div` upstream so this
  // mostly handles the Y10K side.
  case year < 1, year > 9999 {
    True, _ -> 1
    _, True -> 9999
    _, _ -> year
  }
}

fn unix_to_utc(unix: Int) -> #(Int, Int, Int, Int, Int, Int) {
  // Floor-divide so negative `unix` values produce non-negative
  // sub-day components — Gleam's `/` and `%` truncate toward zero,
  // which leaks negatives into the hour/minute/second components
  // for any pre-epoch input (#9).
  let days = floor_div(unix, 86_400)
  let seconds_of_day = floor_mod(unix, 86_400)
  let #(year, month, day) = civil_from_days(days)
  let hour = seconds_of_day / 3600
  let minute = { seconds_of_day % 3600 } / 60
  let second = seconds_of_day % 60
  #(year, month, day, hour, minute, second)
}

fn floor_div(a: Int, b: Int) -> Int {
  let q = a / b
  let r = a - q * b
  case r != 0 && { r < 0 } != { b < 0 } {
    True -> q - 1
    False -> q
  }
}

fn floor_mod(a: Int, b: Int) -> Int {
  let r = a % b
  case r != 0 && { r < 0 } != { b < 0 } {
    True -> r + b
    False -> r
  }
}

fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + 719_468
  let era = floor_div(z, 146_097)
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let y = yoe + era * 400
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day = doy - { 153 * mp + 2 } / 5 + 1
  let month =
    mp
    + case mp < 10 {
      True -> 3
      False -> -9
    }
  let year =
    y
    + case month <= 2 {
      True -> 1
      False -> 0
    }
  #(year, month, day)
}

fn pad(value: Int, width: Int) -> String {
  let text = int.to_string(value)
  let zeros = width - string.length(text)
  case zeros <= 0 {
    True -> text
    False -> string.repeat("0", zeros) <> text
  }
}
