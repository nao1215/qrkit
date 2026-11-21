//// Rectangular Micro QR (rMQR) encoder, ISO/IEC 23941:2022.
////
//// Supports the 32 rMQR sizes from R7×43 to R17×139 with M or H error
//// correction. Reuses the standard Reed-Solomon engine and matrix primitives;
//// functional patterns and format info follow ISO/IEC 23941.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import qrkit/error.{
  type EncodeError, DataExceedsCapacity, IncompatibleOptions, InvalidVersion,
}
import qrkit/internal/bitstream
import qrkit/internal/format_info
import qrkit/internal/mask
import qrkit/internal/matrix
import qrkit/internal/mode
import qrkit/internal/reed_solomon
import qrkit/internal/segment
import qrkit/internal/util
import qrkit/types.{
  type ErrorCorrection, type Mode, type ModePreference, type RectangularPriority,
  Alphanumeric, Byte, High, Kanji, Low, Medium, NarrowestWidth, Numeric,
  Quartile, ShortestHeight, SmallestArea,
}

const total_versions: Int = 32

const heights: List(Int) = [
  7, 7, 7, 7, 7, 9, 9, 9, 9, 9, 11, 11, 11, 11, 11, 11, 13, 13, 13, 13, 13, 13,
  15, 15, 15, 15, 15, 17, 17, 17, 17, 17,
]

const widths: List(Int) = [
  43, 59, 77, 99, 139, 43, 59, 77, 99, 139, 27, 43, 59, 77, 99, 139, 27, 43, 59,
  77, 99, 139, 43, 59, 77, 99, 139, 43, 59, 77, 99, 139,
]

const data_codewords_m: List(Int) = [
  6, 12, 20, 28, 44, 12, 21, 31, 42, 63, 7, 19, 31, 43, 57, 84, 12, 27, 38, 53,
  73, 106, 33, 48, 67, 88, 127, 39, 56, 78, 100, 152,
]

const data_codewords_h: List(Int) = [
  3, 7, 10, 14, 24, 7, 11, 17, 22, 33, 5, 11, 15, 23, 29, 42, 7, 13, 20, 29, 35,
  54, 15, 26, 31, 48, 69, 21, 28, 38, 56, 76,
]

const total_codewords_table: List(Int) = [
  13, 21, 32, 44, 68, 21, 33, 49, 66, 99, 15, 31, 47, 67, 89, 132, 21, 41, 60,
  85, 113, 166, 51, 74, 103, 136, 199, 61, 88, 122, 160, 232,
]

// Error-correction block counts per version, ISO/IEC 23941:2022 Table 8.
// Every block of a symbol has the same number of error-correction codewords;
// when the data does not divide evenly the later blocks take one extra data
// codeword (see `reed_solomon.encode_interleaved`).
const ec_blocks_m: List(Int) = [
  1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 2, 3, 1, 1, 2, 2,
  3, 1, 2, 2, 3, 4,
]

const ec_blocks_h: List(Int) = [
  1, 1, 1, 1, 2, 1, 1, 2, 2, 3, 1, 1, 2, 2, 2, 3, 1, 1, 2, 2, 3, 4, 2, 2, 3, 4,
  5, 2, 2, 3, 4, 6,
]

const numeric_cci: List(Int) = [
  4, 5, 6, 7, 7, 5, 6, 7, 7, 8, 4, 6, 7, 7, 8, 8, 5, 6, 7, 7, 8, 8, 7, 7, 8, 8,
  9, 7, 8, 8, 8, 9,
]

const alphanum_cci: List(Int) = [
  3, 5, 5, 6, 6, 5, 5, 6, 6, 7, 4, 5, 6, 6, 7, 7, 5, 6, 6, 7, 7, 8, 6, 7, 7, 7,
  8, 6, 7, 7, 8, 8,
]

const byte_cci: List(Int) = [
  3, 4, 5, 5, 6, 4, 5, 5, 6, 6, 3, 5, 5, 6, 6, 7, 4, 5, 6, 6, 7, 7, 6, 6, 7, 7,
  7, 6, 6, 7, 7, 8,
]

const kanji_cci: List(Int) = [
  2, 3, 4, 5, 5, 3, 4, 5, 5, 6, 2, 4, 5, 5, 6, 6, 3, 5, 5, 6, 6, 7, 5, 5, 6, 6,
  7, 5, 6, 6, 6, 7,
]

const format_info_left: List(Int) = [
  0x1FAB2, 0x1E597, 0x1DBDD, 0x1C4F8, 0x1B86C, 0x1A749, 0x19903, 0x18626,
  0x17F0E, 0x1602B, 0x15E61, 0x14144, 0x13DD0, 0x122F5, 0x11CBF, 0x1039A,
  0x0F1CA, 0x0EEEF, 0x0D0A5, 0x0CF80, 0x0B314, 0x0AC31, 0x0927B, 0x08D5E,
  0x07476, 0x06B53, 0x05519, 0x04A3C, 0x036A8, 0x0298D, 0x017C7, 0x008E2,
  0x3F367, 0x3EC42, 0x3D208, 0x3CD2D, 0x3B1B9, 0x3AE9C, 0x390D6, 0x38FF3,
  0x376DB, 0x369FE, 0x357B4, 0x34891, 0x33405, 0x32B20, 0x3156A, 0x30A4F,
  0x2F81F, 0x2E73A, 0x2D970, 0x2C655, 0x2BAC1, 0x2A5E4, 0x29BAE, 0x2848B,
  0x27DA3, 0x26286, 0x25CCC, 0x243E9, 0x23F7D, 0x22058, 0x21E12, 0x20137,
]

const format_info_right: List(Int) = [
  0x20A7B, 0x2155E, 0x22B14, 0x23431, 0x248A5, 0x25780, 0x269CA, 0x276EF,
  0x28FC7, 0x290E2, 0x2AEA8, 0x2B18D, 0x2CD19, 0x2D23C, 0x2EC76, 0x2F353,
  0x30103, 0x31E26, 0x3206C, 0x33F49, 0x343DD, 0x35CF8, 0x362B2, 0x37D97,
  0x384BF, 0x39B9A, 0x3A5D0, 0x3BAF5, 0x3C661, 0x3D944, 0x3E70E, 0x3F82B,
  0x003AE, 0x01C8B, 0x022C1, 0x03DE4, 0x04170, 0x05E55, 0x0601F, 0x07F3A,
  0x08612, 0x09937, 0x0A77D, 0x0B858, 0x0C4CC, 0x0DBE9, 0x0E5A3, 0x0FA86,
  0x108D6, 0x117F3, 0x129B9, 0x1369C, 0x14A08, 0x1552D, 0x16B67, 0x17442,
  0x18D6A, 0x1924F, 0x1AC05, 0x1B320, 0x1CFB4, 0x1D091, 0x1EEDB, 0x1F1FE,
]

// Indices into rmqr_table_d1 — alignment column centres per width (5 rows × 4)
const alignment_columns: List(Int) = [
  21, 0, 0, 0, 19, 39, 0, 0, 25, 51, 0, 0, 23, 49, 75, 0, 27, 55, 83, 111,
]

/// Encode `text` into an rMQR symbol.
///
/// `exact_version` is `Some(N)` (1-based, 1 = R7×43, 32 = R17×139) when the
/// caller pinned the version with `qrkit.with_exact_version(N)`: the symbol
/// is version N, and a payload that does not fit returns an `Error`. When it
/// is `None`, the encoder picks the first version in the priority order that
/// fits.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  exact_version: Option(Int),
  preference: ModePreference,
  priority: RectangularPriority,
) -> Result(matrix.Encoded, EncodeError) {
  use _ <- result.try(validate_ecc(ecc))
  use #(chosen, segments) <- result.try(resolve_version(
    text,
    ecc,
    exact_version,
    preference,
    priority,
  ))
  use codewords <- result.try(create_codewords(segments, ecc, chosen))
  let h_size = lookup_int(widths, chosen)
  let v_size = lookup_int(heights, chosen)
  let total = lookup_int(total_codewords_table, chosen)
  let final_matrix = build_matrix(chosen, ecc, h_size, v_size, total, codewords)
  // rMQR has one fixed mask. It is reported as 4, the Standard QR mask with
  // the same `(row / 2 + col / 3) % 2 == 0` pattern.
  Ok(matrix.encoded(final_matrix, version: chosen + 1, mask: 4))
}

fn resolve_version(
  text: String,
  ecc: ErrorCorrection,
  exact_version: Option(Int),
  preference: ModePreference,
  priority: RectangularPriority,
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  case exact_version {
    None -> find_version(text, ecc, preference, search_order(priority))
    Some(value) ->
      case value < 1 || value > total_versions {
        True -> Error(InvalidVersion(value))
        False -> check_version(text, ecc, preference, value - 1)
      }
  }
}

fn check_version(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
  candidate: Int,
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  let segments = segments_at(text, preference, candidate)
  let data_bits = segments_bits(segments, candidate)
  let capacity = data_capacity_bits(candidate, ecc)
  case data_bits <= capacity {
    True -> Ok(#(candidate, segments))
    False -> Error(DataExceedsCapacity(data_bits, capacity))
  }
}

/// The shortest segmentation of `text` for the version at `index`: one Byte
/// segment for `ForceByte`, otherwise Numeric / Alphanumeric / Byte / Kanji
/// runs, keeping a single segment when that is not longer.
fn segments_at(
  text: String,
  preference: ModePreference,
  index: Int,
) -> List(segment.Segment) {
  case preference {
    types.ForceByte -> [segment.single(text, Byte)]
    types.Auto -> {
      let one = [segment.single(text, mode.uniform(util.characters(text)))]
      case segment.split(text, fn(m) { Ok(3 + lookup_cci(m, index)) }) {
        Ok(split) ->
          case segments_bits(one, index) <= segments_bits(split, index) {
            True -> one
            False -> split
          }
        Error(Nil) -> one
      }
    }
  }
}

fn segments_bits(segments: List(segment.Segment), index: Int) -> Int {
  list.fold(segments, 0, fn(acc, seg) {
    acc + 3 + lookup_cci(seg.mode, index) + seg.bits
  })
}

fn validate_ecc(ecc: ErrorCorrection) -> Result(Nil, EncodeError) {
  case ecc {
    Medium | High -> Ok(Nil)
    Low | Quartile ->
      Error(IncompatibleOptions(
        "rMQR only supports M or H error correction levels",
      ))
  }
}

fn find_version(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
  candidates: List(Int),
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  case candidates {
    [] -> Error(no_version_fits_error(text, ecc, preference))
    [candidate, ..rest] ->
      case check_version(text, ecc, preference, candidate) {
        Ok(found) -> Ok(found)
        Error(_) -> find_version(text, ecc, preference, rest)
      }
  }
}

/// Version indices in the order `find_version` tries them. Capacity grows
/// with both dimensions, so the first size that fits in this order is the
/// smallest by the chosen measure.
fn search_order(priority: RectangularPriority) -> List(Int) {
  let key = fn(index) {
    let width = lookup_int(widths, index)
    let height = lookup_int(heights, index)
    case priority {
      SmallestArea -> #(width * height, height)
      ShortestHeight -> #(height, width)
      NarrowestWidth -> #(width, height)
    }
  }
  int.range(from: 0, to: total_versions, with: [], run: list.prepend)
  |> list.sort(fn(a, b) {
    let #(a1, a2) = key(a)
    let #(b1, b2) = key(b)
    case int.compare(a1, b1) {
      order.Eq -> int.compare(a2, b2)
      other -> other
    }
  })
}

/// Build a `DataExceedsCapacity` error for the bailout case where no rMQR
/// version (R7×43..R17×139) accepts the payload at `ecc`. We report the
/// R17×139 (largest) ceiling so the caller can see how far over the rMQR
/// limit the input is.
fn no_version_fits_error(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
) -> EncodeError {
  let largest = total_versions - 1
  let bits_needed =
    segments_bits(segments_at(text, preference, largest), largest)
  let bits_available = data_capacity_bits(largest, ecc)
  DataExceedsCapacity(bits_needed, bits_available)
}

fn data_capacity_bits(index: Int, ecc: ErrorCorrection) -> Int {
  data_codewords(index, ecc) * 8
}

pub fn data_codewords(index: Int, ecc: ErrorCorrection) -> Int {
  case ecc {
    High -> lookup_int(data_codewords_h, index)
    Low | Medium | Quartile -> lookup_int(data_codewords_m, index)
  }
}

pub fn ec_block_count(index: Int, ecc: ErrorCorrection) -> Int {
  case ecc {
    High -> lookup_int(ec_blocks_h, index)
    Low | Medium | Quartile -> lookup_int(ec_blocks_m, index)
  }
}

fn lookup_cci(selected_mode: Mode, index: Int) -> Int {
  case selected_mode {
    Numeric -> lookup_int(numeric_cci, index)
    Alphanumeric -> lookup_int(alphanum_cci, index)
    Byte -> lookup_int(byte_cci, index)
    Kanji -> lookup_int(kanji_cci, index)
  }
}

fn lookup_int(table: List(Int), index: Int) -> Int {
  util.at_or(table, index, default: 0)
}

fn mode_indicator(selected_mode: Mode) -> Int {
  case selected_mode {
    Numeric -> 0b001
    Alphanumeric -> 0b010
    Byte -> 0b011
    Kanji -> 0b100
  }
}

fn create_codewords(
  segments: List(segment.Segment),
  ecc: ErrorCorrection,
  index: Int,
) -> Result(List(Int), EncodeError) {
  let capacity = data_capacity_bits(index, ecc)
  use stream <- result.try(
    segment.append_segments(bitstream.new(), segments, fn(segment_mode) {
      Ok(segment.Header(
        mode_indicator(segment_mode),
        3,
        lookup_cci(segment_mode, index),
      ))
    }),
  )
  let stream = append_terminator(stream, capacity)
  case bitstream.length_bits(stream) > capacity {
    True -> Error(DataExceedsCapacity(bitstream.length_bits(stream), capacity))
    False -> {
      let aligned = bitstream.pad_to_byte_boundary(stream)
      let padded = pad_to_data(aligned, data_codewords(index, ecc))
      Ok(reed_solomon.encode_interleaved(
        bitstream.to_byte_list(padded),
        total_codewords: lookup_int(total_codewords_table, index),
        blocks: ec_block_count(index, ecc),
      ))
    }
  }
}

fn append_terminator(
  stream: bitstream.BitStream,
  capacity: Int,
) -> bitstream.BitStream {
  let remaining = capacity - bitstream.length_bits(stream)
  let bits = case remaining < 3 {
    True -> remaining
    False -> 3
  }
  case bits <= 0 {
    True -> stream
    False -> bitstream.append_bits(stream, 0, size: bits)
  }
}

fn pad_to_data(
  stream: bitstream.BitStream,
  data_bytes: Int,
) -> bitstream.BitStream {
  do_pad_to_data(stream, data_bytes, 0)
}

fn do_pad_to_data(
  stream: bitstream.BitStream,
  data_bytes: Int,
  index: Int,
) -> bitstream.BitStream {
  let current = list.length(bitstream.to_byte_list(stream))
  case current >= data_bytes {
    True -> stream
    False -> {
      let byte = case index % 2 == 0 {
        True -> 0xEC
        False -> 0x11
      }
      do_pad_to_data(bitstream.append_byte(stream, byte), data_bytes, index + 1)
    }
  }
}

fn build_matrix(
  index: Int,
  ecc: ErrorCorrection,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
  codewords: List(Int),
) -> matrix.Matrix {
  let placed =
    place_data(
      function_patterns(h_size, v_size),
      h_size,
      v_size,
      total_codewords,
      codewords,
    )
  let masked = mask.apply_with(placed, mask_at)
  place_format_info(masked, index, ecc, h_size, v_size)
}

fn function_patterns(h_size: Int, v_size: Int) -> matrix.Matrix {
  matrix.new(h_size, v_size)
  |> draw_timing_borders(h_size, v_size)
  |> draw_top_left_finder
  |> draw_bottom_right_subfinder(h_size, v_size)
  |> draw_top_right_corner(h_size)
  |> draw_bottom_left_corner(v_size)
  |> draw_separator(h_size, v_size)
  |> draw_alignment_patterns(h_size, v_size)
  |> reserve_format_info(h_size, v_size)
}

/// The `(row, col)` of every data module of the version at `index`, in
/// placement order (exactly `total_codewords(index) * 8` of them).
pub fn data_module_positions(index: Int) -> List(#(Int, Int)) {
  let h_size = lookup_int(widths, index)
  let v_size = lookup_int(heights, index)
  data_positions(
    function_patterns(h_size, v_size),
    h_size,
    v_size,
    lookup_int(total_codewords_table, index),
  )
}

/// The 0-based version index of a `width` x `height` rMQR symbol.
pub fn index_for_size(width: Int, height: Int) -> Result(Int, Nil) {
  list.zip(widths, heights)
  |> list.index_fold(Error(Nil), fn(found, size, index) {
    case found, size == #(width, height) {
      Ok(_), _ -> found
      Error(_), True -> Ok(index)
      Error(_), False -> found
    }
  })
}

/// The two 18-bit copies of the format information of a symbol given as
/// `module(row, col)`, in the bit order `place_format_info` writes.
pub fn read_format(
  module: fn(Int, Int) -> Bool,
  h_size: Int,
  v_size: Int,
) -> #(Int, Int) {
  let read = fn(positions) {
    list.index_fold(positions, 0, fn(acc, position, bit) {
      let #(row, col) = position
      case module(row, col) {
        True -> acc + int.bitwise_shift_left(1, bit)
        False -> acc
      }
    })
  }
  let #(left, right) = format_info_modules(h_size, v_size)
  #(read(left), read(right))
}

/// The `(row, col)` of each bit of the two 18-bit format information copies,
/// bit 0 first: beside the finder pattern, and beside the sub-finder.
fn format_info_modules(
  h_size: Int,
  v_size: Int,
) -> #(List(#(Int, Int)), List(#(Int, Int))) {
  let copy = fn(top, left, extra) {
    int.range(from: 14, to: -1, with: extra, run: fn(acc, bit) {
      [#(top + bit % 5, left + bit / 5), ..acc]
    })
  }
  #(
    copy(1, 8, [#(1, 11), #(2, 11), #(3, 11)]),
    copy(v_size - 6, h_size - 8, [
      #(v_size - 6, h_size - 5),
      #(v_size - 6, h_size - 4),
      #(v_size - 6, h_size - 3),
    ]),
  )
}

/// The version index and error correction level whose format information is
/// within 3 bits of either copy.
pub fn decode_format(
  left: Int,
  right: Int,
) -> Result(#(Int, ErrorCorrection), Nil) {
  let candidates = fn(table) {
    list.index_map(table, fn(value, i) {
      let ecc = case i >= total_versions {
        True -> High
        False -> Medium
      }
      #(#(i % total_versions, ecc), value)
    })
  }
  case format_info.nearest(candidates(format_info_left), [left], 3) {
    Ok(found) -> Ok(found)
    Error(Nil) -> format_info.nearest(candidates(format_info_right), [right], 3)
  }
}

/// The fixed rMQR data mask at `(row, col)`.
pub fn mask_at(row: Int, col: Int) -> Bool {
  { row / 2 + col / 3 } % 2 == 0
}

pub fn total_codewords(index: Int) -> Int {
  lookup_int(total_codewords_table, index)
}

/// Width of the character count indicator of `selected_mode` at `index`.
pub fn count_bits(selected_mode: Mode, index: Int) -> Int {
  lookup_cci(selected_mode, index)
}

fn draw_timing_borders(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let top_bottom =
    int.range(from: 0, to: h_size, with: target, run: fn(acc, col) {
      let dark = col % 2 == 0
      acc
      |> matrix.set(0, col, dark, reserved: True)
      |> matrix.set(v_size - 1, col, dark, reserved: True)
    })
  int.range(from: 0, to: v_size, with: top_bottom, run: fn(acc, row) {
    let dark = row % 2 == 0
    acc
    |> matrix.set(row, 0, dark, reserved: True)
    |> matrix.set(row, h_size - 1, dark, reserved: True)
  })
}

fn draw_top_left_finder(target: matrix.Matrix) -> matrix.Matrix {
  int.range(from: 0, to: 7, with: target, run: fn(acc, row) {
    int.range(from: 0, to: 7, with: acc, run: fn(acc2, col) {
      let dark =
        row == 0
        || row == 6
        || col == 0
        || col == 6
        || { row >= 2 && row <= 4 && col >= 2 && col <= 4 }
      matrix.set(acc2, row, col, dark, reserved: True)
    })
  })
}

fn draw_bottom_right_subfinder(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  int.range(from: 0, to: 5, with: target, run: fn(acc, row) {
    int.range(from: 0, to: 5, with: acc, run: fn(acc2, col) {
      let dark =
        row == 0 || row == 4 || col == 0 || col == 4 || { row == 2 && col == 2 }
      matrix.set(acc2, v_size - 5 + row, h_size - 5 + col, dark, reserved: True)
    })
  })
}

fn draw_top_right_corner(target: matrix.Matrix, h_size: Int) -> matrix.Matrix {
  target
  |> matrix.set(0, h_size - 2, True, reserved: True)
  |> matrix.set(1, h_size - 2, False, reserved: True)
  |> matrix.set(1, h_size - 1, True, reserved: True)
}

fn draw_bottom_left_corner(
  target: matrix.Matrix,
  v_size: Int,
) -> matrix.Matrix {
  target
  |> matrix.set(v_size - 2, 0, True, reserved: True)
  |> matrix.set(v_size - 2, 1, False, reserved: True)
  |> matrix.set(v_size - 1, 1, True, reserved: True)
}

fn draw_separator(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let with_right =
    int.range(from: 0, to: 7, with: target, run: fn(acc, row) {
      matrix.set(acc, row, 7, False, reserved: True)
    })
  case v_size > 7 {
    False -> with_right
    True ->
      int.range(from: 0, to: 8, with: with_right, run: fn(acc, col) {
        case col >= h_size {
          True -> acc
          False -> matrix.set(acc, 7, col, False, reserved: True)
        }
      })
  }
}

fn draw_alignment_patterns(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  case h_size > 27 {
    False -> target
    True ->
      case alignment_row_for_width(h_size) {
        Error(_) -> target
        Ok(h_version) -> do_draw_alignment_columns(target, v_size, h_version, 0)
      }
  }
}

fn alignment_row_for_width(h_size: Int) -> Result(Int, Nil) {
  case h_size {
    43 -> Ok(0)
    59 -> Ok(1)
    77 -> Ok(2)
    99 -> Ok(3)
    139 -> Ok(4)
    _ -> Error(Nil)
  }
}

fn do_draw_alignment_columns(
  target: matrix.Matrix,
  v_size: Int,
  h_version: Int,
  index: Int,
) -> matrix.Matrix {
  case index >= 4 {
    True -> target
    False -> {
      let column = lookup_int(alignment_columns, h_version * 4 + index)
      case column {
        0 -> target
        _ ->
          do_draw_alignment_columns(
            draw_alignment_column(target, column, v_size),
            v_size,
            h_version,
            index + 1,
          )
      }
    }
  }
}

fn draw_alignment_column(
  target: matrix.Matrix,
  column: Int,
  v_size: Int,
) -> matrix.Matrix {
  let with_line =
    int.range(from: 0, to: v_size, with: target, run: fn(acc, row) {
      let dark = row % 2 == 0
      matrix.set(acc, row, column, dark, reserved: True)
    })
  with_line
  |> matrix.set(1, column - 1, True, reserved: True)
  |> matrix.set(2, column - 1, True, reserved: True)
  |> matrix.set(1, column + 1, True, reserved: True)
  |> matrix.set(2, column + 1, True, reserved: True)
  |> matrix.set(v_size - 3, column - 1, True, reserved: True)
  |> matrix.set(v_size - 2, column - 1, True, reserved: True)
  |> matrix.set(v_size - 3, column + 1, True, reserved: True)
  |> matrix.set(v_size - 2, column + 1, True, reserved: True)
}

fn reserve_format_info(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let #(left, right) = format_info_modules(h_size, v_size)
  list.append(left, right)
  |> list.fold(target, fn(acc, position) {
    matrix.set(acc, position.0, position.1, False, reserved: True)
  })
}

fn place_data(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
  codewords: List(Int),
) -> matrix.Matrix {
  matrix.write_bits(
    target,
    data_positions(target, h_size, v_size, total_codewords),
    bitstream.bytes_to_bits(codewords),
  )
}

fn data_positions(
  target: matrix.Matrix,
  h_size: Int,
  v_size: Int,
  total_codewords: Int,
) -> List(#(Int, Int)) {
  let bits_needed = total_codewords * 8
  let initial_x = h_size - 3
  do_data_positions(target, initial_x, v_size - 1, 1, 0, bits_needed, [])
}

fn do_data_positions(
  target: matrix.Matrix,
  x: Int,
  y: Int,
  direction: Int,
  collected: Int,
  needed: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case collected >= needed || x < 0 {
    True -> list.reverse(acc)
    False -> {
      let #(acc1, count1) = try_place(target, y, x + 1, acc, collected)
      let #(acc2, count2) = try_place(target, y, x, acc1, count1)
      let #(next_x, next_y, next_dir) =
        advance(matrix.height(target), x, y, direction)
      do_data_positions(target, next_x, next_y, next_dir, count2, needed, acc2)
    }
  }
}

fn try_place(
  target: matrix.Matrix,
  row: Int,
  col: Int,
  acc: List(#(Int, Int)),
  collected: Int,
) -> #(List(#(Int, Int)), Int) {
  case col < 0 || col >= matrix.width(target) {
    True -> #(acc, collected)
    False ->
      case matrix.is_reserved(target, row, col) {
        True -> #(acc, collected)
        False -> #([#(row, col), ..acc], collected + 1)
      }
  }
}

fn advance(v_size: Int, x: Int, y: Int, direction: Int) -> #(Int, Int, Int) {
  case direction {
    1 ->
      case y == 0 {
        True -> #(x - 2, 0, 0)
        False -> #(x, y - 1, 1)
      }
    _ ->
      case y == v_size - 1 {
        True -> #(x - 2, v_size - 1, 1)
        False -> #(x, y + 1, 0)
      }
  }
}

fn place_format_info(
  target: matrix.Matrix,
  index: Int,
  ecc: ErrorCorrection,
  h_size: Int,
  v_size: Int,
) -> matrix.Matrix {
  let table_index = case ecc {
    High -> index + 32
    Low | Medium | Quartile -> index
  }
  let #(left, right) = format_info_modules(h_size, v_size)
  target
  |> place_format_copy(left, lookup_int(format_info_left, table_index))
  |> place_format_copy(right, lookup_int(format_info_right, table_index))
}

fn place_format_copy(
  target: matrix.Matrix,
  positions: List(#(Int, Int)),
  bits: Int,
) -> matrix.Matrix {
  list.index_fold(positions, target, fn(acc, position, bit) {
    let #(row, col) = position
    matrix.set(acc, row, col, util.bit_at(bits, bit), reserved: True)
  })
}
