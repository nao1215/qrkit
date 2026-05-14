# qrkit

[![Package Version](https://img.shields.io/hexpm/v/qrkit)](https://hex.pm/packages/qrkit)
[![Downloads](https://img.shields.io/hexpm/dt/qrkit)](https://hex.pm/packages/qrkit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/qrkit/)
[![CI](https://github.com/nao1215/qrkit/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/nao1215/qrkit)](LICENSE)

Pure-Gleam QR code generator for the Erlang and JavaScript targets.

Covers Standard QR (versions 1–40, ECC L/M/Q/H), Micro QR (M1–M4), rMQR (ISO/IEC 23941, 32 sizes), and Structured Append. Ships with terminal, SVG, and PNG renderers and content helpers for URL, WiFi, vCard, email, SMS, phone, geo, and calendar payloads.

The QR below points to the project's GitHub Sponsors page. Try scanning it with your phone — every example in this README was used to render it.

![Sponsor nao1215](docs/images/sponsor-qr.png)

```sh
gleam add qrkit
```

## Hello, QR

The shortest possible path: encode a string and print it to the terminal.

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  io.println(ascii.to_string(qr))
}
```

`qrkit.encode/1` picks the smallest version that fits and defaults to ECC level Medium. The returned `QrCode` is opaque — use the renderers in `qrkit/render/*` to turn it into pixels.

## Builder for ECC, version, and ECI

```gleam
import qrkit
import qrkit/error

pub fn high_density_qr() -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_ecc(error.Quartile)
    |> qrkit.with_min_version(3)
    |> qrkit.with_eci(26)
    |> qrkit.build()
  qr
}
```

`with_ecc` selects an error correction level, `with_min_version` raises the minimum version (handy when you want a fixed size), and `with_eci` prepends an Extended Channel Interpretation header (26 for UTF-8).

## Render as SVG for the browser

```gleam
import qrkit
import qrkit/render/svg

pub fn render_svg() -> String {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  svg.to_string(qr, svg.default_options())
}
```

The returned string is a complete `<svg>` document. Drop it into any HTML template; in Lustre, pass it to an unsafe-HTML helper after sanitising for your environment. Customise the look with the SVG builder:

```gleam
import qrkit
import qrkit/render/svg

pub fn dark_themed_svg() -> String {
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
```

## Write a PNG to disk

```gleam
import qrkit
import qrkit/render/png

pub fn render_png_bytes() -> BitArray {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  png.to_bit_array(qr, scale: 8, margin: 4)
}
```

`png.to_bit_array/3` returns raw PNG bytes. On the Erlang target a file IO library such as `simplifile` writes them to disk in one call:

```gleam
import qrkit
import qrkit/render/png
import simplifile

pub fn save_png() -> Result(Nil, simplifile.FileError) {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  png.to_bit_array(qr, scale: 8, margin: 4)
  |> simplifile.write_bits("qr.png", _)
}
```

## ASCII for the terminal

`ascii.to_string/1` uses `██` full blocks with a 4-module quiet zone. `ascii.to_string_compact/1` halves the vertical size by using `▀`/`▄` half-blocks (the most compact for LLM chat windows and narrow terminals), and `ascii.with_inverse/1` swaps light and dark for dark-themed terminals.

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  io.println(ascii.to_string_compact(qr))
}
```

Running the snippet above prints (the leading / trailing blank lines are the 4-module quiet zone QR readers need):

```


    █▀▀▀▀▀█  ███▀  ▀▀█▀▀█ █▀▀▀▀▀█
    █ ███ █ █ █▀▀ ▀ ▀▄▀█▀ █ ███ █
    █ ▀▀▀ █ █▄▄▄████▄▄▄▀▀ █ ▀▀▀ █
    ▀▀▀▀▀▀▀ █▄▀ ▀▄▀▄█ ▀ ▀ ▀▀▀▀▀▀▀
    █ █▀██▀▄▄█▄█▀ ▀▀▀█▄▄█ ███▀▀ ▄
    █ ▀ ▀▄▀█▀█▄▀█ ▄█▀▀ ▄▀   ▀▄ ▄
     ▄▄▄▀▀▀▀▄▄  ▄▄▄▀▀▀ ▄█▄▄▄▄▀▀ ▄
    ▄ ▄█▀▄▀██▄▄█▄█▀▀ ▀█▄██▄▄█▀▀▄
    ▄ ▀██ ▀ ▀▄▄ ▀ ▀▀▀▀ █ █▄█▄▀█ ▄
    █ ▄█▄ ▀  ▀▀█  ▄█▀▀▀ █▄█▀▀ ▀▄
    ▀    ▀▀ ▄ ▀█▄▄▄▀▀██▀█▀▀▀█▄███
    █▀▀▀▀▀█ ▄▄ ███▀▀█▀ ██ ▀ █▀▀ ▄
    █ ███ █ █▀ █▀▄▀ ▄█▄▄█▀▀▀▀▄██▄
    █ ▀▀▀ █ ▀▄█▄▄▀▀█▀▀▄▀██▀█▀█▀█
    ▀▀▀▀▀▀▀ ▀▀▀ ▀▀ ▀ ▀ ▀  ▀▀▀ ▀


```

This block is scannable directly from the terminal screen with a phone camera — the QR decodes to https://github.com/sponsors/nao1215. For dark-themed terminals call `ascii.with_inverse(qr)` instead, and for double-width pixels use `ascii.to_string(qr)`.

## WiFi credentials

```gleam
import qrkit
import qrkit/content
import qrkit/render/svg

pub fn wifi_qr_svg() -> String {
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
```

Phones recognise the `WIFI:` payload and offer a one-tap "join network" prompt.

## vCard, email, SMS, phone, geo

```gleam
import qrkit
import qrkit/content

pub fn contact_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.vcard()
  |> content.with_name("Naohiro Chikamatsu")
  |> content.with_email("nao@example.com")
  |> content.with_phone("+81-90-0000-0000")
  |> content.with_url("https://github.com/nao1215")
  |> content.vcard_to_string
  |> qrkit.encode
}

pub fn mail_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.email(to: "you@example.com", subject: "Hi", body: "Quick note")
  |> qrkit.encode
}

pub fn sms_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.sms(to: "+819000000000", body: "Hello!") |> qrkit.encode
}

pub fn phone_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.phone("+819000000000") |> qrkit.encode
}

pub fn map_pin_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  content.geo(latitude: 35.6812, longitude: 139.7671) |> qrkit.encode
}
```

## Calendar invite

```gleam
import qrkit
import qrkit/content

pub fn meeting_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  // 2026-05-14 10:00 UTC, ends 11:00 UTC.
  content.event("Sync", 1_778_745_600, 1_778_749_200)
  |> content.with_location("Online")
  |> content.with_description("Project sync meeting")
  |> content.event_to_string
  |> qrkit.encode
}
```

## Inspect the matrix

The `QrCode` type is opaque, but every useful field is accessible through a small inspector API.

```gleam
import qrkit
import qrkit/error

pub fn describe(qr: qrkit.QrCode) -> #(Int, Int, String, Bool) {
  #(
    qrkit.version(qr),
    qrkit.size(qr),
    qrkit.error_correction_designator(qrkit.error_correction(qr)),
    qrkit.module_at(qr, 0, 0),
  )
}

pub fn ecc_letter_for_quartile() -> String {
  qrkit.error_correction_designator(error.Quartile)
  // -> "Q"
}
```

`qrkit.rows/1` returns the matrix as `List(List(Bool))` for custom renderers.

## Micro QR

Micro QR squeezes a small payload into 11×11 — 17×17 modules. M1 takes Numeric only; M2 adds Alphanumeric; M3 and M4 take all four modes. ECC level constraints follow ISO/IEC 18004 Annex K (M1 has error detection only, M4 supports up to Quartile).

```gleam
import qrkit
import qrkit/error
import qrkit/render/svg

pub fn business_card_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_min_version(2)
    |> qrkit.with_ecc(error.Low)
    |> qrkit.build()

  svg.to_string(qr, svg.default_options())
}
```

## rMQR (rectangular Micro QR)

ISO/IEC 23941 defines 32 rectangular sizes from 7×43 to 17×139, with only Medium and High error correction levels. Useful for narrow labels and packaging.

```gleam
import qrkit
import qrkit/error
import qrkit/render/svg

pub fn label_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_symbol(error.Rectangular)
    |> qrkit.with_ecc(error.Medium)
    |> qrkit.build()

  svg.to_string(qr, svg.default_options())
}
```

## Structured Append

`qrkit.encode_split(data, max_version)` chains up to 16 symbols so a single payload can be carried across multiple printed QR codes. Each returned symbol carries the ISO/IEC 18004 §8.2 header (mode indicator + symbol position + total − 1 + parity byte) so a compliant reader can stitch them back together.

```gleam
import gleam/list
import qrkit
import qrkit/render/ascii

pub fn split_long_message() -> List(String) {
  let payload = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

  let assert Ok(shards) = qrkit.encode_split(payload, 2)
  list.map(shards, ascii.to_string)
}
```

When the payload already fits in one symbol at `max_version`, the returned list contains a single QR without the Structured Append header.

## Force a single encoding mode

`with_mode_preference(qrkit.ForceByte)` skips the segmenting optimiser and encodes the whole string as raw bytes — useful when you need a deterministic mode regardless of the input.

```gleam
import qrkit
import qrkit/error

pub fn raw_byte_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.new("123-ABC")
  |> qrkit.with_mode_preference(error.ForceByte)
  |> qrkit.build()
}
```

## Errors

Every public entry point returns `Result(_, qrkit.EncodeError)`. The variants are:

- `EmptyInput` — empty `data`.
- `InvalidVersion(requested)` — version outside the symbol family.
- `DataExceedsCapacity(bits_needed, bits_available)` — payload does not fit.
- `UnsupportedCharacter(at_index, character)` — a character the chosen mode cannot encode.
- `IncompatibleOptions(reason)` — combination not allowed (for example, rMQR with Low ECC).

```gleam
import qrkit
import qrkit/error

pub fn rejected() -> Bool {
  case qrkit.encode("") {
    Error(error.EmptyInput) -> True
    _ -> False
  }
}
```

## Targets

Both the Erlang and JavaScript targets are exercised in CI on every push. Pure-Gleam internals mean no NIF / native binary is needed for PNG rendering or Reed-Solomon — `qrkit` runs anywhere Gleam runs.

Full API reference: <https://hexdocs.pm/qrkit/>.

## License

[MIT](LICENSE)
