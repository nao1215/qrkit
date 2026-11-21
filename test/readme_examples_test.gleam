//// Tests the code blocks in `README.md` and the usage samples that used to
//// live there. Keep the README blocks and the `readme_` functions in step.

import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import gleeunit/should
import qrkit

// ---------------------------------------------------------------------------
// README: Hello, QR
// ---------------------------------------------------------------------------

fn readme_hello_qr() -> qrkit.QrCode {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  qr
}

pub fn readme_hello_qr_test() -> Nil {
  let qr = readme_hello_qr()
  qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 4)
  |> string.is_empty
  |> should.be_false
}

// ---------------------------------------------------------------------------
// README: Options for ECC, exact version, and ECI
// ---------------------------------------------------------------------------

fn readme_high_density_qr() -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.encode_with(
      "https://github.com/sponsors/nao1215",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Quartile,
        version: Some(4),
        eci: Some(26),
      ),
    )
  qr
}

pub fn readme_high_density_qr_test() -> Nil {
  let qr = readme_high_density_qr()
  qr.error_correction
  |> should.equal(qrkit.Quartile)
  // `version: Some(4)` pins the symbol version.
  qr.version
  |> should.equal(4)
}

// ---------------------------------------------------------------------------
// README: Render as SVG
// ---------------------------------------------------------------------------

fn readme_render_svg() -> String {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  qrkit.to_svg(qr, qrkit.default_image_options())
}

pub fn readme_render_svg_test() -> Nil {
  let xml = readme_render_svg()
  string.starts_with(xml, "<svg")
  |> should.be_true
  string.contains(does: xml, contain: "path")
  |> should.be_true
}

fn readme_dark_themed_svg() -> String {
  let options =
    qrkit.ImageOptions(
      module_size: 12,
      margin: 2,
      dark_color: "#22d3ee",
      light_color: Some("#0f172a"),
    )

  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  qrkit.to_svg(qr, options)
}

pub fn readme_dark_themed_svg_test() -> Nil {
  let xml = readme_dark_themed_svg()
  string.contains(does: xml, contain: "#22d3ee")
  |> should.be_true
  string.contains(does: xml, contain: "#0f172a")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: PNG
// ---------------------------------------------------------------------------

fn readme_render_png_bytes() -> BitArray {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  qrkit.to_png(qr, qrkit.default_image_options())
}

pub fn readme_render_png_bytes_test() -> Nil {
  let bytes = readme_render_png_bytes()
  let assert Ok(signature) = bit_array.slice(bytes, at: 0, take: 8)
  signature
  |> should.equal(<<137, 80, 78, 71, 13, 10, 26, 10>>)
}

// ---------------------------------------------------------------------------
// README: ASCII compact
// ---------------------------------------------------------------------------

fn readme_compact_qr() -> String {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  qrkit.to_terminal(qr, style: qrkit.HalfBlocks, margin: 4)
}

pub fn readme_compact_qr_test() -> Nil {
  // Pin the exact terminal output shown in the README so the docs never drift
  // from what users see when they run the snippet.
  readme_compact_qr()
  |> should.equal(string.join(
    [
      "                                     ",
      "                                     ",
      "    █▀▀▀▀▀█ ▄ ▀ █▄▀  ▀██▄ █▀▀▀▀▀█    ",
      "    █ ███ █  █▄▀█▄ ▀  █▀  █ ███ █    ",
      "    █ ▀▀▀ █ ▀█ ▀▄▀▄▄▀  █  █ ▀▀▀ █    ",
      "    ▀▀▀▀▀▀▀ ▀ ▀ █ ▀▄▀▄█▄▀ ▀▀▀▀▀▀▀    ",
      "    █▄▀▄▀▄▀▄ █▀▀▀▄ ▄▄▀  ▄ ▄ ▀▄ ▀▄    ",
      "    █▄▄ ▄ ▀█  ▀▀█▄█▄ █▄  ▀▀▄█ ▀█▀    ",
      "    ▄▄▀▀  ▀█ ▄▄ █ █▀▄█▄ ▄██  █ ▀█    ",
      "     ▄█▀▄▄▀ ▀▀▀▀ ▀ ▄▀█▀ ▄▄█ ▀█ █▀    ",
      "    ▀▀▀▄▄▀▀ ▄▀█▀ ▄ ▄ █▄▀▀▄█▀ █▄▀█    ",
      "    ▀▄▀▀▄█▀▀ ▀▀ ▄▄█▄▀██▄▄█▄██▄ █▀    ",
      "    ▀  ▀▀▀▀ █▀▀▀  █▄ ▀▀██▀▀▀█ ▄▄▄    ",
      "    █▀▀▀▀▀█  ██▀▄▀  ▄█▄▀█ ▀ ██ ▀█    ",
      "    █ ███ █ ▀▀█▀█▄ ▀█▀  █▀▀██ ▄▀     ",
      "    █ ▀▀▀ █ ▀█▄▄█  ▄ █ █▄▄ ▀█▀ ▄▀    ",
      "    ▀▀▀▀▀▀▀ ▀   ▀ ▀ ▀▀ ▀▀▀ ▀▀  ▀▀    ",
      "                                     ",
      "                                     ",
    ],
    with: "\n",
  ))
}

// ---------------------------------------------------------------------------
// README: WiFi
// ---------------------------------------------------------------------------

fn readme_wifi_qr_svg() -> String {
  let payload =
    qrkit.wifi(ssid: "MyAP", security: qrkit.Wpa2("secret"), hidden: False)
  let assert Ok(qr) = qrkit.encode(payload)
  qrkit.to_svg(qr, qrkit.default_image_options())
}

pub fn readme_wifi_qr_svg_test() -> Nil {
  string.starts_with(readme_wifi_qr_svg(), "<svg")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: vCard, email, SMS, phone, geo
// ---------------------------------------------------------------------------

fn readme_contact_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.VCard(
    ..qrkit.vcard("Naohiro Chikamatsu"),
    email: Some("nao@example.com"),
    phone: Some("+81-90-0000-0000"),
    url: Some("https://github.com/nao1215"),
  )
  |> qrkit.vcard_to_string
  |> qrkit.encode
}

fn readme_mail_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.email(to: "you@example.com", subject: "Hi", body: "Quick note")
  |> qrkit.encode
}

fn readme_sms_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.sms(to: "+819000000000", body: "Hello!") |> qrkit.encode
}

fn readme_phone_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.phone("+819000000000") |> qrkit.encode
}

fn readme_map_pin_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.geo(latitude: 35.6812, longitude: 139.7671) |> qrkit.encode
}

pub fn readme_content_helpers_test() -> Nil {
  let assert Ok(_) = readme_contact_qr()
  let assert Ok(_) = readme_mail_qr()
  let assert Ok(_) = readme_sms_qr()
  let assert Ok(_) = readme_phone_qr()
  let assert Ok(_) = readme_map_pin_qr()
  Nil
}

// ---------------------------------------------------------------------------
// README: Calendar
// ---------------------------------------------------------------------------

fn readme_meeting_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  // 2026-05-14 10:00 UTC, ends 11:00 UTC.
  let time =
    qrkit.Timed(
      start: timestamp.from_unix_seconds(1_778_752_800),
      end: timestamp.from_unix_seconds(1_778_756_400),
    )
  qrkit.CalendarEvent(
    ..qrkit.calendar_event("Sync", time),
    location: Some("Online"),
    description: Some("Project sync meeting"),
  )
  |> qrkit.calendar_event_to_string
  |> qrkit.encode_with(
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      error_correction: qrkit.Low,
    ),
  )
}

pub fn readme_meeting_qr_test() -> Nil {
  let assert Ok(_) = readme_meeting_qr()
  Nil
}

pub fn readme_meeting_qr_payload_matches_documented_times_test() -> Nil {
  // Payload now CRLF-terminated and carries the RFC-required
  // PRODID / UID / DTSTAMP properties (qrkit content #12, #14).
  qrkit.CalendarEvent(
    ..qrkit.calendar_event(
      "Sync",
      qrkit.Timed(
        timestamp.from_unix_seconds(1_778_752_800),
        timestamp.from_unix_seconds(1_778_756_400),
      ),
    ),
    location: Some("Online"),
    description: Some("Project sync meeting"),
  )
  |> qrkit.calendar_event_to_string
  |> should.equal(
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//nao1215//qrkit//EN\r\nBEGIN:VEVENT\r\nUID:2592443-1778752800-1778756400@qrkit.nao1215\r\nDTSTAMP:20260514T100000Z\r\nSUMMARY:Sync\r\nDTSTART:20260514T100000Z\r\nDTEND:20260514T110000Z\r\nLOCATION:Online\r\nDESCRIPTION:Project sync meeting\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
  )
}

// ---------------------------------------------------------------------------
// README: Decode a module matrix
// ---------------------------------------------------------------------------

fn readme_round_trip() -> Result(String, qrkit.DecodeError) {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  case qrkit.decode(qr.rows) {
    Ok(decoded) -> Ok(decoded.text)
    Error(error) -> Error(error)
  }
}

pub fn readme_round_trip_test() -> Nil {
  readme_round_trip()
  |> should.equal(Ok("https://github.com/sponsors/nao1215"))
}

// ---------------------------------------------------------------------------
// README: Micro QR
// ---------------------------------------------------------------------------

fn readme_business_card_qr() -> String {
  let assert Ok(qr) =
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        version: Some(2),
        error_correction: qrkit.Low,
      ),
    )

  qrkit.to_svg(qr, qrkit.default_image_options())
}

pub fn readme_business_card_qr_test() -> Nil {
  string.starts_with(readme_business_card_qr(), "<svg")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: rMQR
// ---------------------------------------------------------------------------

fn readme_label_qr() -> String {
  let assert Ok(qr) =
    qrkit.encode_with(
      "https://github.com/sponsors/nao1215",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        error_correction: qrkit.Medium,
        rectangular_priority: qrkit.ShortestHeight,
      ),
    )

  qrkit.to_svg(qr, qrkit.default_image_options())
}

pub fn readme_label_qr_test() -> Nil {
  string.starts_with(readme_label_qr(), "<svg")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: Structured Append
// ---------------------------------------------------------------------------

fn readme_split_long_message() -> List(String) {
  let payload = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

  let assert Ok(shards) =
    qrkit.encode_split(payload, max_version: 2, error_correction: qrkit.Medium)
  list.map(shards, qrkit.to_terminal(_, style: qrkit.Blocks, margin: 4))
}

pub fn readme_split_long_message_test() -> Nil {
  let shards = readme_split_long_message()
  { list.length(shards) >= 2 }
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: Force byte mode
// ---------------------------------------------------------------------------

fn readme_raw_byte_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.encode_with(
    "123-ABC",
    qrkit.EncodeOptions(..qrkit.default_encode_options(), mode: qrkit.ForceByte),
  )
}

pub fn readme_raw_byte_qr_test() -> Nil {
  let assert Ok(_) = readme_raw_byte_qr()
  Nil
}

// ---------------------------------------------------------------------------
// README: Errors
// ---------------------------------------------------------------------------

fn readme_rejected() -> Bool {
  case qrkit.encode("") {
    Error(qrkit.EmptyInput) -> True
    _ -> False
  }
}

pub fn readme_rejected_test() -> Nil {
  readme_rejected()
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: the first example and the options example
// ---------------------------------------------------------------------------

fn readme_label() -> Result(String, qrkit.EncodeError) {
  let options =
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Rectangular,
      rectangular_priority: qrkit.ShortestHeight,
    )
  case qrkit.encode_with("https://github.com/sponsors/nao1215", options) {
    Ok(qr) ->
      Ok(qrkit.to_svg(
        qr,
        qrkit.ImageOptions(..qrkit.default_image_options(), light_color: None),
      ))
    Error(error) -> Error(error)
  }
}

pub fn readme_label_test() -> Nil {
  let assert Ok(svg) = readme_label()
  assert string.starts_with(svg, "<svg")
  assert !string.contains(svg, "#ffffff")
}

pub fn readme_half_blocks_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  let text = qrkit.to_terminal(qr, style: qrkit.HalfBlocks, margin: 4)
  assert string.contains(text, "▀")
}
