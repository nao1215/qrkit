# qrkit

[![CI](https://github.com/nao1215/qrkit/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/qrkit/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/qrkit/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/qrkit/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/qrkit/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/qrkit)](https://hex.pm/packages/qrkit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/qrkit/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/qrkit)](https://hex.pm/packages/qrkit)
[![License](https://img.shields.io/github/license/nao1215/qrkit)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/qrkit/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/qrkit)

Pure-Gleam QR code generator and decoder for the Erlang and JavaScript targets.

It covers Standard QR (versions 1 to 40, ECC L/M/Q/H), Micro QR (M1 to M4), rMQR (ISO/IEC 23941, 32 sizes) and Structured Append, with Kanji mode for all of JIS X 0208 and segmentation that picks the fewest bits. It renders to the terminal, SVG and PNG, decodes module matrices with Reed-Solomon error correction, and builds URL, WiFi, vCard, email, SMS, phone, geo and calendar payloads.

The QR below was rendered by qrkit and points to the project's GitHub Sponsors page.

![Sponsor nao1215](https://raw.githubusercontent.com/nao1215/qrkit/main/docs/images/sponsor-qr.png)

```sh
gleam add qrkit
```

## Hello, QR

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  io.println(ascii.to_string(qr))
}
```

`qrkit.encode/1` picks the smallest version that fits and uses ECC level Medium. The renderers in `qrkit/render/*` turn the opaque `QrCode` into output.

## Builder for ECC, exact version, and ECI

```gleam
import qrkit
import qrkit/types

pub fn high_density_qr() -> qrkit.QrCode {
  let assert Ok(qr) =
    qrkit.new("https://github.com/sponsors/nao1215")
    |> qrkit.with_ecc(types.Quartile)
    |> qrkit.with_exact_version(4)
    |> qrkit.with_eci(26)
    |> qrkit.build()
  qr
}
```

`with_exact_version` pins the symbol version; `build` returns `Error(DataExceedsCapacity)` or `Error(IncompatibleOptions)` if the payload, mode or ECC level does not fit there. `with_eci` prepends an Extended Channel Interpretation header (26 for UTF-8) and works on Standard QR only.

## Render as SVG for the browser

```gleam
import qrkit
import qrkit/render/svg

pub fn render_svg() -> String {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  svg.to_string(qr)
}
```

The result is a complete `<svg>` document. The SVG builder changes size, margin and colours:

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

  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  svg.to_string_with(qr, options)
}
```

## Write a PNG to disk

```gleam
import qrkit
import qrkit/render/png

pub fn render_png_bytes() -> BitArray {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  png.to_bit_array(qr, scale: 8, margin: 4)
}
```

`png.to_bit_array/3` returns raw PNG bytes. On the Erlang target, `simplifile` can write them:

```gleam
import qrkit
import qrkit/render/png
import simplifile

pub fn save_png() -> Result(Nil, simplifile.FileError) {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  png.to_bit_array(qr, scale: 8, margin: 4)
  |> simplifile.write_bits("qr.png", _)
}
```

## ASCII for the terminal

`ascii.to_string/1` draws `██` full blocks with a 4-module quiet zone. `ascii.to_string_compact/1` uses `▀`/`▄` half-blocks at half the height, and `ascii.with_inverse/1` swaps light and dark for dark-themed terminals.

```gleam
import gleam/io
import qrkit
import qrkit/render/ascii

pub fn main() {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  io.println(ascii.to_string_compact(qr))
}
```

It prints the following (the blank lines above and below are the quiet zone):

```
                                     
                                     
    █▀▀▀▀▀█ ▄ ▀ █▄▀  ▀██▄ █▀▀▀▀▀█    
    █ ███ █  █▄▀█▄ ▀  █▀  █ ███ █    
    █ ▀▀▀ █ ▀█ ▀▄▀▄▄▀  █  █ ▀▀▀ █    
    ▀▀▀▀▀▀▀ ▀ ▀ █ ▀▄▀▄█▄▀ ▀▀▀▀▀▀▀    
    █▄▀▄▀▄▀▄ █▀▀▀▄ ▄▄▀  ▄ ▄ ▀▄ ▀▄    
    █▄▄ ▄ ▀█  ▀▀█▄█▄ █▄  ▀▀▄█ ▀█▀    
    ▄▄▀▀  ▀█ ▄▄ █ █▀▄█▄ ▄██  █ ▀█    
     ▄█▀▄▄▀ ▀▀▀▀ ▀ ▄▀█▀ ▄▄█ ▀█ █▀    
    ▀▀▀▄▄▀▀ ▄▀█▀ ▄ ▄ █▄▀▀▄█▀ █▄▀█    
    ▀▄▀▀▄█▀▀ ▀▀ ▄▄█▄▀██▄▄█▄██▄ █▀    
    ▀  ▀▀▀▀ █▀▀▀  █▄ ▀▀██▀▀▀█ ▄▄▄    
    █▀▀▀▀▀█  ██▀▄▀  ▄█▄▀█ ▀ ██ ▀█    
    █ ███ █ ▀▀█▀█▄ ▀█▀  █▀▀██ ▄▀     
    █ ▀▀▀ █ ▀█▄▄█  ▄ █ █▄▄ ▀█▀ ▄▀    
    ▀▀▀▀▀▀▀ ▀   ▀ ▀ ▀▀ ▀▀▀ ▀▀  ▀▀    
                                     
                                     
```

## Payload helpers

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
  svg.to_string(qr)
}
```

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

```gleam
import qrkit
import qrkit/content

pub fn meeting_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  // 2026-05-14 10:00 UTC, ends 11:00 UTC.
  content.event(title: "Sync", start_unix: 1_778_752_800, end_unix: 1_778_756_400)
  |> content.with_location("Online")
  |> content.with_description("Project sync meeting")
  |> content.event_to_string
  |> qrkit.encode
}
```

## Inspect the matrix

```gleam
import qrkit
import qrkit/types

pub fn describe(qr: qrkit.QrCode) -> #(Int, Int, String, Bool) {
  let assert Ok(top_left) = qrkit.module_at(qr, 0, 0)
  #(
    qrkit.version(qr),
    qrkit.width(qr),
    qrkit.error_correction_designator(qrkit.error_correction(qr)),
    top_left,
  )
}

pub fn ecc_letter_for_quartile() -> String {
  qrkit.error_correction_designator(types.Quartile)
  // -> "Q"
}
```

`qrkit.rows/1` returns the matrix as `List(List(Bool))` for custom renderers. `qrkit.module_at/3` returns `Error(ModuleOutOfBounds(..))` for coordinates outside the symbol.

## Decode a module matrix

`qrkit/decode` reads a Standard QR, Micro QR or rMQR symbol from rows of modules (the shape `qrkit.rows` returns) and corrects damaged codewords. It strips a light quiet zone, reads rotated and mirrored symbols, and reads Byte data as ISO-8859-1 under ECI 1 or 3, Shift JIS under ECI 20 and UTF-8 under ECI 26. With any other ECI, or none, it guesses between UTF-8, Shift JIS and ISO-8859-1 as zxing does.

```gleam
import qrkit
import qrkit/decode

pub fn round_trip() -> Result(String, qrkit.DecodeError) {
  let assert Ok(qr) = qrkit.encode("https://github.com/sponsors/nao1215")
  case decode.from_rows(qrkit.rows(qr)) {
    Ok(decoded) -> Ok(decode.text(decoded))
    Error(error) -> Error(error)
  }
}
```

`decode.errors_corrected`, `decode.error_correction`, `decode.version`, `decode.eci` and `decode.structured_append` report what was read. Errors are `NotASymbol(width, height)`, `UnreadableFormatInformation`, `TooManyErrors` and `MalformedData(reason)` in `qrkit/error`.

## Micro QR, rMQR and Structured Append

Many consumer scanner apps cannot read Micro QR or rMQR, and some decode Structured Append symbols one by one without joining them. Test the target reader first.

Micro QR fits a small payload into 11×11 to 17×17 modules. M1 takes Numeric only, M2 adds Alphanumeric, and M3 and M4 take all four modes. ECC levels follow ISO/IEC 18004 Annex K: M1 has error detection only, and M4 goes up to Quartile.

```gleam
import qrkit
import qrkit/types
import qrkit/render/svg

pub fn business_card_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("01234567")
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_exact_version(2)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build()

  svg.to_string(qr)
}
```

rMQR (ISO/IEC 23941) has 32 rectangular sizes from 7×43 to 17×139, with Medium and High error correction only.

```gleam
import qrkit
import qrkit/types
import qrkit/render/svg

pub fn label_qr() -> String {
  let assert Ok(qr) =
    qrkit.new("https://github.com/sponsors/nao1215")
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.with_rectangular_priority(types.ShortestHeight)
    |> qrkit.build()

  svg.to_string(qr)
}
```

By default `build` picks the size with the fewest modules (`types.SmallestArea`). `types.ShortestHeight` picks the lowest symbol, `types.NarrowestWidth` the narrowest, and `with_exact_version` pins one size.

`qrkit.encode_split(data, max_version)` splits a payload across up to 16 symbols, each with the ISO/IEC 18004 §8.2 Structured Append header (mode indicator, symbol position, total − 1, parity byte).

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

If the payload fits in one symbol at `max_version`, the list holds a single QR without the header.

## Force a single encoding mode

`with_mode_preference(types.ForceByte)` skips segmentation and encodes the whole string as bytes.

```gleam
import qrkit
import qrkit/types

pub fn raw_byte_qr() -> Result(qrkit.QrCode, qrkit.EncodeError) {
  qrkit.new("123-ABC")
  |> qrkit.with_mode_preference(types.ForceByte)
  |> qrkit.build()
}
```

## Errors

Every encoding function returns `Result(_, qrkit.EncodeError)` instead of crashing. The variants live in `qrkit/error`:

- `EmptyInput`: empty `data`.
- `InvalidVersion(requested)`: version outside the symbol family.
- `InvalidEciDesignator(designator)`: ECI assignment number outside `0..999999`.
- `DataExceedsCapacity(bits_needed, bits_available)`: payload does not fit.
- `UnsupportedCharacter(at_index, character)`: a character the chosen mode cannot encode.
- `IncompatibleOptions(reason)`: combination not allowed, such as rMQR with Low ECC.

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

`qrkit.EncodeError` is a type alias, and Gleam aliases do not carry constructors, so match the variants through `qrkit/error`. The constructors of `ErrorCorrection`, `Symbol` and `ModePreference` likewise live in `qrkit/types`.

CI tests both the Erlang and JavaScript targets. PNG rendering and Reed-Solomon are pure Gleam, with no NIF or native binary.

API reference: <https://hexdocs.pm/qrkit/>.

## Scope and non-goals

- qrkit decodes module matrices, not photos. Finding a symbol in an image (detection, perspective correction, thresholding) is out of scope.
- Kanji mode covers the characters of JIS X 0208. Characters outside it (CP932 extensions such as circled digits, and JIS X 0213 additions) are encoded in Byte mode as UTF-8.
- Model 1 QR (the pre-1997 specification) is not implemented; only Model 2 (ISO/IEC 18004:2015), Micro QR, and rMQR.
- The encoder does not normalise input: no trimming, no Unicode normalisation, no `\r\n` ↔ `\n` rewrites, no NUL truncation. What you pass is what a reader decodes.
- Whether a symbol scans also depends on quiet zone, contrast, module size, print scale, medium and scanner. Test on the target devices.

## Safety notes

- qrkit does not check the payload. A `javascript:` URI, an otpauth secret or attacker-controlled text reaches the scanning app as is, so validate before encoding.
- The SVG renderer escapes `dark_color` and `light_color` so they cannot break out of the `fill="..."` attribute, and does no other escaping. Run the output through a sanitiser such as DOMPurify before embedding it in untrusted HTML.
- `EncodeError` never contains the payload, except `UnsupportedCharacter`, which reports the offending character. Handle that error before logging if the payload is secret, such as a TOTP seed.

## Testing

| Technique | Bug class caught here |
|---|---|
| Examples and unit tests | [Wrong matrices, capacities and errors](doc/testing.md#examples-and-unit-tests) |
| Generated properties | [Round trips that lose data, uncorrected damage, decoder crashes](doc/testing.md#generated-properties) |
| Metamorphic relations | [Wrong size choice, orientation and quiet zone handling](doc/testing.md#metamorphic-relations) |
| Snapshots | [Unreviewed changes to symbols and rendered output](doc/testing.md#snapshots) |
| Differential testing | [Symbols other readers cannot read, misread foreign symbols](doc/testing.md#differential-testing) |
| Mutation testing | [Assertions that miss a changed operator or branch](doc/testing.md#mutation-testing) |

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`qrkit-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`qrkit-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify qrkit-<version>.tar --repo nao1215/qrkit

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/qrkit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](LICENSE)
