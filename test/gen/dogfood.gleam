//// Mini sample apps that exercise the qrkit API surface. Run via
//// `gleam run -m gen/dogfood`. Each function corresponds to a real-world use
//// case and writes a QR to `/tmp/qr-decode/dogfood/` for scanability checks.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import qrkit
import qrkit/content
import qrkit/render/ascii
import qrkit/render/png
import qrkit/render/svg
import qrkit/types
import simplifile

const out_dir: String = "/tmp/qr-decode/dogfood"

fn save_png(name: String, qr: qrkit.QrCode) -> Nil {
  let bytes = png.to_bit_array(qr, scale: 8, margin: 4)
  let assert Ok(Nil) = simplifile.write_bits(out_dir <> "/" <> name, bytes)
  Nil
}

// ---------------------------------------------------------------------------
// App 1: business card maker.
// ---------------------------------------------------------------------------

fn app_business_card() -> Nil {
  io.println("== App 1: business card ==")
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

  io.println("payload length: " <> int.to_string(string.length(payload)))
  let assert Ok(qr) =
    qrkit.new(payload) |> qrkit.with_ecc(types.Quartile) |> qrkit.build
  io.println(
    "qr version="
    <> int.to_string(qrkit.version(qr))
    <> " size="
    <> int.to_string(qrkit.size(qr)),
  )
  save_png("business_card.png", qr)
}

// ---------------------------------------------------------------------------
// App 2: WiFi credentials with special chars.
// ---------------------------------------------------------------------------

fn app_wifi_special_chars() -> Nil {
  io.println("== App 2: WiFi with special chars ==")
  let payload =
    content.wifi(
      ssid: "Cafe \"Espresso\" 2026",
      password: "P@ssw0rd!#;:,",
      security: content.Wpa2,
      hidden: False,
    )
  io.println("payload: " <> payload)
  let assert Ok(qr) = qrkit.encode(payload)
  save_png("wifi_special.png", qr)
}

// ---------------------------------------------------------------------------
// App 3: terminal-style URL share (multi format).
// ---------------------------------------------------------------------------

fn app_share_url_three_ways() -> Nil {
  io.println("== App 3: share URL three ways ==")
  let url = "https://github.com/nao1215/qrkit"
  let assert Ok(qr) = qrkit.encode(url)

  io.println("ascii preview (first 5 lines):")
  ascii.to_string_compact(qr)
  |> string.split(on: "\n")
  |> list.take(5)
  |> list.each(io.println)

  let svg_doc = svg.to_string(qr, svg.default_options())
  io.println("svg length: " <> int.to_string(string.length(svg_doc)))

  save_png("share_url.png", qr)
}

// ---------------------------------------------------------------------------
// App 4: structured-append printout.
// ---------------------------------------------------------------------------

fn app_structured_append() -> Nil {
  io.println("== App 4: long text via Structured Append ==")
  let payload =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation."
  let assert Ok(shards) = qrkit.encode_split(payload, 5)
  io.println("shard count: " <> int.to_string(list.length(shards)))
  list.index_map(shards, fn(qr, idx) {
    save_png("sa_" <> int.to_string(idx) <> ".png", qr)
    Nil
  })
  Nil
}

// ---------------------------------------------------------------------------
// App 5: rMQR label.
// ---------------------------------------------------------------------------

fn app_rmqr_label() -> Nil {
  io.println("== App 5: rMQR product label ==")
  let payload = "PROD-2026-0042"
  let assert Ok(qr) =
    qrkit.new(payload)
    |> qrkit.with_symbol(types.Rectangular)
    |> qrkit.with_ecc(types.Medium)
    |> qrkit.build
  io.println(
    "rMQR dims="
    <> int.to_string(qrkit.width(qr))
    <> "x"
    <> int.to_string(qrkit.height(qr)),
  )
  save_png("rmqr_label.png", qr)
}

// ---------------------------------------------------------------------------
// App 6: Micro QR business card (compact).
// ---------------------------------------------------------------------------

fn app_micro_business_card() -> Nil {
  io.println("== App 6: Micro QR small contact ==")
  let payload = "TEL:+81900000000"
  let assert Ok(qr) =
    qrkit.new(payload)
    |> qrkit.with_symbol(types.Micro)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build
  io.println(
    "Micro QR M"
    <> int.to_string(qrkit.version(qr))
    <> " size="
    <> int.to_string(qrkit.size(qr)),
  )
  save_png("micro_contact.png", qr)
}

// ---------------------------------------------------------------------------
// App 7: Japanese text (Kanji + ECI).
// ---------------------------------------------------------------------------

fn app_japanese() -> Nil {
  io.println("== App 7: Japanese kanji content ==")
  let payload = "こんにちは、世界！"
  let assert Ok(qr) =
    qrkit.new(payload)
    |> qrkit.with_eci(26)
    |> qrkit.build
  io.println(
    "version=" <> int.to_string(qrkit.version(qr)) <> " (eci=26 utf-8)",
  )
  save_png("japanese.png", qr)
}

// ---------------------------------------------------------------------------
// App 8: huge payload.
// ---------------------------------------------------------------------------

fn app_huge_payload() -> Nil {
  io.println("== App 8: max-capacity URL ==")
  let payload = string.repeat("0123456789", 70)
  let assert Ok(qr) =
    qrkit.new(payload)
    |> qrkit.with_ecc(types.Low)
    |> qrkit.build
  io.println(
    "huge payload "
    <> int.to_string(string.length(payload))
    <> " chars → version="
    <> int.to_string(qrkit.version(qr)),
  )
  save_png("huge.png", qr)
}

pub fn main() -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(out_dir)
  app_business_card()
  app_wifi_special_chars()
  app_share_url_three_ways()
  app_structured_append()
  app_rmqr_label()
  app_micro_business_card()
  app_japanese()
  app_huge_payload()
  io.println("done")
  Nil
}
