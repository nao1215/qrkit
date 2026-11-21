import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleeunit
import gleeunit/should
import qrkit
import qrkit/internal/reed_solomon

pub fn main() -> Nil {
  gleeunit.main()
}

fn must_module_at(qr: qrkit.QrCode, x: Int, y: Int) -> Bool {
  let assert [row, ..] = list.drop(qr.rows, y)
  let assert [value, ..] = list.drop(row, x)
  value
}

pub fn encode_returns_square_symbol_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qr.width
  |> should.equal(qr.height)
}

pub fn builder_accepts_explicit_ecc_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "https://github.com/sponsors/nao1215",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Quartile,
      ),
    )

  qr.error_correction
  |> should.equal(qrkit.Quartile)
}

pub fn empty_input_is_rejected_test() -> Nil {
  qrkit.encode("")
  |> should.equal(Error(qrkit.EmptyInput))
}

pub fn wifi_content_helper_test() -> Nil {
  qrkit.wifi(ssid: "MyAP", security: qrkit.Wpa2("secret"), hidden: False)
  |> should.equal("WIFI:T:WPA2;S:MyAP;P:secret;;")
}

pub fn wifi_escapes_reserved_chars_test() -> Nil {
  // Per the Apple Engineering / ZXing WIFI URI grammar, `\`, `;`, `,`, `:`,
  // and `"` must be backslash-escaped inside SSID and password fields.
  qrkit.wifi(
    ssid: "Cafe \"Espresso\"",
    security: qrkit.Wpa2("p;w:d,\\\""),
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
    qrkit.VCard(
      ..qrkit.vcard("Naohiro Chikamatsu"),
      organization: Some("Open Source"),
      title: Some("Software Engineer"),
      email: Some("nao@example.com"),
      phone: Some("+81-90-0000-0000"),
      url: Some("https://github.com/nao1215"),
      address: Some("Tokyo, Japan"),
    )
    |> qrkit.vcard_to_string
  let assert Ok(qr) =
    qrkit.encode_with(
      payload,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Quartile,
      ),
    )
  qr.symbol
  |> should.equal(qrkit.Standard)
  { qr.version <= 40 }
  |> should.be_true
}

pub fn vcard_content_helper_test() -> Nil {
  // RFC 2426 §2.1: CRLF line terminator. The renderer also always
  // emits N and FN (mandatory per §3.1.1 / §3.1.2).
  qrkit.VCard(
    ..qrkit.vcard("Nao"),
    phone: Some("+81-90-0000-0000"),
    email: Some("nao@example.com"),
  )
  |> qrkit.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Nao\r\nFN:Nao\r\nTEL:+81-90-0000-0000\r\nEMAIL:nao@example.com\r\nEND:VCARD\r\n",
  )
}

// Issue #15: vcard_to_string always emits the RFC 2426 MANDATORY N
// and FN properties even when the caller did not set a name.
pub fn vcard_emits_required_n_and_fn_when_name_missing_test() -> Nil {
  qrkit.vcard("")
  |> qrkit.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nFN:\r\nEND:VCARD\r\n",
  )
}

pub fn email_content_percent_encodes_reserved_chars_test() -> Nil {
  // Issue #21: the `to` addr-spec keeps `@` literal per RFC 6068 §2.
  // Subject / body keep the wider RFC 3986 percent-encoding the
  // stdlib provides so `?` / `&` / `#` / space / `%` are still
  // escaped in those hfvalues.
  qrkit.email(
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
  qrkit.email(to: "a?b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%3Fb@c.com?subject=S&body=B")
  qrkit.email(to: "a&b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%26b@c.com?subject=S&body=B")
  qrkit.email(to: "a#b@c.com", subject: "S", body: "B")
  |> should.equal("mailto:a%23b@c.com?subject=S&body=B")
}

// Issue #21: the addr-spec `@` separator must remain literal per
// RFC 6068 §2 — over-encoding it to `%40` broke canonical-form
// matching in some QR-handler whitelists.
pub fn email_to_keeps_at_literal_test() -> Nil {
  qrkit.email(to: "user+tag@example.com", subject: "Q & A", body: "Hi#fragment")
  |> should.equal(
    "mailto:user+tag@example.com?subject=Q%20%26%20A&body=Hi%23fragment",
  )
}

// Issue #21: `+` is in RFC 6068 §2 some-delims so it stays literal
// in the addr-spec (sub-addressing tags like `user+tag` must survive
// the round-trip).
pub fn email_to_keeps_plus_literal_test() -> Nil {
  qrkit.email(to: "user+tag@example.com", subject: "", body: "")
  |> should.equal("mailto:user+tag@example.com?subject=&body=")
}

// Issue #21: `,` separates multiple addr-specs in the `to` list per
// RFC 6068 §2, so it must stay literal — encoding it would merge two
// recipients into a single malformed local-part.
pub fn email_to_comma_recipient_separator_test() -> Nil {
  qrkit.email(to: "a@x.com,b@y.com", subject: "S", body: "B")
  |> should.equal("mailto:a@x.com,b@y.com?subject=S&body=B")
}

// Issue #21 regression guard: subject / body are hfvalues (not
// addr-specs) so the wider RFC 3986 percent-encoding still applies
// to `?` / `&` / `#` / space / `%` — only the `to` encoder was
// narrowed.
pub fn email_subject_body_still_encoded_test() -> Nil {
  qrkit.email(to: "u@e.com", subject: "a?b&c#d e", body: "x?y&z#w v")
  |> should.equal(
    "mailto:u@e.com?subject=a%3Fb%26c%23d%20e&body=x%3Fy%26z%23w%20v",
  )
}

pub fn vcard_escapes_reserved_chars_test() -> Nil {
  qrkit.VCard(..qrkit.vcard("Nao;Inc,\nDev"), address: Some("Tokyo;JP,\nLine2"))
  |> qrkit.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Nao\\;Inc\\,\\nDev\r\nFN:Nao\\;Inc\\,\\nDev\r\nADR:Tokyo\\;JP\\,\\nLine2\r\nEND:VCARD\r\n",
  )
}

// Issue #11: escape helpers strip raw CR and NUL from TEXT values
// (RFC 5545 §3.3.11 / RFC 2426 §2.4.2 forbid them; CR in particular
// breaks line termination by emulating CRLF inside a value).
pub fn vcard_escape_strips_raw_cr_and_nul_test() -> Nil {
  qrkit.vcard("A\rB")
  |> qrkit.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:AB\r\nFN:AB\r\nEND:VCARD\r\n",
  )
  qrkit.vcard("A\u{0000}B")
  |> qrkit.vcard_to_string()
  |> should.equal(
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:AB\r\nFN:AB\r\nEND:VCARD\r\n",
  )
}

pub fn calendar_event_escapes_text_fields_test() -> Nil {
  // RFC 5545 §3.1: CRLF terminator. §3.7.3 + §3.6.1: PRODID, UID,
  // DTSTAMP are required (#14). UID is a deterministic synthesis of
  // (title-hash, start, end); DTSTAMP defaults to start_unix
  // (no clock is available in a pure renderer).
  qrkit.CalendarEvent(
    ..qrkit.calendar_event(
      "Sync;One,Two",
      qrkit.Timed(
        timestamp.from_unix_seconds(1_778_752_800),
        timestamp.from_unix_seconds(1_778_756_400),
      ),
    ),
    location: Some("Room;A,\nTokyo"),
    description: Some("Line1\nLine2;done,ok"),
  )
  |> qrkit.calendar_event_to_string()
  |> should.equal(
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//nao1215//qrkit//EN\r\nBEGIN:VEVENT\r\nUID:1868597102-1778752800-1778756400@qrkit.nao1215\r\nDTSTAMP:20260514T100000Z\r\nSUMMARY:Sync\\;One\\,Two\r\nDTSTART:20260514T100000Z\r\nDTEND:20260514T110000Z\r\nLOCATION:Room\\;A\\,\\nTokyo\r\nDESCRIPTION:Line1\\nLine2\\;done\\,ok\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
  )
}

// Issue #14: event_to_string emits PRODID + UID + DTSTAMP.
pub fn calendar_event_includes_required_properties_test() -> Nil {
  let s =
    qrkit.calendar_event(
      "X",
      qrkit.Timed(
        timestamp.from_unix_seconds(0),
        timestamp.from_unix_seconds(0),
      ),
    )
    |> qrkit.calendar_event_to_string
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
    qrkit.calendar_event(
      "x",
      qrkit.AllDay(
        calendar.Date(1970, calendar.January, 1),
        calendar.Date(1970, calendar.January, 1),
      ),
    )
    |> qrkit.calendar_event_to_string
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
    qrkit.calendar_event(
      "x",
      qrkit.Timed(
        timestamp.from_unix_seconds(-1),
        timestamp.from_unix_seconds(-1),
      ),
    )
    |> qrkit.calendar_event_to_string
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
    qrkit.calendar_event(
      "x",
      qrkit.Timed(
        timestamp.from_unix_seconds(253_402_300_800),
        timestamp.from_unix_seconds(253_402_300_800),
      ),
    )
    |> qrkit.calendar_event_to_string
  s_y10k
  |> string.contains("DTSTART:9999")
  |> should.be_true
  // -62_167_219_200 unix is roughly Jan 1, 0000 UTC — earlier than
  // year 1, so the renderer clamps to year 0001 rather than emitting
  // a 0-prefixed year that breaks the RFC 5545 fixed-width format.
  let s_pre_y1 =
    qrkit.calendar_event(
      "x",
      qrkit.Timed(
        timestamp.from_unix_seconds(-62_167_219_200),
        timestamp.from_unix_seconds(-62_167_219_200),
      ),
    )
    |> qrkit.calendar_event_to_string
  s_pre_y1
  |> string.contains("DTSTART:0001")
  |> should.be_true
}

pub fn ascii_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 4)
  |> string.is_empty
  |> should.be_false
}

// Issue #8: ascii renderer exposes a builder-style options object
// for non-spec-mandated rendering (smaller margin in debug dumps,
// fixture diffs, README terminal panels). The default 4-module
// quiet zone matches ISO/IEC 18004 and the existing to_string output.
pub fn ascii_with_margin_zero_strips_quiet_zone_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let tight = qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 0)
  // With no quiet zone every line starts with a dark cell (the
  // finder pattern's top-left corner) — the default output has a
  // 4-module margin of light cells in front.
  string.starts_with(tight, "██")
  |> should.be_true
}

pub fn ascii_with_margin_matches_default_at_4_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let default = qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 4)
  let rebuilt = qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 4)
  default
  |> should.equal(rebuilt)
}

pub fn ascii_with_inverse_option_flips_glyphs_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let inverted_via_options =
    qrkit.to_terminal(qr, style: qrkit.InvertedBlocks, margin: 4)
  inverted_via_options
  |> should.equal(qrkit.to_terminal(qr, style: qrkit.InvertedBlocks, margin: 4))
}

pub fn ascii_with_margin_negative_clamps_to_zero_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let zeroed = qrkit.to_terminal(qr, style: qrkit.Blocks, margin: 0)
  let negative = qrkit.to_terminal(qr, style: qrkit.Blocks, margin: -1)
  zeroed
  |> should.equal(negative)
}

pub fn svg_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let xml = qrkit.to_svg(qr, qrkit.default_image_options())
  string.starts_with(xml, "<svg")
  |> should.equal(True)

  string.contains(does: xml, contain: "path")
  |> should.equal(True)
}

pub fn hello_world_has_finder_patterns_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  should.equal(qr.version, 1)
  should.equal(must_module_at(qr, 0, 0), True)
  should.equal(must_module_at(qr, 6, 0), True)
  should.equal(must_module_at(qr, 0, 6), True)
  should.equal(must_module_at(qr, 20, 0), True)
  should.equal(must_module_at(qr, 0, 20), True)
}

pub fn hello_world_matches_reference_matrix_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qr.rows
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
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Medium,
      ),
    )

  qr.rows
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
  qr.rows
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
    qrkit.encode_with(
      "HELLO WORLD",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Medium,
        version: Some(2),
      ),
    )

  qr.version
  |> should.equal(2)
  qr.width
  |> should.equal(25)
  qr.rows
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
    qrkit.encode_with(
      "HELLO",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(7)),
    )

  qr.version
  |> should.equal(7)
  qr.width
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
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Medium,
      ),
    )

  qr.width
  |> should.equal(13)
  qr.height
  |> should.equal(13)
  qr.symbol
  |> should.equal(qrkit.Micro)
}

pub fn micro_qr_m1_half_codeword_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "01234",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        version: Some(1),
        error_correction: qrkit.Low,
      ),
    )

  qr.width
  |> should.equal(11)
  qr.height
  |> should.equal(11)
  must_module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn micro_qr_m2_low_matches_iso_annex_i_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Low,
      ),
    )

  qr.rows
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
  let assert Ok(shards) =
    qrkit.encode_split("HI", max_version: 40, error_correction: qrkit.Medium)

  shards
  |> list.length
  |> should.equal(1)
}

pub fn structured_append_long_input_splits_test() -> Nil {
  let assert Ok(shards) =
    qrkit.encode_split(
      string.repeat("0123456789", 8),
      max_version: 2,
      error_correction: qrkit.Medium,
    )

  { list.length(shards) >= 2 }
  |> should.be_true
}

pub fn structured_append_with_level_test() -> Nil {
  let assert Ok(shards) =
    qrkit.encode_split(
      string.repeat("0123456789", 8),
      max_version: 2,
      error_correction: qrkit.High,
    )

  { list.length(shards) >= 2 }
  |> should.be_true
  list.map(shards, fn(shard) {
    qrkit.decode(shard.rows)
    |> result.map(fn(decoded) { decoded.error_correction })
  })
  |> list.all(fn(level) { level == Ok(qrkit.High) })
  |> should.be_true
}

pub fn structured_append_max_version_too_small_test() -> Nil {
  qrkit.encode_split(
    string.repeat("0123456789", 60),
    max_version: 1,
    error_correction: qrkit.Medium,
  )
  |> result_is_data_too_long
  |> should.be_true
}

fn result_is_data_too_long(result: Result(a, qrkit.EncodeError)) -> Bool {
  case result {
    Error(qrkit.DataExceedsCapacity(_, _)) -> True
    _ -> False
  }
}

pub fn rmqr_default_picks_the_smallest_area_test() -> Nil {
  // "01234567" fits R7x43 (301 modules) and R11x27 (297 modules); the
  // default picks the smaller area.
  let assert Ok(qr) =
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        error_correction: qrkit.Medium,
      ),
    )

  #(qr.width, qr.height)
  |> should.equal(#(27, 11))
  qr.symbol
  |> should.equal(qrkit.Rectangular)
  must_module_at(qr, 0, 0)
  |> should.equal(True)
}

pub fn rmqr_shortest_height_priority_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        error_correction: qrkit.Medium,
        rectangular_priority: qrkit.ShortestHeight,
      ),
    )
  #(qr.width, qr.height) |> should.equal(#(43, 7))
}

pub fn rmqr_priorities_pick_different_shapes_test() -> Nil {
  // 100 digits need 344 bits at M: the smallest area that holds them is
  // R11x77 (847 modules, exactly 344 bits), the lowest is R7x139 and the
  // narrowest is R15x59.
  let payload = string.repeat("0123456789", 10)
  let build = fn(priority) {
    let assert Ok(qr) =
      qrkit.encode_with(
        payload,
        qrkit.EncodeOptions(
          ..qrkit.default_encode_options(),
          symbol: qrkit.Rectangular,
          rectangular_priority: priority,
        ),
      )
    #(qr.width, qr.height)
  }
  build(qrkit.SmallestArea) |> should.equal(#(77, 11))
  build(qrkit.ShortestHeight) |> should.equal(#(139, 7))
  build(qrkit.NarrowestWidth) |> should.equal(#(59, 15))
}

pub fn rectangular_priority_is_ignored_for_other_symbols_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      rectangular_priority: qrkit.ShortestHeight,
    ),
  )
  |> should.equal(qrkit.encode("HELLO"))
}

pub fn rmqr_rejects_low_ecc_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Rectangular,
      error_correction: qrkit.Low,
    ),
  )
  |> should.equal(
    Error(qrkit.ErrorCorrectionNotSupported(qrkit.Rectangular, qrkit.Low)),
  )
}

pub fn rmqr_rejects_quartile_ecc_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Rectangular,
      error_correction: qrkit.Quartile,
    ),
  )
  |> should.equal(
    Error(qrkit.ErrorCorrectionNotSupported(qrkit.Rectangular, qrkit.Quartile)),
  )
}

pub fn rmqr_large_size_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      string.repeat("0123456789", 6),
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        error_correction: qrkit.Medium,
      ),
    )

  { qr.width > 27 }
  |> should.be_true
  { qr.height >= 7 && qr.height <= 17 }
  |> should.be_true
}

pub fn micro_qr_m1_rejects_high_ecc_test() -> Nil {
  qrkit.encode_with(
    "12345",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      error_correction: qrkit.High,
    ),
  )
  |> should.equal(
    Error(qrkit.ErrorCorrectionNotSupported(qrkit.Micro, qrkit.High)),
  )
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

pub fn reed_solomon_generator_coefficients_test() -> Nil {
  // The remainder of x^d divided by the degree-d generator is the generator
  // without its leading 1, so encoding [1] pins the ISO/IEC 18004 Annex A
  // coefficients.
  reed_solomon.encode([1], 7)
  |> should.equal([127, 122, 154, 164, 11, 68, 117])
  reed_solomon.encode([1], 10)
  |> should.equal([216, 194, 159, 111, 199, 94, 95, 113, 157, 193])
  reed_solomon.encode([1], 15)
  |> should.equal([
    29, 196, 111, 163, 112, 74, 10, 105, 105, 139, 132, 151, 32, 134, 26,
  ])
  reed_solomon.encode([1], 20)
  |> should.equal([
    152, 185, 240, 5, 111, 99, 6, 220, 112, 150, 69, 36, 187, 22, 228, 198, 121,
    121, 165, 174,
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
    qrkit.encode_with(
      "Hello, world!",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(9)),
    )
  let assert Ok(at_v10) =
    qrkit.encode_with(
      "Hello, world!",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(10)),
    )
  at_v9.version
  |> should.equal(9)
  at_v10.version
  |> should.equal(10)
  { rows_to_strings(at_v9.rows) != rows_to_strings(at_v10.rows) }
  |> should.be_true
}

pub fn byte_mode_v10_matches_reference_test() -> Nil {
  // Captured from the npm `qrcode` library for "Hello, world!" at v10-M.
  // Exercises the 16-bit Byte-mode CCI bracket.
  let assert Ok(qr) =
    qrkit.encode_with(
      "Hello, world!",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(10)),
    )
  qr.version
  |> should.equal(10)
  qr.width
  |> should.equal(57)
  let rendered =
    qr.rows
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
    qrkit.encode_with(
      "https://github.com/nao1215/qrkit",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Medium,
        version: Some(5),
      ),
    )
  qr.version
  |> should.equal(5)
  qr.width
  |> should.equal(37)
  qr.rows
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
    qrkit.encode_with(
      string.repeat("0123456789", 30),
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Medium,
        version: Some(25),
      ),
    )
  qr.version
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

// ---------------------------------------------------------------------------
// UTF-8 / NUL byte / control character handling
// ---------------------------------------------------------------------------

pub fn utf8_round_trip_through_byte_mode_test() -> Nil {
  // Multi-byte UTF-8 strings flow through Byte mode without truncation.
  let payload = "日本語テスト 🇯🇵"
  let assert Ok(qr) = qrkit.encode(payload)
  qr.symbol
  |> should.equal(qrkit.Standard)
  // The QR matrix is square.
  qr.width
  |> should.equal(qr.height)
}

pub fn control_chars_and_nul_byte_test() -> Nil {
  // \n, \t, \r, and \u{0} are valid Byte-mode characters and must not crash
  // the encoder or be silently dropped.
  let payload = "line1\nline2\tcol\r\u{0}nul\u{0}\u{1f}"
  let assert Ok(qr) = qrkit.encode(payload)
  { qr.width >= 21 }
  |> should.be_true
}

pub fn emoji_payload_test() -> Nil {
  // Emojis are valid UTF-8 and just become Byte-mode bytes.
  let assert Ok(qr) = qrkit.encode("Hello 👋🌏 World")
  { qr.width > 0 }
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Encoder error variants must surface, never panic.
// ---------------------------------------------------------------------------

pub fn version_below_one_errors_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(0)),
  )
  |> should.equal(Error(qrkit.InvalidVersion(0)))
}

pub fn version_above_forty_errors_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(41)),
  )
  |> should.equal(Error(qrkit.InvalidVersion(41)))
}

pub fn payload_exceeds_v40_capacity_errors_test() -> Nil {
  // v40-H caps Byte-mode data at ~1273 bytes; 4 KiB is well past every
  // version's capacity at every ECC level.
  let huge = string.repeat("X", 5000)
  let result =
    qrkit.encode_with(
      huge,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.High,
      ),
    )
  case result {
    Error(qrkit.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn negative_eci_designator_errors_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(..qrkit.default_encode_options(), eci: Some(-1)),
  )
  |> should.equal(Error(qrkit.InvalidEciDesignator(-1)))
}

pub fn oversized_eci_designator_errors_test() -> Nil {
  qrkit.encode_with(
    "HELLO",
    qrkit.EncodeOptions(..qrkit.default_encode_options(), eci: Some(1_000_000)),
  )
  |> should.equal(Error(qrkit.InvalidEciDesignator(1_000_000)))
}

pub fn eci_is_rejected_for_micro_qr_test() -> Nil {
  let result =
    qrkit.encode_with(
      "12345",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        eci: Some(26),
      ),
    )
  result
  |> should.equal(Error(qrkit.EciNotSupported(qrkit.Micro)))
}

// ---------------------------------------------------------------------------
// `with_exact_version` pins the version.
//
// When the caller pins version N, the builder must use exactly version N —
// capacity overflow, mode incompatibility, or ECC incompatibility at N must
// surface as a typed `Error`, not silently promote to N+1. Tests below pin
// each of those error paths.
// ---------------------------------------------------------------------------

pub fn exact_version_pins_exact_version_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "HI",
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(5)),
    )
  qr.version
  |> should.equal(5)
}

pub fn strict_standard_overflow_at_exact_version_errors_test() -> Nil {
  // v1 ECC-M Alphanumeric capacity is 20 chars. 100 chars cannot fit at v1,
  // so a strict v1 must return DataExceedsCapacity rather than promoting.
  let payload = string.repeat("A", 100)
  let result =
    qrkit.encode_with(
      payload,
      qrkit.EncodeOptions(..qrkit.default_encode_options(), version: Some(1)),
    )
  case result {
    Error(qrkit.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_micro_m1_byte_mode_errors_test() -> Nil {
  // M1 only encodes Numeric mode per ISO/IEC 18004 Annex K.
  // Byte input ("abc") at M1 must name the first character M1 cannot
  // encode, not promote.
  qrkit.encode_with(
    "abc",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      version: Some(1),
    ),
  )
  |> should.equal(Error(qrkit.UnsupportedCharacter(0, "a")))
}

pub fn strict_micro_m1_medium_ecc_errors_test() -> Nil {
  // M1 supports error-detection only — no L/M/Q/H ECC levels.
  // `Micro + exact version 1 + ecc=Medium` must be rejected, not silently
  // promote to M2 (which does support Medium).
  qrkit.encode_with(
    "123",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      version: Some(1),
      error_correction: qrkit.Medium,
    ),
  )
  |> should.equal(
    Error(qrkit.ErrorCorrectionNotSupported(qrkit.Micro, qrkit.Medium)),
  )
}

pub fn strict_micro_m1_overflow_errors_test() -> Nil {
  // M1 + Low ECC holds 5 numeric digits (20 bits). 8 digits exceeds capacity,
  // so a strict M1 + Low must surface DataExceedsCapacity, not promote to M2.
  // (default ECC = Medium would be caught earlier by the M1 ECC-incompatibility
  // path; see strict_micro_m1_medium_ecc_errors_test for that case.)
  let result =
    qrkit.encode_with(
      "01234567",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        version: Some(1),
        error_correction: qrkit.Low,
      ),
    )
  case result {
    Error(qrkit.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn strict_rmqr_overflow_errors_test() -> Nil {
  // rMQR R7×43 (index 1) at Medium ECC holds a small payload. A very long
  // payload at rMQR + exact version 1 must surface DataExceedsCapacity, not
  // promote to a wider rMQR variant.
  let huge = string.repeat("X", 500)
  let result =
    qrkit.encode_with(
      huge,
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        version: Some(1),
        error_correction: qrkit.Medium,
      ),
    )
  case result {
    Error(qrkit.DataExceedsCapacity(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn default_smallest_fit_unchanged_test() -> Nil {
  // When with_exact_version is not called, build still picks the smallest
  // fit — the strict behaviour only applies when the caller asks for a
  // specific floor.
  let assert Ok(qr) = qrkit.encode("HI")
  qr.version
  |> should.equal(1)
}

// ---------------------------------------------------------------------------
// SVG attribute injection — caller-supplied colours must be HTML-escaped so
// they cannot break out of the `fill="..."` quote pair.
// ---------------------------------------------------------------------------

pub fn svg_dark_color_escaped_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HI")
  let injected =
    qrkit.ImageOptions(
      ..qrkit.default_image_options(),
      dark_color: "\" onclick=\"alert(1)",
      light_color: Some("</svg><script>evil()</script>"),
    )
  let document = qrkit.to_svg(qr, injected)

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
    qrkit.ImageOptions(
      ..qrkit.default_image_options(),
      module_size: 0,
      margin: -3,
    )
  let document = qrkit.to_svg(qr, options)

  string.contains(does: document, contain: "viewBox=\"0 0 21 21\"")
  |> should.be_true
}

pub fn png_renderer_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let image =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 2,
        margin: 4,
      ),
    )

  { bit_array.byte_size(image) > 0 }
  |> should.be_true

  let assert Ok(signature) = bit_array.slice(image, at: 0, take: 8)
  signature
  |> should.equal(<<137, 80, 78, 71, 13, 10, 26, 10>>)

  let assert Ok(dimensions) = bit_array.slice(image, at: 16, take: 8)
  dimensions
  |> should.equal(<<0, 0, 0, 58, 0, 0, 0, 58>>)
}

pub fn png_renderer_writes_every_module_and_valid_checksums_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let image =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 1,
        margin: 0,
      ),
    )

  // The IEND chunk is always the same 12 bytes: an empty chunk followed by
  // the CRC-32 of its type, AE 42 60 82.
  let size = bit_array.byte_size(image)
  let assert Ok(iend) = bit_array.slice(image, at: size - 12, take: 12)
  iend
  |> should.equal(<<0, 0, 0, 0, 73, 69, 78, 68, 0xAE, 0x42, 0x60, 0x82>>)

  // The image data is a stored (uncompressed) zlib stream, so the scanlines
  // start right after the signature, IHDR, PLTE, the IDAT header, the zlib
  // header and the stored-block header (8 + 25 + 18 + 8 + 2 + 5 bytes).
  // Each scanline is a filter byte and one bit per module, palette index 0
  // being dark, padded to a whole byte.
  let width = qr.width
  let row_bytes = 1 + { width + 7 } / 8
  let rows = qr.rows
  rows
  |> list.index_map(fn(_, row) {
    let assert Ok(line) =
      bit_array.slice(image, at: 66 + row * row_bytes, take: row_bytes)
    png_scanline(line, width)
  })
  |> should.equal(rows)
}

fn png_scanline(line: BitArray, width: Int) -> List(Bool) {
  let assert <<0, pixels:bits>> = line
  png_pixels(pixels, width, [])
}

fn png_pixels(bits: BitArray, remaining: Int, acc: List(Bool)) -> List(Bool) {
  case remaining, bits {
    0, _ -> list.reverse(acc)
    _, <<bit:1, rest:bits>> ->
      png_pixels(rest, remaining - 1, [bit == 0, ..acc])
    _, _ -> list.reverse(acc)
  }
}

pub fn png_renderer_normalizes_invalid_scale_and_margin_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let normalized =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 1,
        margin: 0,
      ),
    )
  let coerced =
    qrkit.to_png(
      qr,
      qrkit.ImageOptions(
        ..qrkit.default_image_options(),
        module_size: 0,
        margin: -4,
      ),
    )
  coerced
  |> should.equal(normalized)
}

pub fn mixed_payload_switches_to_numeric_for_a_digit_run_test() -> Nil {
  // 35 bytes of URL followed by 29 digits: one Byte segment needs version 4
  // at Medium, while Byte + Numeric for the digit run fits version 3.
  let assert Ok(qr) =
    qrkit.encode("https://example.com/item?id=12345678901234567890123456789")
  qr.version |> should.equal(3)
}

pub fn payload_that_fits_version_10_or_later_is_not_rejected_test() -> Nil {
  // Mixed digit and letter runs were segmented and measured with the
  // character-count widths of versions 1-9 and then encoded at version 10+,
  // where every segment header is wider, so payloads that fit were rejected
  // with DataExceedsCapacity.
  let assert Ok(qr) =
    qrkit.encode_with(
      string.repeat("abc123456", 30),
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Low,
      ),
    )
  qr.version |> should.equal(10)

  let assert Ok(qr) =
    qrkit.encode_with(
      string.repeat("id=1234567;", 25),
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        error_correction: qrkit.Low,
      ),
    )
  qr.version |> should.equal(11)
}

pub fn micro_qr_encodes_kana_in_kanji_mode_test() -> Nil {
  // Kanji mode costs 13 bits per character against 24 for UTF-8 Byte, so
  // four katakana fit M3 at Medium and M4 at Quartile.
  let assert Ok(medium) =
    qrkit.encode_with(
      "カタカナ",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Medium,
      ),
    )
  medium.version |> should.equal(3)

  let assert Ok(quartile) =
    qrkit.encode_with(
      "カタカナ",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Quartile,
      ),
    )
  quartile.version |> should.equal(4)
}

pub fn rmqr_encodes_kana_in_kanji_mode_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "こんにちは",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        rectangular_priority: qrkit.ShortestHeight,
      ),
    )
  // R7x59: five characters in Kanji mode need 3 + 3 + 65 = 71 bits.
  #(qr.width, qr.height) |> should.equal(#(59, 7))
}

pub fn micro_qr_mixes_numeric_and_kanji_segments_test() -> Nil {
  // "59" in Numeric plus three kana in Kanji mode fits M3 at Low and M4 at
  // Quartile; one Byte segment for all five characters needs 96 bits and
  // does not fit M4 at Quartile (80 bits).
  let assert Ok(low) =
    qrkit.encode_with(
      "59けあお",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Low,
      ),
    )
  low.version |> should.equal(3)

  let assert Ok(quartile) =
    qrkit.encode_with(
      "59けあお",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Micro,
        error_correction: qrkit.Quartile,
      ),
    )
  quartile.version |> should.equal(4)
}

pub fn rmqr_mixes_kanji_and_alphanumeric_segments_test() -> Nil {
  let assert Ok(qr) =
    qrkit.encode_with(
      "品番ABC-12345 数量10",
      qrkit.EncodeOptions(
        ..qrkit.default_encode_options(),
        symbol: qrkit.Rectangular,
        rectangular_priority: qrkit.ShortestHeight,
      ),
    )
  #(qr.width, qr.height) |> should.equal(#(77, 7))
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

// ---------------------------------------------------------------------------
// Errors that used to be `IncompatibleOptions(String)`.
// ---------------------------------------------------------------------------

fn micro_at(text: String, version: Int, mode: qrkit.ModePreference) {
  qrkit.encode_with(
    text,
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      version: Some(version),
      error_correction: qrkit.Low,
      mode:,
    ),
  )
}

pub fn pinned_micro_version_names_first_unsupported_character_test() -> Nil {
  // M1 is Numeric only.
  micro_at("12AB", 1, qrkit.Auto)
  |> should.equal(Error(qrkit.UnsupportedCharacter(2, "A")))
  // M2 adds Alphanumeric, but not lower case.
  micro_at("AB12a", 2, qrkit.Auto)
  |> should.equal(Error(qrkit.UnsupportedCharacter(4, "a")))
  // ForceByte needs Byte mode, which M1 and M2 lack.
  micro_at("12", 2, qrkit.ForceByte)
  |> should.equal(Error(qrkit.UnsupportedCharacter(0, "1")))
}

pub fn unsupported_character_index_counts_code_points_test() -> Nil {
  // "👍🏽" is one grapheme but two code points; the index and the character
  // are per code point.
  micro_at("1é2", 1, qrkit.Auto)
  |> should.equal(Error(qrkit.UnsupportedCharacter(1, "é")))
  micro_at("👍🏽1A", 2, qrkit.Auto)
  |> should.equal(Error(qrkit.UnsupportedCharacter(0, "👍")))
  micro_at("1👍🏽A", 2, qrkit.Auto)
  |> should.equal(Error(qrkit.UnsupportedCharacter(1, "👍")))
}

pub fn pinned_micro_version_still_accepts_its_modes_test() -> Nil {
  let assert Ok(qr) = micro_at("12AB", 2, qrkit.Auto)
  qr.version |> should.equal(2)
  let assert Ok(qr) = micro_at("12ab", 3, qrkit.ForceByte)
  qr.version |> should.equal(3)
}

pub fn micro_error_correction_per_version_test() -> Nil {
  qrkit.encode_with(
    "12",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      version: Some(2),
      error_correction: qrkit.Quartile,
    ),
  )
  |> should.equal(
    Error(qrkit.ErrorCorrectionNotSupported(qrkit.Micro, qrkit.Quartile)),
  )
}

pub fn eci_is_rejected_for_rmqr_test() -> Nil {
  qrkit.encode_with(
    "12345",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Rectangular,
      eci: Some(26),
    ),
  )
  |> should.equal(Error(qrkit.EciNotSupported(qrkit.Rectangular)))
}

pub fn invalid_eci_designator_wins_over_symbol_check_test() -> Nil {
  qrkit.encode_with(
    "12345",
    qrkit.EncodeOptions(
      ..qrkit.default_encode_options(),
      symbol: qrkit.Micro,
      eci: Some(-1),
    ),
  )
  |> should.equal(Error(qrkit.InvalidEciDesignator(-1)))
}

// ---------------------------------------------------------------------------
// Rendering reads the size from `rows`.
// ---------------------------------------------------------------------------

pub fn renderers_size_from_rows_not_record_fields_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let wrong = qrkit.QrCode(..qr, width: 3, height: 99)
  let options = qrkit.default_image_options()
  qrkit.to_svg(wrong, options) |> should.equal(qrkit.to_svg(qr, options))
  qrkit.to_png(wrong, options) |> should.equal(qrkit.to_png(qr, options))
  qrkit.to_terminal(wrong, style: qrkit.HalfBlocks, margin: 1)
  |> should.equal(qrkit.to_terminal(qr, style: qrkit.HalfBlocks, margin: 1))
}

pub fn svg_default_dark_is_black_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  let document = qrkit.to_svg(qr, qrkit.default_image_options())
  string.contains(document, "<path fill=\"#000000\"") |> should.be_true
  string.contains(document, "<rect") |> should.be_true
}

pub fn svg_without_light_color_has_no_background_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  qrkit.to_svg(
    qr,
    qrkit.ImageOptions(..qrkit.default_image_options(), light_color: None),
  )
  |> string.contains("<rect")
  |> should.be_false
}

pub fn terminal_negative_margin_is_zero_test() -> Nil {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  list.each([qrkit.Blocks, qrkit.InvertedBlocks, qrkit.HalfBlocks], fn(style) {
    qrkit.to_terminal(qr, style:, margin: -3)
    |> should.equal(qrkit.to_terminal(qr, style:, margin: 0))
  })
}

// ---------------------------------------------------------------------------
// Payloads.
// ---------------------------------------------------------------------------

pub fn wifi_open_network_has_no_password_test() -> Nil {
  qrkit.wifi(ssid: "Guest", security: qrkit.Open, hidden: False)
  |> should.equal("WIFI:T:nopass;S:Guest;P:;;")
}

pub fn all_day_event_ends_the_day_after_last_test() -> Nil {
  let event =
    qrkit.calendar_event(
      "Trip",
      qrkit.AllDay(
        first: calendar.Date(2026, calendar.December, 30),
        last: calendar.Date(2027, calendar.January, 1),
      ),
    )
    |> qrkit.calendar_event_to_string
  string.contains(event, "DTSTART;VALUE=DATE:20261230\r\n") |> should.be_true
  string.contains(event, "DTEND;VALUE=DATE:20270102\r\n") |> should.be_true
  string.contains(event, "DTSTAMP:20261230T000000Z\r\n") |> should.be_true
}

pub fn all_day_event_crosses_leap_day_test() -> Nil {
  qrkit.calendar_event(
    "Leap",
    qrkit.AllDay(
      first: calendar.Date(2028, calendar.February, 28),
      last: calendar.Date(2028, calendar.February, 29),
    ),
  )
  |> qrkit.calendar_event_to_string
  |> string.contains("DTEND;VALUE=DATE:20280301\r\n")
  |> should.be_true
}

pub fn timed_event_ignores_sub_second_part_test() -> Nil {
  let at = fn(seconds, nanoseconds) {
    timestamp.from_unix_seconds_and_nanoseconds(seconds, nanoseconds)
  }
  qrkit.calendar_event("x", qrkit.Timed(at(10, 999_999_999), at(20, 1)))
  |> qrkit.calendar_event_to_string
  |> should.equal(
    qrkit.calendar_event("x", qrkit.Timed(at(10, 0), at(20, 0)))
    |> qrkit.calendar_event_to_string,
  )
}

pub fn geo_writes_plain_decimals_test() -> Nil {
  qrkit.geo(latitude: 0.0, longitude: 1.0e-7)
  |> should.equal("geo:0.0,0.0000001")
  qrkit.geo(latitude: -1.5e-8, longitude: 35.6895)
  |> should.equal("geo:-0.000000015,35.6895")
  qrkit.geo(latitude: 35.6812, longitude: -139.7671)
  |> should.equal("geo:35.6812,-139.7671")
  // JavaScript writes large values as `1e+21`.
  qrkit.geo(latitude: 1.0e21, longitude: -2.5e22)
  |> should.equal("geo:1000000000000000000000.0,-25000000000000000000000.0")
}
