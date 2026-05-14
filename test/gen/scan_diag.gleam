//// Generates many QR codes for offline scanability diagnosis.

import gleam/int
import gleam/list
import gleam/string
import qrkit
import qrkit/content
import qrkit/internal/util
import qrkit/render/png
import qrkit/types
import simplifile

const out_dir: String = "/tmp/qr-decode/samples"

fn save(name: String, qr: qrkit.QrCode) -> Nil {
  let bytes = png.to_bit_array(qr, scale: 8, margin: 4)
  let assert Ok(Nil) = simplifile.write_bits(out_dir <> "/" <> name, bytes)
  Nil
}

fn save_idx(prefix: String, index: Int, qr: qrkit.QrCode) -> Nil {
  save(prefix <> "_" <> int.to_string(index) <> ".png", qr)
}

fn try_save(
  label: String,
  result: Result(qrkit.QrCode, qrkit.EncodeError),
) -> Nil {
  case result {
    Ok(qr) -> save(label, qr)
    Error(_) -> Nil
  }
}

pub fn main() -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(out_dir)

  // Short / mid / long URLs and texts
  let inputs = [
    #("01_hi.png", "HI"),
    #("02_hello.png", "HELLO WORLD"),
    #("03_numeric.png", "01234567"),
    #("04_short_url.png", "nao1215.dev"),
    #("05_https.png", "https://nao1215.dev"),
    #("06_sponsor.png", "https://github.com/sponsors/nao1215"),
    #("07_lowercase.png", "hello world"),
    #("08_mixed.png", "Hello, World! 12345"),
    #("09_with_emoji.png", "Hello 👋 World 🌏"),
    #("10_kanji.png", "こんにちは世界"),
  ]
  list.each(inputs, fn(pair) {
    let #(name, text) = pair
    try_save(name, qrkit.encode(text))
  })

  // All ECC levels for same payload
  let eccs = [
    #("11_url_L.png", types.Low),
    #("12_url_M.png", types.Medium),
    #("13_url_Q.png", types.Quartile),
    #("14_url_H.png", types.High),
  ]
  list.each(eccs, fn(pair) {
    let #(name, ecc) = pair
    try_save(
      name,
      qrkit.new("https://nao1215.dev")
        |> qrkit.with_ecc(ecc)
        |> qrkit.build,
    )
  })

  // Forced versions 1-40
  list.each(util.range(1, 40), fn(v) {
    let label = "v_" <> string.pad_start(int.to_string(v), to: 2, with: "0")
    try_save(
      label <> ".png",
      qrkit.new("HELLO")
        |> qrkit.with_min_version(v)
        |> qrkit.build,
    )
  })

  // WiFi
  let wifi =
    content.wifi(
      ssid: "MyAP",
      password: "secret123",
      security: content.Wpa2,
      hidden: False,
    )
  try_save("wifi.png", qrkit.encode(wifi))

  // vCard
  let vcard =
    content.vcard()
    |> content.with_name("Naohiro Chikamatsu")
    |> content.with_email("nao@example.com")
    |> content.with_phone("+81-90-0000-0000")
    |> content.with_url("https://github.com/nao1215")
    |> content.vcard_to_string
  try_save("vcard.png", qrkit.encode(vcard))

  // Structured Append shards
  let assert Ok(shards) =
    qrkit.encode_split(string.repeat("0123456789ABCDEFGH", 5), 3)
  list.index_map(shards, fn(shard, idx) { save_idx("sa_shard", idx, shard) })

  // Micro QR variants
  let micros = [
    #("micro_m1.png", "12345", types.Low),
    #("micro_m2_l.png", "01234567", types.Low),
    #("micro_m2_m.png", "ABCDEF", types.Medium),
    #("micro_m3_l.png", "01234567890123", types.Low),
    #("micro_m3_m.png", "hello", types.Medium),
    #("micro_m4_l.png", "abcdefghijklmno", types.Low),
    #("micro_m4_q.png", "12345", types.Quartile),
  ]
  list.each(micros, fn(triple) {
    let #(name, text, ecc) = triple
    try_save(
      name,
      qrkit.new(text)
        |> qrkit.with_symbol(types.Micro)
        |> qrkit.with_ecc(ecc)
        |> qrkit.build,
    )
  })

  Nil
}
