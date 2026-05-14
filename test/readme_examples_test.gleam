//// Tests every code block in `README.md`. Each function below corresponds
//// directly to a sample in the README — if you change the README, update
//// these tests in lock-step.

import gleam/bit_array
import gleam/list
import gleam/string
import gleeunit/should
import qrkit
import qrkit/content
import qrkit/error
import qrkit/render/ascii
import qrkit/render/png
import qrkit/render/svg

// ---------------------------------------------------------------------------
// README: Hello, QR
// ---------------------------------------------------------------------------

fn readme_hello_qr() -> qrkit.QrCode {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  qr
}

pub fn readme_hello_qr_test() -> Nil {
  let qr = readme_hello_qr()
  ascii.to_string(qr)
  |> string.is_empty
  |> should.be_false
}

// ---------------------------------------------------------------------------
// README: Builder for ECC, version, and ECI
// ---------------------------------------------------------------------------

fn readme_high_density_qr() -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_ecc(error.Quartile)
    |> qrkit.with_min_version(3)
    |> qrkit.with_eci(26)
    |> qrkit.build()
  qr
}

pub fn readme_high_density_qr_test() -> Nil {
  let qr = readme_high_density_qr()
  qrkit.error_correction(qr)
  |> should.equal(error.Quartile)
  { qrkit.version(qr) >= 3 }
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: Render as SVG
// ---------------------------------------------------------------------------

fn readme_render_svg() -> String {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  svg.to_string(qr, svg.default_options())
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
    svg.default_options()
    |> svg.with_module_size(12)
    |> svg.with_margin(2)
    |> svg.with_dark_color("#22d3ee")
    |> svg.with_light_color("#0f172a")
    |> svg.with_background(True)

  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  svg.to_string(qr, options)
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
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  png.to_bit_array(qr, scale: 8, margin: 4)
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
  let assert Ok(qr) = qrkit.encode("HELLO")
  ascii.to_string_compact(qr)
}

pub fn readme_compact_qr_test() -> Nil {
  let text = readme_compact_qr()
  string.is_empty(text)
  |> should.be_false
  string.contains(does: text, contain: "▀")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: WiFi
// ---------------------------------------------------------------------------

fn readme_wifi_qr_svg() -> String {
  let payload =
    content.wifi(
      ssid: "MyAP",
      password: "secret",
      security: content.Wpa2,
      hidden: False,
    )
  let assert Ok(qr) = qrkit.encode(payload)
  svg.to_string(qr, svg.default_options())
}

pub fn readme_wifi_qr_svg_test() -> Nil {
  string.starts_with(readme_wifi_qr_svg(), "<svg")
  |> should.be_true
}

// ---------------------------------------------------------------------------
// README: vCard, email, SMS, phone, geo
// ---------------------------------------------------------------------------

fn readme_contact_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.vcard()
  |> content.with_name("Naohiro Chikamatsu")
  |> content.with_email("nao@example.com")
  |> content.with_phone("+81-90-0000-0000")
  |> content.with_url("https://github.com/nao1215")
  |> content.vcard_to_string
  |> qrkit.encode
}

fn readme_mail_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.email(to: "you@example.com", subject: "Hi", body: "Quick note")
  |> qrkit.encode
}

fn readme_sms_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.sms(to: "+819000000000", body: "Hello!") |> qrkit.encode
}

fn readme_phone_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.phone("+819000000000") |> qrkit.encode
}

fn readme_map_pin_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.geo(latitude: 35.6812, longitude: 139.7671) |> qrkit.encode
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
  content.event("Sync", 1_778_745_600, 1_778_749_200)
  |> content.with_location("Online")
  |> content.with_description("Project sync meeting")
  |> content.event_to_string
  |> qrkit.encode
}

pub fn readme_meeting_qr_test() -> Nil {
  let assert Ok(_) = readme_meeting_qr()
  Nil
}

// ---------------------------------------------------------------------------
// README: Inspect the matrix
// ---------------------------------------------------------------------------

fn readme_describe(qr: qrkit.QrCode) -> #(Int, Int, String, Bool) {
  #(
    qrkit.version(qr),
    qrkit.size(qr),
    qrkit.error_correction_designator(qrkit.error_correction(qr)),
    qrkit.module_at(qr, 0, 0),
  )
}

fn readme_ecc_letter_for_quartile() -> String {
  qrkit.error_correction_designator(error.Quartile)
}

pub fn readme_inspect_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let #(version, size, letter, top_left) = readme_describe(qr)
  version |> should.equal(1)
  size |> should.equal(21)
  letter |> should.equal("M")
  top_left |> should.be_true

  readme_ecc_letter_for_quartile()
  |> should.equal("Q")
}

// ---------------------------------------------------------------------------
// README: Micro QR
// ---------------------------------------------------------------------------

fn readme_business_card_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_min_version(2)
    |> qrkit.with_ecc(error.Low)
    |> qrkit.build()

  svg.to_string(qr, svg.default_options())
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
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_symbol(error.Rectangular)
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  svg.to_string(qr, svg.default_options())
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

  let assert Ok(shards) = qrkit.encode_split(payload, 2)
  list.map(shards, ascii.to_string)
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
  qrkit.new("123-ABC")
  |> qrkit.with_mode_preference(error.ForceByte)
  |> qrkit.build()
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
    Error(error.EmptyInput) -> True
    _ -> False
  }
}

pub fn readme_rejected_test() -> Nil {
  readme_rejected()
  |> should.be_true
}
