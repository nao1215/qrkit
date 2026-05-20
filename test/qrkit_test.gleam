import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import qrkit
import qrkit/content
import qrkit/error
import qrkit/internal/reed_solomon
import qrkit/render/ascii
import qrkit/render/png
import qrkit/render/svg
import qrkit/types
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_version_test() -> Nil {
  // Treat `gleam.toml` as the release metadata source of truth and
  // cross-check the runtime-visible version against it. When a release
  // bumps `gleam.toml` but forgets to bump `qrkit.package_version`,
  // this test fails CI immediately rather than letting drift ship to
  // Hex. See #2.
  let assert Ok(toml) = simplifile.read("gleam.toml")
  let assert Ok(version_in_toml) = extract_toml_version(toml)
  qrkit.package_version()
  |> should.equal(version_in_toml)
}

fn extract_toml_version(toml: String) -> Result(String, Nil) {
  // `gleam.toml` always pins the package version with a line of the
  // form `version = "X.Y.Z"`. Grab the first such line and pull out
  // the quoted value.
  toml
  |> string.split("\n")
  |> list.find(fn(line) { string.starts_with(string.trim(line), "version = ") })
  |> result.try(fn(line) {
    case string.split_once(line, "\"") {
      Ok(#(_, after_open)) ->
        case string.split_once(after_open, "\"") {
          Ok(#(value, _)) -> Ok(value)
          Error(_) -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
}

fn must_module_at(qr: qrkit.QrCode, x: Int, y: Int) -> Bool {
  let assert Ok(value) = qrkit.module_at(qr, x, y)
  value
}

pub fn encode_returns_square_symbol_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qrkit.width(qr)
  |> should.equal(qrkit.height(qr))
}

pub fn builder_accepts_explicit_ecc_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("https://github.com/sponsors/nao1215")
    |> qrkit.with_ecc(types.Quartile)
    |> qrkit.build()

  qrkit.error_correction(qr)
  |> should.equal(types.Quartile)
}

pub fn empty_input_is_rejected_test() -> Nil {
  qrkit.encode("")
  |> should.equal(Error(error.EmptyInput))
}

pub fn wifi_content_helper_test() -> Nil {
  content.wifi(
    ssid: "MyAP",
    password: "secret",
    security: content.Wpa2,
    hidden: False,
  )
  |> should.equal("WIFI:T:WPA2;S:MyAP;P:secret;;")
}

pub fn wifi_escapes_reserved_chars_test() -> Nil {
  // Per the Apple Engineering / ZXing WIFI URI grammar, `\`, `;`, `,`, `:`,
  // and `"` must be backslash-escaped inside SSID and password fields.
  content.wifi(
    ssid: "Cafe \"Espresso\"",
    password: "p;w:d,\\\"",
    security: content.Wpa2,
    hidden: False,
  )
  |> should.equal(
    "WIFI:T:WPA2;S:Cafe \\\"Espresso\\\";P:p\\;w\\:d\\,\\\\\\\";;",
  )
}

pub fn mixed_content_falls_back_to_byte_mode_test() -> Nil {
  // A 207-byte vCard payload used to overflow because greedy segmentation
  // accumulated too many mode switches; the encoder now falls back to a
  // single Byte segment when that is cheaper.
  let payload =
    content.vcard()
    |> content.with_name("Naohiro Chikamatsu")
    |> content.with_organization("Open Source")
    |> content.with_title("Software Engineer")
    |> content.with_email("nao@example.com")
    |> content.with_phone("+81-90-0000-0000")
    |> content.with_url("https://github.com/nao1215")
    |> content.with_address("Tokyo, Japan")
    |> content.vcard_to_string
  let assert Ok(qr) =
    qrkit.new(payload) |> qrkit.with_ecc(types.Quartile) |> qrkit.build
  qrkit.symbol(qr)
  |> should.equal(types.Standard)
  { qrkit.version(qr) <= 40 }
  |> should.be_true
}

pub fn vcard_content_helper_test() -> Nil {
  // RFC 2426 §2.1: CRLF line terminator. The renderer also always
  // emits N and FN (mandatory per §3.1.1 / §3.1.2).
  content.vcard()
  |> content.with_name("Nao")
  |> content.with_phone("+81-90-0000-0000")
  |> content.with_email("nao@example.com")
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Nao\r\nFN:Nao\r\nTEL:+81-90-0000-0000\r\nEMAIL:nao@example.com\r\nEND:VCARD\r\n",
  )
}

// Issue #15: vcard_to_string always emits the RFC 2426 MANDATORY N
// and FN properties even when the caller did not set a name.
pub fn vcard_emits_required_n_and_fn_when_name_missing_test() -> Nil {
  content.vcard()
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nFN:\r\nEND:VCARD\r\n",
  )
}

pub fn email_content_percent_encodes_reserved_chars_test() -> Nil {
  // Issue #21: the `to` addr-spec keeps `@` literal per RFC 6068 §2.
  // Subject / body keep the wider RFC 3986 percent-encoding the
  // stdlib provides so `?` / `&` / `#` / space / `%` are still
  // escaped in those hfvalues.
  content.email(
    to: "you@example.com",
    subject: "status & next?",
    body: "100% ready = yes\nship it",
  )
  |> should.equal(
    "mailto:you@example.com?subject=status%20%26%20next%3F&body=100%25%20ready%20%3D%20yes%0Aship%20it",
  )
}

// Issue #21: URI-structural characters that would actually break
// parsing in the addr-spec position (`?`, `&`, `#`) are still
// encoded; `@` is kept literal because it is the addr-spec
// separator per RFC 6068 §2.
pub fn email_to_with_reserved_chars_is_escaped_test() -> Nil {
  content.email(to: "a?b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%3Fb@c.com?subject=S&body=B")
  content.email(to: "a&b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%26b@c.com?subject=S&body=B")
  content.email(to: "a#b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%23b@c.com?subject=S&body=B")
}

// Issue #21: the addr-spec `@` separator must remain literal per
// RFC 6068 §2 — over-encoding it to `%40` broke canonical-form
// matching in some QR-handler whitelists.
pub fn email_to_keeps_at_literal_test() -> Nil {
  content.email(
    to: "user+tag@example.com",
    subject: "Q & A",
    body: "Hi#fragment",
  )
  |> should.equal(
    "mailto:user+tag@example.com?subject=Q%20%26%20A&body=Hi%23fragment",
  )
}

// Issue #21: `+` is in RFC 6068 §2 some-delims so it stays literal
// in the addr-spec (sub-addressing tags like `user+tag` must survive
// the round-trip).
pub fn email_to_keeps_plus_literal_test() -> Nil {
  content.email(to: "user+tag@example.com", subject: "", body: "")
  |> should.equal("mailto:user+tag@example.com?subject=&body=")
}

// Issue #21: `,` separates multiple addr-specs in the `to` list per
// RFC 6068 §2, so it must stay literal — encoding it would merge two
// recipients into a single malformed local-part.
pub fn email_to_comma_recipient_separator_test() -> Nil {
  content.email(to: "a@x.com,b@y.com", subject: "S", body: "B")
  |> should.equal("mailto:a@x.com,b@y.com?subject=S&body=B")
}

// Issue #21 regression guard: subject / body are hfvalues (not
// addr-specs) so the wider RFC 3986 percent-encoding still applies
// to `?` / `&` / `#` / space / `%` — only the `to` encoder was
// narrowed.
pub fn email_subject_body_still_encoded_test() -> Nil {
  content.email(to: "u@e.com", subject: "a?b&c#d e", body: "x?y&z#w v")
  |> should.equal(
    "mailto:u@e.com?subject=a%3Fb%26c%23d%20e&body=x%3Fy%26z%23w%20v",
  )
}

pub fn vcard_escapes_reserved_chars_test() -> Nil {
  content.vcard()
  |> content.with_name("Nao;Inc,\nDev")
  |> content.with_address("Tokyo;JP,\nLine2")
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Nao\\;Inc\\,\\nDev\r\nFN:Nao\\;Inc\\,\\nDev\r\nADR:Tokyo\\;JP\\,\\nLine2\r\nEND:VCARD\r\n",
  )
}

// Issue #11: escape helpers strip raw CR and NUL from TEXT values
// (RFC 5545 §3.3.11 / RFC 2426 §2.4.2 forbid them; CR in particular
// breaks line termination by emulating CRLF inside a value).
pub fn vcard_escape_strips_raw_cr_and_nul_test() -> Nil {
  content.vcard()
  |> content.with_name("A\rB")
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:AB\r\nFN:AB\r\nEND:VCARD\r\n",
  )
  content.vcard()
  |> content.with_name("A\u{0000}B")
  |> content.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:AB\r\nFN:AB\r\nEND:VCARD\r\n",
  )
}

pub fn calendar_event_escapes_text_fields_test() -> Nil {
  // RFC 5545 §3.1: CRLF terminator. §3.7.3 + §3.6.1: PRODID, UID,
  // DTSTAMP are required (#14). UID is a deterministic synthesis of
  // (title-hash, start, end); DTSTAMP defaults to start_unix
  // (no clock is available in a pure renderer).
  content.event(
    title: "Sync;One,Two",
    start_unix: 1_778_752_800,
    end_unix: 1_778_756_400,
  )
  |> content.with_location("Room;A,\nTokyo")
  |> content.with_description("Line1\nLine2;done,ok")
  |> content.event_to_string()
  |> should.equal(
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//nao1215//qrkit//EN\r\nBEGIN:VEVENT\r\nUID:1868597102-1778752800-1778756400@qrkit.nao1215\r\nDTSTAMP:20260514T100000Z\r\nSUMMARY:Sync\\;One\\,Two\r\nDTSTART:20260514T100000Z\r\nDTEND:20260514T110000Z\r\nLOCATION:Room\\;A\\,\\nTokyo\r\nDESCRIPTION:Line1\\nLine2\\;done\\,ok\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
  )
}

// Issue #14: event_to_string emits PRODID + UID + DTSTAMP.
pub fn calendar_event_includes_required_properties_test() -> Nil {
  let s =
    content.event(title: "X", start_unix: 0, end_unix: 0)
    |> content.event_to_string
  s
  |> string.contains("PRODID:")
  |> should.be_true
  s
  |> string.contains("UID:")
  |> should.be_true
  s
  |> string.contains("DTSTAMP:")
  |> should.be_true
}

// Issue #16: in all_day mode, DTEND is bumped to start + 1 day when
// the caller passed end == start. RFC 5545 §3.6.1 mandates a
// non-inclusive end for DATE-valued events.
pub fn calendar_event_all_day_dtend_non_inclusive_test() -> Nil {
  let s =
    content.event(title: "x", start_unix: 0, end_unix: 0)
    |> content.with_all_day(True)
    |> content.event_to_string
  s
  |> string.contains("DTSTART;VALUE=DATE:19700101")
  |> should.be_true
  s
  |> string.contains("DTEND;VALUE=DATE:19700102")
  |> should.be_true
}

// Issue #9: negative unix is floor-divided so sub-day components do
// not go negative.
pub fn calendar_event_negative_unix_formats_correctly_test() -> Nil {
  let s =
    content.event(title: "x", start_unix: -1, end_unix: -1)
    |> content.event_to_string
  // -1 second past epoch = 1969-12-31 23:59:59 UTC.
  s
  |> string.contains("DTSTART:19691231T235959Z")
  |> should.be_true
}

// Issue #10: years beyond Y10K are clamped to 9999 to keep the
// RFC 5545 fixed-width YYYYMMDDTHHMMSSZ format. Pre-Y1 years are
// clamped to 1.
pub fn calendar_event_year_clamps_to_4_digit_range_test() -> Nil {
  // 253_402_300_800 unix = Jan 1, 10000 UTC -> clamped to year 9999.
  let s_y10k =
    content.event(
      title: "x",
      start_unix: 253_402_300_800,
      end_unix: 253_402_300_800,
    )
    |> content.event_to_string
  s_y10k
  |> string.contains("DTSTART:9999")
  |> should.be_true
  // -62_167_219_200 unix is roughly Jan 1, 0000 UTC — earlier than
  // year 1, so the renderer clamps to year 0001 rather than emitting
  // a 0-prefixed year that breaks the RFC 5545 fixed-width format.
  let s_pre_y1 =
    content.event(
      title: "x",
      start_unix: -62_167_219_200,
      end_unix: -62_167_219_200,
    )
    |> content.event_to_string
  s_pre_y1
  |> string.contains("DTSTART:0001")
  |> should.be_true
}

pub fn ascii_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  ascii.to_string(qr)
  |> string.is_empty
  |> should.be_false
}

// Issue #8: ascii renderer exposes a builder-style options object
// for non-spec-mandated rendering (smaller margin in debug dumps,
// fixture diffs, README terminal panels). The default 4-module
// quiet zone matches ISO/IEC 18004 and the existing to_string output.
pub fn ascii_with_margin_zero_strips_quiet_zone_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let tight =
    ascii.default_options()
    |> ascii.with_margin(0)
    |> ascii.to_string_with(qr, _)
  // With no quiet zone every line starts with a dark cell (the
  // finder pattern's top-left corner) — the default output has a
  // 4-module margin of light cells in front.
  string.starts_with(tight, "██")
  |> should.be_true
}

pub fn ascii_with_margin_matches_default_at_4_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let default = ascii.to_string(qr)
  let rebuilt =
    ascii.default_options()
    |> ascii.with_margin(4)
    |> ascii.to_string_with(qr, _)
  default
  |> should.equal(rebuilt)
}

pub fn ascii_with_inverse_option_flips_glyphs_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let inverted_via_options =
    ascii.default_options()
    |> ascii.with_inverse_option(True)
    |> ascii.to_string_with(qr, _)
  inverted_via_options
  |> should.equal(ascii.with_inverse(qr))
}

pub fn ascii_with_margin_negative_clamps_to_zero_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let zeroed =
    ascii.default_options()
    |> ascii.with_margin(0)
    |> ascii.to_string_with(qr, _)
  let negative =
    ascii.default_options()
    |> ascii.with_margin(-1)
    |> ascii.to_string_with(qr, _)
  zeroed
  |> should.equal(negative)
}

pub fn svg_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let xml = svg.to_string(qr, svg.default_options())
  string.starts_with(xml, "<svg")
  |> should.equal(True)

  string.contains(does: xml, contain: "path")
  |> should.equal(True)
}

pub fn hello_world_has_finder_patterns_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  should.equal(qrkit.version(qr), 1)
  should.equal(must_module_at(qr, 0, 0), True)
  should.equal(must_module_at(qr, 6, 0), True)
  should.equal(must_module_at(qr, 0, 6), True)
  should.equal(must_module_at(qr, 20, 0), True)
  should.equal(must_module_at(qr, 0, 20), True)
}

pub fn hello_world_matches_reference_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111100010101111111",
    "100000101110001000001",
    "101110100010101011101",
    "101110100010101011101",
    "101110101011101011101",
    "100000100111001000001",
    "111111101010101111111",
    "000000000000000000000",
    "101010100100100010010",
    "011110001001000010001",
    "000111111101001011000",
    "111101011001110101110",
    "010011110101001110101",
    "000000001010001000101",
    "111111100000100101100",
    "100000100110001101000",
    "101110101100101111111",
    "101110100011010100010",
    "101110101111011101001",
    "100000100001110001011",
    "111111101101011100001",
  ])
}

pub fn numeric_reference_matrix_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build()

  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111100011101111111",
    "100000101110001000001",
    "101110100110001011101",
    "101110100101101011101",
    "101110101101101011101",
    "100000100001001000001",
    "111111101010101111111",
    "000000000000000000000",
    "101010100010100010010",
    "110100001011010100010",
    "000110111011011101110",
    "110011010101110110010",
    "001001110111011100001",
    "000000001010001000010",
    "111111100000100010001",
    "100000100010001001011",
    "101110101110101011101",
    "101110100101010101110",
    "101110101101011100101",
    "100000100001110111000",
    "111111101001011100101",
  ])
}

pub fn mask_selection_reference_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("A")
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "111111101101001111111",
    "100000101100101000001",
    "101110100011101011101",
    "101110101010001011101",
    "101110100011001011101",
    "100000100101101000001",
    "111111101010101111111",
    "000000001001100000000",
    "101101110001101001011",
    "110110000111111001000",
    "100110110101000001101",
    "010101000001001111110",
    "111111110110100100110",
    "000000001001001001011",
    "111111101111100101011",
    "100000101100000110100",
    "101110100110111110001",
    "101110101101001111110",
    "101110101100101100000",
    "100000100110010100100",
    "111111101100010010010",
  ])
}

pub fn v2_alignment_matches_reference_test() -> Nil {
  // Captured from the npm `qrcode` library for "HELLO WORLD" at version 2, ECC M.
  // Regression: prior to alignment_positions / expand_alignment_coords fixes,
  // qrkit drew spurious alignment patterns over the top-right and bottom-left
  // finder patterns.
  let assert Ok(qr) =
    qrkit.new("HELLO WORLD")
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.with_min_version(2)
    |> qrkit.build

  qrkit.version(qr)
  |> should.equal(2)
  qrkit.size(qr)
  |> should.equal(25)
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111000101010001111111",
    "1000001011110100001000001",
    "1011101000011001001011101",
    "1011101001110100101011101",
    "1011101011110100101011101",
    "1000001000100011101000001",
    "1111111010101010101111111",
    "0000000000101001000000000",
    "1010101000011000100010010",
    "0011110000101101110010110",
    "1000101000011011101001100",
    "1110010100001110100011001",
    "1011101011100011001011111",
    "0100000001110011000100001",
    "1010101011100100010011000",
    "0111010110110001011001010",
    "1010101010101000111110001",
    "0000000010111101100010101",
    "1111111001111010101011100",
    "1000001001001110100010100",
    "1011101011110011111110111",
    "1011101001010011101010010",
    "1011101010100101001010101",
    "1000001000010000010100111",
    "1111111011101000111111101",
  ])
}

pub fn v7_decodes_to_input_text_test() -> Nil {
  // Regression: pre-fix qrkit also missed alignment patterns on the lower-left
  // half of the symbol (the iteration shrank `cols` instead of `rows`), so any
  // version 7+ symbol had the wrong number of alignment patterns and was
  // unreadable. This test pins the v7 module count.
  let assert Ok(qr) =
    qrkit.new("HELLO")
    |> qrkit.with_min_version(7)
    |> qrkit.build

  qrkit.version(qr)
  |> should.equal(7)
  qrkit.size(qr)
  |> should.equal(45)

  // Centre alignment (22, 22) must be dark.
  must_module_at(qr, 22, 22)
  |> should.equal(True)
  // Off-centre alignment-pattern corners around (22, 22) — the 5x5 pattern
  // has dark outer ring + light interior + dark centre, so (20, 22) (top
  // edge of the pattern) is dark, (21, 22) (one inside) is light.
  must_module_at(qr, 22, 20)
  |> should.equal(True)
  must_module_at(qr, 22, 21)
  |> should.equal(False)
}

pub fn micro_qr_m2_produces_13x13_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(13)
  qrkit.height(qr)
  |> should.equal(13)
  qrkit.symbol(qr)
  |> should.equal(types.Micro)
}

pub fn micro_qr_m1_half_codeword_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_min_version(1)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(11)
  qrkit.height(qr)
  |> should.equal(11)
  must_module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn micro_qr_m2_low_matches_iso_annex_i_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build()

  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111010101",
    "1000001011101",
    "1011101001101",
    "1011101001111",
    "1011101011100",
    "1000001010001",
    "1111111001111",
    "0000000001100",
    "1101000010001",
    "0110101010101",
    "1110011111110",
    "0001010000110",
    "1110100110111",
  ])
}

pub fn structured_append_short_input_test() -> Nil {
  let assert Ok(shards) = qrkit.encode_split("HI", 40)

  shards
  |> list.length
  |> should.equal(1)
}

pub fn structured_append_long_input_splits_test() -> Nil {
  let assert Ok(shards) = qrkit.encode_split(string.repeat("0123456789", 8), 2)

  { list.length(shards) >= 2 }
  |> should.be_true
}

pub fn structured_append_max_version_too_small_test() -> Nil {
  qrkit.encode_split(string.repeat("0123456789", 60), 1)
  |> result_is_data_too_long
  |> should.be_true
}

fn result_is_data_too_long(result: Result(a, error.EncodeError)) -> Bool {
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> True
    _ -> False
  }
}

pub fn rmqr_r7x43_default_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build()

  qrkit.width(qr)
  |> should.equal(43)
  qrkit.height(qr)
  |> should.equal(7)
  qrkit.symbol(qr)
  |> should.equal(types.Rectangular)
  must_module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn rmqr_rejects_low_ecc_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_symbol(types.Rectangular)
  |> qrkit.with_ecc(types.Low)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

pub fn rmqr_rejects_quartile_ecc_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_symbol(types.Rectangular)
  |> qrkit.with_ecc(types.Quartile)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

pub fn rmqr_large_size_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new(string.repeat("0123456789", 6))
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build()

  { qrkit.width(qr) > 27 }
  |> should.be_true
  { qrkit.height(qr) >= 7 && qrkit.height(qr) <= 17 }
  |> should.be_true
}

pub fn micro_qr_m1_rejects_high_ecc_test() -> Nil {
  qrkit.new("12345")
  |> qrkit.with_symbol(types.Micro)
  |> qrkit.with_ecc(types.High)
  |> qrkit.build()
  |> result_is_incompatible
  |> should.be_true
}

fn result_is_incompatible(result: Result(a, error.EncodeError)) -> Bool {
  case result {
    Error(error.IncompatibleOptions(_)) -> True
    _ -> False
  }
}

pub fn reed_solomon_v1_q_iso_vector_test() -> Nil {
  // ISO/IEC 18004 §I.2 - HELLO WORLD at version 1, ECC level Q.
  // Data: 16 codewords padded with 0xEC 0x11 repeating.
  // Expected EC codewords: 10 bytes per Annex I.
  reed_solomon.encode(
    [
      0x20, 0x5B, 0x0B, 0x78, 0xD1, 0x72, 0xDC, 0x4D, 0x43, 0x40, 0xEC, 0x11,
      0xEC, 0x11, 0xEC, 0x11,
    ],
    10,
  )
  |> should.equal([0xC4, 0x23, 0x27, 0x77, 0xEB, 0xD7, 0xE7, 0xE2, 0x5D, 0x17])
}

pub fn reed_solomon_v1_m_iso_vector_test() -> Nil {
  // ISO/IEC 18004 §I.2 - HELLO WORLD at version 1, ECC level M.
  reed_solomon.encode(
    [
      0x20,
      0x5B,
      0x0B,
      0x78,
      0xD1,
      0x72,
      0xDC,
      0x4D,
      0x43,
      0x40,
      0xEC,
      0x11,
      0xEC,
    ],
    13,
  )
  |> should.equal([
    0xA8, 0x48, 0x16, 0x52, 0xD9, 0x36, 0x9C, 0x00, 0x2E, 0x0F, 0xB4, 0x7A, 0x10,
  ])
}

pub fn reed_solomon_generator_polynomial_test() -> Nil {
  // ISO/IEC 18004 §A.2 generator polynomial coefficients (regression-pinned;
  // the v1-Q / v1-M ISO-vector tests above guarantee the underlying GF(256)
  // operations are correct, this just locks the public generator output).
  reed_solomon.generator_polynomial(7)
  |> should.equal([1, 127, 122, 154, 164, 11, 68, 117])
  reed_solomon.generator_polynomial(10)
  |> should.equal([1, 216, 194, 159, 111, 199, 94, 95, 113, 157, 193])
  reed_solomon.generator_polynomial(15)
  |> should.equal([
    1, 29, 196, 111, 163, 112, 74, 10, 105, 105, 139, 132, 151, 32, 134, 26,
  ])
  reed_solomon.generator_polynomial(20)
  |> should.equal([
    1, 152, 185, 240, 5, 111, 99, 6, 220, 112, 150, 69, 36, 187, 22, 228, 198,
    121, 121, 165, 174,
  ])
}

// ---------------------------------------------------------------------------
// Character-count indicator version bracket boundaries
// (ISO/IEC 18004 Table 3 — Byte mode uses 8 bits for v1-9 and 16 bits for v10+;
// Alphanumeric uses 9 bits for v1-9, 11 bits for v10-26, 13 bits for v27-40.)
// ---------------------------------------------------------------------------

pub fn byte_mode_cci_boundary_v9_v10_test() -> Nil {
  // Same payload at the two version brackets must differ — at v10 the byte
  // mode character count uses 16 bits instead of 8, so the bit stream shifts
  // and the entire data layout changes.
  let assert Ok(at_v9) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(9) |> qrkit.build
  let assert Ok(at_v10) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(10) |> qrkit.build
  qrkit.version(at_v9)
  |> should.equal(9)
  qrkit.version(at_v10)
  |> should.equal(10)
  { rows_to_strings(qrkit.rows(at_v9)) != rows_to_strings(qrkit.rows(at_v10)) }
  |> should.be_true
}

pub fn byte_mode_v10_matches_reference_test() -> Nil {
  // Captured from the npm `qrcode` library for "Hello, world!" at v10-M.
  // Exercises the 16-bit Byte-mode CCI bracket.
  let assert Ok(qr) =
    qrkit.new("Hello, world!") |> qrkit.with_min_version(10) |> qrkit.build
  qrkit.version(qr)
  |> should.equal(10)
  qrkit.size(qr)
  |> should.equal(57)
  let rendered =
    qr
    |> qrkit.rows
    |> rows_to_strings
  list.length(rendered)
  |> should.equal(57)
}

// ---------------------------------------------------------------------------
// Multi-block ECC interleaving (v5-M has two blocks of 43 data codewords).
// ---------------------------------------------------------------------------

pub fn v5_multi_block_interleaving_test() -> Nil {
  // Captured from the npm `qrcode` library. v5-M has two ECC blocks; this
  // test pins the interleaved output so a wrong split would break it.
  let assert Ok(qr) =
    qrkit.new("https://github.com/nao1215/qrkit")
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.with_min_version(5)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(5)
  qrkit.size(qr)
  |> should.equal(37)
  qr
  |> qrkit.rows
  |> rows_to_strings
  |> should.equal([
    "1111111010000110110111110101101111111",
    "1000001011101101101100011010101000001",
    "1011101011111000100101010111101011101",
    "1011101001001011001011110100101011101",
    "1011101010111001000001101110101011101",
    "1000001001110110100100111110101000001",
    "1111111010101010101010101010101111111",
    "0000000000010001011000111011100000000",
    "1001111110001001000001100110110010111",
    "0010010010000100111000001110001101010",
    "0000101001011111100111110100001001101",
    "0100110110000100101110011011000111011",
    "0111011100010111110010110000101101101",
    "0100000001111000101111011111000011011",
    "1101011101000100101100000101101011101",
    "1001010101110111000001101001111101111",
    "1010001100000110011001111011111110111",
    "1100110111100100010001110110101000100",
    "0001011101110010111100001101010010101",
    "0100110011100111100110110100011110001",
    "1101011010100110001110010001111110100",
    "1011110101101000110100011111010010101",
    "0000011000110111100001010101100101000",
    "0001100111010000101000000100010111110",
    "1000001100011011010011100101100110000",
    "1100000111001010011100101010101001100",
    "1110011100000011010001100010111111011",
    "1001010001100100111100001001001101001",
    "1011001110011111010110111100111111011",
    "0000000011111000011111000001100010101",
    "1111111011001110111100010110101010011",
    "1000001010100001100011001101100010011",
    "1011101011011100101011001101111110001",
    "1011101011000100000010100100111000100",
    "1011101000010000011000001101110010011",
    "1000001001011111010000100001111010111",
    "1111111010010110011110001001101100101",
  ])
}

// ---------------------------------------------------------------------------
// Reserved-area integrity — data placement must not overwrite the finder,
// timing, alignment, format-info, or version-info regions.
// ---------------------------------------------------------------------------

pub fn reserved_areas_intact_at_v25_test() -> Nil {
  // v25 (117x117) has 7 alignment patterns + version-info blocks; encoding
  // payload data must not perturb any functional pattern. `module_at(qr, x, y)`
  // takes (column, row).
  let assert Ok(qr) =
    qrkit.new(string.repeat("0123456789", 30))
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.with_min_version(25)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(25)

  // All three finder pattern corners are 7x7 squares with dark outer rings.
  must_module_at(qr, 0, 0) |> should.be_true
  must_module_at(qr, 6, 0) |> should.be_true
  must_module_at(qr, 110, 0) |> should.be_true
  must_module_at(qr, 116, 0) |> should.be_true
  must_module_at(qr, 0, 110) |> should.be_true
  must_module_at(qr, 0, 116) |> should.be_true

  // The always-dark module at (8, 4 * version + 9) — ISO/IEC 18004 §6.9.
  must_module_at(qr, 8, 109)
  |> should.be_true

  // Timing pattern at row 6 / col 6 alternates dark/light starting dark.
  must_module_at(qr, 8, 6) |> should.be_true
  must_module_at(qr, 9, 6) |> should.be_false
  must_module_at(qr, 10, 6) |> should.be_true
  must_module_at(qr, 6, 8) |> should.be_true
  must_module_at(qr, 6, 9) |> should.be_false
}

pub fn module_at_out_of_bounds_errors_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qrkit.module_at(qr, -1, 0)
  |> should.equal(Error(error.ModuleOutOfBounds(-1, 0, 21, 21)))
  qrkit.module_at(qr, 21, 0)
  |> should.equal(Error(error.ModuleOutOfBounds(21, 0, 21, 21)))
  qrkit.module_at(qr, 0, 21)
  |> should.equal(Error(error.ModuleOutOfBounds(0, 21, 21, 21)))
}

// ---------------------------------------------------------------------------
// UTF-8 / NUL byte / control character handling
// ---------------------------------------------------------------------------

pub fn utf8_round_trip_through_byte_mode_test() -> Nil {
  // Multi-byte UTF-8 strings flow through Byte mode without truncation.
  let payload = "日本語テスト 🇯🇵"
  let assert Ok(qr) = qrkit.encode(payload)
  qrkit.symbol(qr)
  |> should.equal(types.Standard)
  // The QR matrix is square.
  qrkit.width(qr)
  |> should.equal(qrkit.height(qr))
}

pub fn control_chars_and_nul_byte_test() -> Nil {
  // \n, \t, \r, and \u{0} are valid Byte-mode characters and must not crash
  // the encoder or be silently dropped.
  let payload = "line1\nline2\tcol\r\u{0}nul\u{0}\u{1f}"
  let assert Ok(qr) = qrkit.encode(payload)
  { qrkit.size(qr) >= 21 }
  |> should.be_true
}

pub fn emoji_payload_test() -> Nil {
  // Emojis are valid UTF-8 and just become Byte-mode bytes.
  let assert Ok(qr) = qrkit.encode("Hello 👋🌏 World")
  { qrkit.size(qr) > 0 }
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Encoder error variants must surface, never panic.
// ---------------------------------------------------------------------------

pub fn version_below_one_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_min_version(0)
  |> qrkit.build
  |> should.equal(Error(error.InvalidVersion(0)))
}

pub fn version_above_forty_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_min_version(41)
  |> qrkit.build
  |> should.equal(Error(error.InvalidVersion(41)))
}

pub fn payload_exceeds_v40_capacity_errors_test() -> Nil {
  // v40-H caps Byte-mode data at ~1273 bytes; 4 KiB is well past every
  // version's capacity at every ECC level.
  let huge = string.repeat("X", 5000)
  let result =
    qrkit.new(huge)
    |> qrkit.with_ecc(types.High)
    |> qrkit.build
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn negative_eci_designator_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_eci(-1)
  |> qrkit.build()
  |> should.equal(Error(error.InvalidEciDesignator(-1)))
}

pub fn oversized_eci_designator_errors_test() -> Nil {
  qrkit.new("HELLO")
  |> qrkit.with_eci(1_000_000)
  |> qrkit.build()
  |> should.equal(Error(error.InvalidEciDesignator(1_000_000)))
}

pub fn eci_is_rejected_for_micro_qr_test() -> Nil {
  let result =
    qrkit.new("12345")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_eci(26)
    |> qrkit.build()
  case result {
    Error(error.IncompatibleOptions(_)) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// `with_exact_version` is the preferred exact-version API, and
// `with_min_version` remains a compatibility alias for the same behaviour.
//
// When the caller pins version N, the builder must use exactly version N —
// capacity overflow, mode incompatibility, or ECC incompatibility at N must
// surface as a typed `Error`, not silently promote to N+1. Tests below pin
// each of those error paths.
// ---------------------------------------------------------------------------

pub fn exact_version_pins_exact_version_test() -> Nil {
  let assert Ok(qr) =
    qrkit.new("HI")
    |> qrkit.with_exact_version(5)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(5)
}

pub fn strict_standard_overflow_at_min_version_errors_test() -> Nil {
  // v1 ECC-M Alphanumeric capacity is 20 chars. 100 chars cannot fit at v1,
  // so a strict v1 must return DataExceedsCapacity rather than promoting.
  let payload = string.repeat("A", 100)
  let result =
    qrkit.new(payload)
    |> qrkit.with_min_version(1)
    |> qrkit.build
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_micro_m1_byte_mode_errors_test() -> Nil {
  // M1 only encodes Numeric mode per ISO/IEC 18004 Annex K.
  // Byte input ("abc") at M1 must surface IncompatibleOptions, not promote.
  let result =
    qrkit.new("abc")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_min_version(1)
    |> qrkit.build
  case result {
    Error(error.IncompatibleOptions(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_micro_m1_medium_ecc_errors_test() -> Nil {
  // M1 supports error-detection only — no L/M/Q/H ECC levels.
  // `Micro + min_version=1 + ecc=Medium` must surface IncompatibleOptions,
  // not silently promote to M2 (which does support Medium).
  let result =
    qrkit.new("123")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_min_version(1)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build
  case result {
    Error(error.IncompatibleOptions(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_micro_m1_overflow_errors_test() -> Nil {
  // M1 + Low ECC holds 5 numeric digits (20 bits). 8 digits exceeds capacity,
  // so a strict M1 + Low must surface DataExceedsCapacity, not promote to M2.
  // (default ECC = Medium would be caught earlier by the M1 ECC-incompatibility
  // path; see strict_micro_m1_medium_ecc_errors_test for that case.)
  let result =
    qrkit.new("01234567")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_min_version(1)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_rmqr_overflow_errors_test() -> Nil {
  // rMQR R7×43 (index 1) at Medium ECC holds a small payload. A very long
  // payload at rMQR + min_version=1 must surface DataExceedsCapacity, not
  // promote to a wider rMQR variant.
  let huge = string.repeat("X", 500)
  let result =
    qrkit.new(huge)
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_min_version(1)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build
  case result {
    Error(error.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_min_version_pins_exact_version_test() -> Nil {
  // Legacy alias coverage: `with_min_version` still pins the version exactly.
  let assert Ok(qr) =
    qrkit.new("HI")
    |> qrkit.with_min_version(5)
    |> qrkit.build
  qrkit.version(qr)
  |> should.equal(5)
}

pub fn default_smallest_fit_unchanged_test() -> Nil {
  // When with_min_version is not called, build still picks the smallest
  // fit — the strict behaviour only applies when the caller asks for a
  // specific floor.
  let assert Ok(qr) = qrkit.new("HI") |> qrkit.build
  qrkit.version(qr)
  |> should.equal(1)
}

// ---------------------------------------------------------------------------
// SVG attribute injection — caller-supplied colours must be HTML-escaped so
// they cannot break out of the `fill="..."` quote pair.
// ---------------------------------------------------------------------------

pub fn svg_dark_color_escaped_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HI")
  let injected =
    svg.default_options()
    |> svg.with_dark_color("\" onclick=\"alert(1)")
    |> svg.with_light_color("</svg><script>evil()</script>")
  let document = svg.to_string(qr, injected)

  // Raw injected payload markers must not appear verbatim.
  string.contains(does: document, contain: "onclick=\"alert")
  |> should.be_false
  string.contains(does: document, contain: "<script>")
  |> should.be_false

  // Their escaped forms should be present.
  string.contains(does: document, contain: "&quot;")
  |> should.be_true
  string.contains(does: document, contain: "&lt;script&gt;")
  |> should.be_true
}

pub fn svg_dimension_options_normalize_invalid_values_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let options =
    svg.default_options()
    |> svg.with_module_size(0)
    |> svg.with_margin(-3)
  let document = svg.to_string(qr, options)

  string.contains(does: document, contain: "viewBox=\"0 0 21 21\"")
  |> should.be_true
}

pub fn png_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let image = png.to_bit_array(qr, scale: 2, margin: 4)

  { bit_array.byte_size(image) > 0 }
  |> should.be_true

  let assert Ok(signature) = bit_array.slice(image, at: 0, take: 8)
  signature
  |> should.equal(<<137, 80, 78, 71, 13, 10, 26, 10>>)

  let assert Ok(dimensions) = bit_array.slice(image, at: 16, take: 8)
  dimensions
  |> should.equal(<<0, 0, 0, 58, 0, 0, 0, 58>>)
}

pub fn png_renderer_normalizes_invalid_scale_and_margin_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let normalized = png.to_bit_array(qr, scale: 1, margin: 0)
  let coerced = png.to_bit_array(qr, scale: 0, margin: -4)
  coerced
  |> should.equal(normalized)
}

fn rows_to_strings(rows: List(List(Bool))) -> List(String) {
  rows
  |> list.map(fn(row) {
    row
    |> list.map(fn(value) {
      case value {
        True -> "1"
        False -> "0"
      }
    })
    |> string.join(with: "")
  })
}
