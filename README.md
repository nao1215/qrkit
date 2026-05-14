# qrkit

[![CI](https://github.com/nao1215/qrkit/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/ci.yml)

`qrkit` is a pure Gleam QR code generator for Erlang and JavaScript
targets.

Current support:

- Standard QR Code symbols (`version 1..40`) with ECC levels `L`, `M`, `Q`,
  `H` and Numeric / Alphanumeric / Byte (UTF-8) / Kanji (Shift_JIS) modes
- Micro QR Code symbols (`M1`..`M4`) via `qrkit.with_symbol(error.Micro)`
- rMQR Code symbols (32 sizes, ISO/IEC 23941) via
  `qrkit.with_symbol(error.Rectangular)`
- Structured Append (`qrkit.encode_split/2`) for splitting long input into
  up to 16 chained symbols
- Terminal rendering (`ascii`)
- Browser rendering (`svg`)
- PNG rendering as raw `BitArray` bytes
- Content helpers for URL, WiFi, vCard, mail, SMS, phone, geo, and
  calendar payloads

`src/qrkit/internal/*` is internal implementation detail and has no API
stability guarantee.

## Installation

```sh
gleam add qrkit
```

## Quick Start

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  io.println(ascii.to_string(qr))
}
```

## Builder API

Error correction constructors currently live in `qrkit/error`.

```gleam
import qrkit
import qrkit/error

pub fn main() {
  let assert Ok(qr) =
    qrkit.new("https://nao1215.dev")
    |> qrkit.with_ecc(error.Quartile)
    |> qrkit.with_min_version(3)
    |> qrkit.with_eci(26)
    |> qrkit.build()

  qrkit.version(qr)
}
```

## Terminal Rendering

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("HELLO WORLD")
  io.println(ascii.to_string(qr))
}
```

## SVG Rendering

```gleam
import qrkit
import qrkit/render/svg

pub fn render() -> String {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  svg.to_string(qr, svg.default_options())
}
```

The returned string can be embedded in HTML directly. In Lustre, for
example, you could pass it to an unsafe HTML helper after sanitising it
for your environment.

## PNG Rendering

```gleam
import qrkit
import qrkit/render/png

pub fn render() -> BitArray {
  let assert Ok(qr) = qrkit.encode("https://nao1215.dev")
  png.to_bit_array(qr, scale: 8, margin: 4)
}
```

On Erlang you can write the returned bytes with a file helper such as
`simplifile.write_bits`.

## WiFi Payloads

```gleam
import qrkit
import qrkit/content
import qrkit/render/svg

pub fn wifi_svg() -> String {
  let payload = content.wifi(
    ssid: "MyAP",
    password: "secret",
    security: content.Wpa2,
    hidden: False,
  )
  let assert Ok(qr) = qrkit.encode(payload)
  svg.to_string(qr, svg.default_options())
}
```

## Micro QR

```gleam
import qrkit
import qrkit/error
import qrkit/render/svg

pub fn name_card_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(error.Micro)
    |> qrkit.with_min_version(2)
    |> qrkit.with_ecc(error.Low)
    |> qrkit.build()

  svg.to_string(qr, svg.default_options())
}
```

## Structured Append

```gleam
import qrkit

pub fn split_long_message() -> List(qrkit.QrCode) {
  let assert Ok(shards) =
    qrkit.encode_split(
      "A very long message that does not fit in a single small QR code"
        <> " so we split it across several chained symbols.",
      2,
    )

  shards
}
```

`encode_split/2` follows ISO/IEC 18004 §8.2: each returned symbol carries
the 20-bit Structured Append header (mode `0011` + index + total − 1 +
parity byte) so a compliant reader can reassemble the original message.

## Content Helpers

- `content.url/1`
- `content.wifi/4`
- `content.vcard/0` and `content.vcard_to_string/1`
- `content.email/3`
- `content.sms/2`
- `content.geo/2`
- `content.phone/1`
- `content.event/3` and `content.event_to_string/1`

## Development

This repository uses [`mise`](https://mise.jdx.dev/) for toolchain
pinning and [`just`](https://github.com/casey/just) for common tasks.

```sh
mise trust .mise.toml
mise install
just deps
just ci
just docs
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full development
workflow.

## License

MIT
