//// Pure Gleam PNG renderer.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import qrkit/internal/util

const png_signature = <<137, 80, 78, 71, 13, 10, 26, 10>>

/// CRC-32 of every byte value (polynomial 0xEDB88320, reflected), for the
/// chunk checksums.
const crc32_table: BitArray = <<
  0x00000000:32, 0x77073096:32, 0xEE0E612C:32, 0x990951BA:32, 0x076DC419:32,
  0x706AF48F:32, 0xE963A535:32, 0x9E6495A3:32, 0x0EDB8832:32, 0x79DCB8A4:32,
  0xE0D5E91E:32, 0x97D2D988:32, 0x09B64C2B:32, 0x7EB17CBD:32, 0xE7B82D07:32,
  0x90BF1D91:32, 0x1DB71064:32, 0x6AB020F2:32, 0xF3B97148:32, 0x84BE41DE:32,
  0x1ADAD47D:32, 0x6DDDE4EB:32, 0xF4D4B551:32, 0x83D385C7:32, 0x136C9856:32,
  0x646BA8C0:32, 0xFD62F97A:32, 0x8A65C9EC:32, 0x14015C4F:32, 0x63066CD9:32,
  0xFA0F3D63:32, 0x8D080DF5:32, 0x3B6E20C8:32, 0x4C69105E:32, 0xD56041E4:32,
  0xA2677172:32, 0x3C03E4D1:32, 0x4B04D447:32, 0xD20D85FD:32, 0xA50AB56B:32,
  0x35B5A8FA:32, 0x42B2986C:32, 0xDBBBC9D6:32, 0xACBCF940:32, 0x32D86CE3:32,
  0x45DF5C75:32, 0xDCD60DCF:32, 0xABD13D59:32, 0x26D930AC:32, 0x51DE003A:32,
  0xC8D75180:32, 0xBFD06116:32, 0x21B4F4B5:32, 0x56B3C423:32, 0xCFBA9599:32,
  0xB8BDA50F:32, 0x2802B89E:32, 0x5F058808:32, 0xC60CD9B2:32, 0xB10BE924:32,
  0x2F6F7C87:32, 0x58684C11:32, 0xC1611DAB:32, 0xB6662D3D:32, 0x76DC4190:32,
  0x01DB7106:32, 0x98D220BC:32, 0xEFD5102A:32, 0x71B18589:32, 0x06B6B51F:32,
  0x9FBFE4A5:32, 0xE8B8D433:32, 0x7807C9A2:32, 0x0F00F934:32, 0x9609A88E:32,
  0xE10E9818:32, 0x7F6A0DBB:32, 0x086D3D2D:32, 0x91646C97:32, 0xE6635C01:32,
  0x6B6B51F4:32, 0x1C6C6162:32, 0x856530D8:32, 0xF262004E:32, 0x6C0695ED:32,
  0x1B01A57B:32, 0x8208F4C1:32, 0xF50FC457:32, 0x65B0D9C6:32, 0x12B7E950:32,
  0x8BBEB8EA:32, 0xFCB9887C:32, 0x62DD1DDF:32, 0x15DA2D49:32, 0x8CD37CF3:32,
  0xFBD44C65:32, 0x4DB26158:32, 0x3AB551CE:32, 0xA3BC0074:32, 0xD4BB30E2:32,
  0x4ADFA541:32, 0x3DD895D7:32, 0xA4D1C46D:32, 0xD3D6F4FB:32, 0x4369E96A:32,
  0x346ED9FC:32, 0xAD678846:32, 0xDA60B8D0:32, 0x44042D73:32, 0x33031DE5:32,
  0xAA0A4C5F:32, 0xDD0D7CC9:32, 0x5005713C:32, 0x270241AA:32, 0xBE0B1010:32,
  0xC90C2086:32, 0x5768B525:32, 0x206F85B3:32, 0xB966D409:32, 0xCE61E49F:32,
  0x5EDEF90E:32, 0x29D9C998:32, 0xB0D09822:32, 0xC7D7A8B4:32, 0x59B33D17:32,
  0x2EB40D81:32, 0xB7BD5C3B:32, 0xC0BA6CAD:32, 0xEDB88320:32, 0x9ABFB3B6:32,
  0x03B6E20C:32, 0x74B1D29A:32, 0xEAD54739:32, 0x9DD277AF:32, 0x04DB2615:32,
  0x73DC1683:32, 0xE3630B12:32, 0x94643B84:32, 0x0D6D6A3E:32, 0x7A6A5AA8:32,
  0xE40ECF0B:32, 0x9309FF9D:32, 0x0A00AE27:32, 0x7D079EB1:32, 0xF00F9344:32,
  0x8708A3D2:32, 0x1E01F268:32, 0x6906C2FE:32, 0xF762575D:32, 0x806567CB:32,
  0x196C3671:32, 0x6E6B06E7:32, 0xFED41B76:32, 0x89D32BE0:32, 0x10DA7A5A:32,
  0x67DD4ACC:32, 0xF9B9DF6F:32, 0x8EBEEFF9:32, 0x17B7BE43:32, 0x60B08ED5:32,
  0xD6D6A3E8:32, 0xA1D1937E:32, 0x38D8C2C4:32, 0x4FDFF252:32, 0xD1BB67F1:32,
  0xA6BC5767:32, 0x3FB506DD:32, 0x48B2364B:32, 0xD80D2BDA:32, 0xAF0A1B4C:32,
  0x36034AF6:32, 0x41047A60:32, 0xDF60EFC3:32, 0xA867DF55:32, 0x316E8EEF:32,
  0x4669BE79:32, 0xCB61B38C:32, 0xBC66831A:32, 0x256FD2A0:32, 0x5268E236:32,
  0xCC0C7795:32, 0xBB0B4703:32, 0x220216B9:32, 0x5505262F:32, 0xC5BA3BBE:32,
  0xB2BD0B28:32, 0x2BB45A92:32, 0x5CB36A04:32, 0xC2D7FFA7:32, 0xB5D0CF31:32,
  0x2CD99E8B:32, 0x5BDEAE1D:32, 0x9B64C2B0:32, 0xEC63F226:32, 0x756AA39C:32,
  0x026D930A:32, 0x9C0906A9:32, 0xEB0E363F:32, 0x72076785:32, 0x05005713:32,
  0x95BF4A82:32, 0xE2B87A14:32, 0x7BB12BAE:32, 0x0CB61B38:32, 0x92D28E9B:32,
  0xE5D5BE0D:32, 0x7CDCEFB7:32, 0x0BDBDF21:32, 0x86D3D2D4:32, 0xF1D4E242:32,
  0x68DDB3F8:32, 0x1FDA836E:32, 0x81BE16CD:32, 0xF6B9265B:32, 0x6FB077E1:32,
  0x18B74777:32, 0x88085AE6:32, 0xFF0F6A70:32, 0x66063BCA:32, 0x11010B5C:32,
  0x8F659EFF:32, 0xF862AE69:32, 0x616BFFD3:32, 0x166CCF45:32, 0xA00AE278:32,
  0xD70DD2EE:32, 0x4E048354:32, 0x3903B3C2:32, 0xA7672661:32, 0xD06016F7:32,
  0x4969474D:32, 0x3E6E77DB:32, 0xAED16A4A:32, 0xD9D65ADC:32, 0x40DF0B66:32,
  0x37D83BF0:32, 0xA9BCAE53:32, 0xDEBB9EC5:32, 0x47B2CF7F:32, 0x30B5FFE9:32,
  0xBDBDF21C:32, 0xCABAC28A:32, 0x53B39330:32, 0x24B4A3A6:32, 0xBAD03605:32,
  0xCDD70693:32, 0x54DE5729:32, 0x23D967BF:32, 0xB3667A2E:32, 0xC4614AB8:32,
  0x5D681B02:32, 0x2A6F2B94:32, 0xB40BBE37:32, 0xC30C8EA1:32, 0x5A05DF1B:32,
  0x2D02EF8D:32,
>>

const adler32_modulus = 65_521

/// Render `rows` as a 1-bit palette PNG: `module_size` px per module, a
/// quiet zone of `margin` modules, and the dark and light palette entries
/// from `dark_color` and `light_color`. A `None` light colour keeps the
/// light entry white and marks it transparent with a `tRNS` chunk. Colours
/// are `#rgb`, `#rrggbb` or `#rrggbbaa` (alpha ignored); anything else
/// falls back to black for dark and white for light.
pub fn render(
  rows: List(List(Bool)),
  module_size module_size: Int,
  margin margin: Int,
  dark_color dark_color: String,
  light_color light_color: Option(String),
) -> BitArray {
  let rows = util.pad_rows(rows, margin)
  let width = case rows {
    [first, ..] -> list.length(first) * module_size
    [] -> 0
  }
  let height = list.length(rows) * module_size
  // Every module row becomes `module_size` identical scanlines.
  let image_data =
    list.flat_map(rows, fn(row) {
      list.repeat(scanline(row, module_size), module_size)
    })
    |> bit_array.concat
  let ihdr = <<width:32, height:32, 1, 3, 0, 0, 0>>
  let #(dr, dg, db) = parse_css_rgb(dark_color, default: #(0, 0, 0))
  let #(lr, lg, lb) =
    parse_css_rgb(option.unwrap(light_color, "#ffffff"), default: #(
      255,
      255,
      255,
    ))
  // tRNS chunk: palette alpha. Index 0 (dark) stays opaque at 255;
  // index 1 (light) is made transparent when there is no light colour.
  let trns_chunk = case light_color {
    Some(_) -> <<>>
    None -> chunk(<<"tRNS">>, <<255, 0>>)
  }
  bit_array.concat([
    png_signature,
    chunk(<<"IHDR">>, ihdr),
    chunk(<<"PLTE">>, <<dr, dg, db, lr, lg, lb>>),
    trns_chunk,
    chunk(<<"IDAT">>, zlib_store(image_data)),
    chunk(<<"IEND">>, <<>>),
  ])
}

fn parse_css_rgb(
  css: String,
  default default: #(Int, Int, Int),
) -> #(Int, Int, Int) {
  case string.starts_with(css, "#") {
    False -> default
    True -> {
      let hex = string.drop_start(css, 1)
      case string.length(hex) {
        3 -> parse_short_hex(hex, default)
        6 -> parse_long_hex(hex, default)
        8 -> parse_long_hex(string.slice(hex, 0, 6), default)
        _ -> default
      }
    }
  }
}

fn parse_short_hex(hex: String, default: #(Int, Int, Int)) -> #(Int, Int, Int) {
  let r = string.slice(hex, 0, 1)
  let g = string.slice(hex, 1, 1)
  let b = string.slice(hex, 2, 1)
  case parse_hex_byte(r <> r), parse_hex_byte(g <> g), parse_hex_byte(b <> b) {
    Ok(rv), Ok(gv), Ok(bv) -> #(rv, gv, bv)
    _, _, _ -> default
  }
}

fn parse_long_hex(hex: String, default: #(Int, Int, Int)) -> #(Int, Int, Int) {
  let r = string.slice(hex, 0, 2)
  let g = string.slice(hex, 2, 2)
  let b = string.slice(hex, 4, 2)
  case parse_hex_byte(r), parse_hex_byte(g), parse_hex_byte(b) {
    Ok(rv), Ok(gv), Ok(bv) -> #(rv, gv, bv)
    _, _, _ -> default
  }
}

fn parse_hex_byte(s: String) -> Result(Int, Nil) {
  int.base_parse(s, 16)
}

/// One scanline: filter type 0, then one bit per pixel (0 is the dark
/// palette entry, 1 the light one), each module `scale` pixels wide, and the
/// last byte filled with light pixels.
fn scanline(row: List(Bool), scale: Int) -> BitArray {
  let pixels =
    list.fold(row, <<0>>, fn(acc, dark) {
      case dark {
        True -> append_run(acc, 0, scale)
        False -> append_run(acc, 1, scale)
      }
    })
  append_run(pixels, 1, { 8 - bit_array.bit_size(pixels) % 8 } % 8)
}

/// Append `count` copies of `bit`, at most 8 at a time.
fn append_run(acc: BitArray, bit: Int, count: Int) -> BitArray {
  case count {
    0 -> acc
    _ -> {
      let take = int.min(count, 8)
      let value = bit * { int.bitwise_shift_left(1, take) - 1 }
      append_run(<<acc:bits, value:size(take)>>, bit, count - take)
    }
  }
}

/// A zlib stream (no compression) holding `data` in stored DEFLATE blocks
/// of at most 65535 bytes.
fn zlib_store(data: BitArray) -> BitArray {
  bit_array.concat([
    <<120, 1>>,
    stored_blocks(data, []),
    <<adler32(data, 1, 0):32>>,
  ])
}

fn stored_blocks(data: BitArray, acc: List(BitArray)) -> BitArray {
  let size = bit_array.byte_size(data)
  case size {
    0 -> bit_array.concat(list.reverse(acc))
    _ -> {
      let length = int.min(size, 65_535)
      let final = case length == size {
        True -> 1
        False -> 0
      }
      case data {
        <<block:bytes-size(length), rest:bytes>> ->
          stored_blocks(rest, [
            <<
              final,
              length:little-16,
              { 65_535 - length }:little-16,
              block:bits,
            >>,
            ..acc
          ])
        _ -> bit_array.concat(list.reverse(acc))
      }
    }
  }
}

fn chunk(type_bytes: BitArray, data: BitArray) -> BitArray {
  let crc =
    crc32(<<type_bytes:bits, data:bits>>, 0xFFFF_FFFF)
    |> int.bitwise_exclusive_or(0xFFFF_FFFF)
  <<bit_array.byte_size(data):32, type_bytes:bits, data:bits, crc:32>>
}

fn crc32(bytes: BitArray, crc: Int) -> Int {
  case bytes {
    <<byte, rest:bytes>> -> {
      let index = int.bitwise_and(int.bitwise_exclusive_or(crc, byte), 0xFF)
      let entry = case crc32_table {
        <<_:bytes-size(index * 4), value:32, _:bytes>> -> value
        _ -> 0
      }
      crc32(
        rest,
        int.bitwise_exclusive_or(int.bitwise_shift_right(crc, 8), entry),
      )
    }
    _ -> crc
  }
}

fn adler32(bytes: BitArray, s1: Int, s2: Int) -> Int {
  case bytes {
    <<byte, rest:bytes>> -> {
      let next_s1 = { s1 + byte } % adler32_modulus
      adler32(rest, next_s1, { s2 + next_s1 } % adler32_modulus)
    }
    _ -> s2 * 65_536 + s1
  }
}
