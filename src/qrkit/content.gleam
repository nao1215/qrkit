//// Domain-specific helpers that produce QR-ready payload strings.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

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

/// Render the vCard as a text payload.
pub fn vcard_to_string(card: VCard) -> String {
  let VCard(name, phone, email, url, organization, title, address) = card
  [
    Some("BEGIN:VCARD"),
    Some("VERSION:3.0"),
    option_line("N", name),
    option_line("FN", name),
    option_line("ORG", organization),
    option_line("TITLE", title),
    option_line("TEL", phone),
    option_line("EMAIL", email),
    option_line("URL", url),
    option_line("ADR", address),
    Some("END:VCARD"),
  ]
  |> present_lines([])
  |> string.join(with: "\n")
}

/// Build a `mailto:` payload.
pub fn email(
  to to: String,
  subject subject: String,
  body body: String,
) -> String {
  "mailto:"
  <> to
  <> "?subject="
  <> url_encode(subject)
  <> "&body="
  <> url_encode(body)
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
pub fn event(title: String, start_unix: Int, end_unix: Int) -> CalendarEvent {
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

/// Render a calendar event as an iCalendar payload.
pub fn event_to_string(event: CalendarEvent) -> String {
  let CalendarEvent(title, start_unix, end_unix, location, description, all_day) =
    event
  let start_value = format_datetime(start_unix, all_day)
  let end_value = format_datetime(end_unix, all_day)
  let start_key = case all_day {
    True -> "DTSTART;VALUE=DATE"
    False -> "DTSTART"
  }
  let end_key = case all_day {
    True -> "DTEND;VALUE=DATE"
    False -> "DTEND"
  }
  [
    Some("BEGIN:VCALENDAR"),
    Some("VERSION:2.0"),
    Some("BEGIN:VEVENT"),
    Some("SUMMARY:" <> escape_ical(title)),
    Some(start_key <> ":" <> start_value),
    Some(end_key <> ":" <> end_value),
    option_line("LOCATION", location),
    option_line("DESCRIPTION", description),
    Some("END:VEVENT"),
    Some("END:VCALENDAR"),
  ]
  |> present_lines([])
  |> string.join(with: "\n")
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
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: ";", with: "\\;")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ":", with: "\\:")
}

fn option_line(key: String, value: Option(String)) -> Option(String) {
  case value {
    Some(value) -> Some(key <> ":" <> value)
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

fn url_encode(value: String) -> String {
  value
  |> string.replace(each: " ", with: "%20")
  |> string.replace(each: "\n", with: "%0A")
}

fn escape_ical(value: String) -> String {
  value
  |> string.replace(each: "\\", with: "\\\\")
  |> string.replace(each: "\n", with: "\\n")
  |> string.replace(each: ",", with: "\\,")
  |> string.replace(each: ";", with: "\\;")
}

fn format_datetime(unix: Int, all_day: Bool) -> String {
  let #(year, month, day, hour, minute, second) = unix_to_utc(unix)
  case all_day {
    True -> pad(year, 4) <> pad(month, 2) <> pad(day, 2)
    False ->
      pad(year, 4)
      <> pad(month, 2)
      <> pad(day, 2)
      <> "T"
      <> pad(hour, 2)
      <> pad(minute, 2)
      <> pad(second, 2)
      <> "Z"
  }
}

fn unix_to_utc(unix: Int) -> #(Int, Int, Int, Int, Int, Int) {
  let days = unix / 86_400
  let seconds_of_day = unix % 86_400
  let #(year, month, day) = civil_from_days(days)
  let hour = seconds_of_day / 3600
  let minute = { seconds_of_day % 3600 } / 60
  let second = seconds_of_day % 60
  #(year, month, day, hour, minute, second)
}

fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + 719_468
  let era = z / 146_097
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
