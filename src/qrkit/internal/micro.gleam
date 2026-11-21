//// Micro QR Code encoder (ISO/IEC 18004 §6 + Annex K).
////
//// Supports M1 (11×11) through M4 (17×17). Reuses the standard QR Reed-Solomon
//// engine, bitstream, and matrix primitives; mask selection, format info and
//// data placement follow the Micro QR rules.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import qrkit/internal/bitstream
import qrkit/internal/error.{
  type EncodeError, DataExceedsCapacity, ErrorCorrectionNotSupported,
  InvalidVersion, UnsupportedCharacter,
}
import qrkit/internal/format_info
import qrkit/internal/mask
import qrkit/internal/matrix
import qrkit/internal/mode
import qrkit/internal/reed_solomon
import qrkit/internal/segment
import qrkit/internal/types.{
  type ErrorCorrection, type Mode, type ModePreference, Alphanumeric, Byte, High,
  Kanji, Low, Medium, Micro, Numeric, Quartile,
}
import qrkit/internal/util

const finder_size: Int = 7

const min_version: Int = 1

const max_version: Int = 4

const format_xor_mask: Int = 0x4445

const format_info_table: List(Int) = [
  0x4445, 0x4172, 0x4E2B, 0x4B1C, 0x55AE, 0x5099, 0x5FC0, 0x5AF7, 0x6793, 0x62A4,
  0x6DFD, 0x68CA, 0x7678, 0x734F, 0x7C16, 0x7921, 0x06DE, 0x03E9, 0x0CB0, 0x0987,
  0x1735, 0x1202, 0x1D5B, 0x186C, 0x2508, 0x203F, 0x2F66, 0x2A51, 0x34E3, 0x31D4,
  0x3E8D, 0x3BBA,
]

/// Every Micro QR version and error correction level pair in symbol number
/// order (ISO/IEC 18004 Table 13), with its data capacity in bits and its
/// number of error correction codewords.
const symbols: List(#(Int, ErrorCorrection, Int, Int)) = [
  #(1, Low, 20, 2),
  #(2, Low, 40, 5),
  #(2, Medium, 32, 6),
  #(3, Low, 84, 6),
  #(3, Medium, 68, 8),
  #(4, Low, 128, 8),
  #(4, Medium, 112, 10),
  #(4, Quartile, 80, 14),
]

/// Encode `text` into a Micro QR code.
///
/// `exact_version` is `Some(N)` when the caller pinned the version with
/// `EncodeOptions(version: Some(N))`: the symbol is MN, and a mode, error
/// correction level or payload that MN cannot carry returns an `Error`. When
/// it is `None`, the encoder picks the smallest version that fits the
/// payload.
pub fn encode(
  text: String,
  ecc: ErrorCorrection,
  exact_version: Option(Int),
  preference: ModePreference,
) -> Result(matrix.Encoded, EncodeError) {
  use _ <- result.try(validate_exact_version(exact_version))
  use _ <- result.try(validate_ecc(ecc))
  use #(chosen_version, segments) <- result.try(resolve_version(
    text,
    ecc,
    exact_version,
    preference,
  ))
  use codewords <- result.try(create_codewords(segments, ecc, chosen_version))
  case build_matrix(chosen_version, ecc, codewords) {
    Ok(#(best_mask, final_matrix)) ->
      Ok(matrix.encoded(final_matrix, version: chosen_version, mask: best_mask))
    Error(error) -> Error(error)
  }
}

fn validate_exact_version(
  exact_version: Option(Int),
) -> Result(Nil, EncodeError) {
  case exact_version {
    None -> Ok(Nil)
    Some(value) -> validate_version(value)
  }
}

/// Resolve the version the encoder should use, with the segments measured
/// for it (the mode indicator and character counts widen with the version).
///
/// - When `exact_version` is `None`, walk versions from `min_version` upward
///   and pick the first that fits the payload.
/// - When `exact_version` is `Some(N)`, use exactly N: if N cannot encode the
///   characters, support the ECC level, or hold the payload, return the
///   `Error` that explains why.
fn resolve_version(
  text: String,
  ecc: ErrorCorrection,
  exact_version: Option(Int),
  preference: ModePreference,
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  case exact_version {
    None -> do_find_version(text, ecc, preference, min_version)
    Some(n) -> check_version(text, ecc, preference, n)
  }
}

/// Confirm a single, caller-requested Micro QR version. Returns the version
/// and its segments when modes + ECC + capacity all check out; otherwise
/// surfaces the precise `EncodeError` that explains the mismatch.
fn check_version(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
  candidate: Int,
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  use segments <- result.try(segments_at(text, preference, candidate))
  use capacity <- result.try(data_capacity_bits(candidate, ecc))
  let required = segments_bits(segments, candidate)
  case required <= capacity {
    True -> Ok(#(candidate, segments))
    False -> Error(DataExceedsCapacity(required, capacity))
  }
}

/// The shortest segmentation of `text` at `version`. `ForceByte` keeps one
/// Byte segment. `Auto` splits into Numeric / Alphanumeric / Byte / Kanji
/// runs where the version allows those modes (M1 is Numeric only, M2 adds
/// Alphanumeric), and keeps a single segment when that is not longer.
fn segments_at(
  text: String,
  preference: ModePreference,
  version: Int,
) -> Result(List(segment.Segment), EncodeError) {
  let single_mode = case preference {
    types.ForceByte -> Byte
    types.Auto -> mode.uniform(util.characters(text))
  }
  let single = case mode_supported(single_mode, version) {
    True -> Ok([segment.single(text, single_mode)])
    False -> Error(unsupported_at(text, preference, version))
  }
  case preference {
    types.ForceByte -> single
    types.Auto ->
      case segment.split(text, header_bits(version)), single {
        Error(Nil), _ -> single
        Ok(split), Ok(one) ->
          case segments_bits(one, version) <= segments_bits(split, version) {
            True -> Ok(one)
            False -> Ok(split)
          }
        Ok(split), Error(_) -> Ok(split)
      }
  }
}

fn header_bits(version: Int) -> fn(Mode) -> Result(Int, Nil) {
  fn(segment_mode) {
    case char_count_bits_for_mode(segment_mode, version) {
      Ok(count_bits) -> Ok(mode_indicator_bits(version) + count_bits)
      Error(_) -> Error(Nil)
    }
  }
}

fn segments_bits(segments: List(segment.Segment), version: Int) -> Int {
  list.fold(segments, 0, fn(acc, seg) {
    let count_bits = case char_count_bits_for_mode(seg.mode, version) {
      Ok(value) -> value
      Error(_) -> 0
    }
    acc + mode_indicator_bits(version) + count_bits + seg.bits
  })
}

/// The error for a payload that `version` cannot carry in any mode it
/// allows: the first character no allowed mode can encode. `at_index`
/// counts Unicode code points, as `mode.encode` does. `ForceByte` needs Byte
/// mode, which M1 and M2 lack, so the first character is the culprit.
fn unsupported_at(
  text: String,
  preference: ModePreference,
  version: Int,
) -> EncodeError {
  let encodable = case preference, version {
    types.ForceByte, _ -> fn(_) { False }
    types.Auto, 1 -> mode.is_numeric_char
    types.Auto, _ -> fn(char) {
      mode.is_numeric_char(char) || mode.is_alphanumeric_char(char)
    }
  }
  first_unsupported_character(util.characters(text), 0, encodable)
}

fn first_unsupported_character(
  chars: List(String),
  index: Int,
  encodable: fn(String) -> Bool,
) -> EncodeError {
  case chars {
    [] -> UnsupportedCharacter(index, "")
    [char, ..rest] ->
      case encodable(char) {
        True -> first_unsupported_character(rest, index + 1, encodable)
        False -> UnsupportedCharacter(index, char)
      }
  }
}

/// Return the side length of a Micro QR version (M1..M4 → 11..17).
pub fn symbol_size(version: Int) -> Result(Int, EncodeError) {
  case version >= min_version && version <= max_version {
    True -> Ok(version * 2 + 9)
    False -> Error(InvalidVersion(version))
  }
}

/// Return the maximum data-and-header bit capacity for `(version, ecc)`.
pub fn data_capacity_bits(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  symbol(version, ecc) |> result.map(fn(found) { found.1 })
}

/// Number of error-correction codewords for `(version, ecc)`.
pub fn ec_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  symbol(version, ecc) |> result.map(fn(found) { found.2 })
}

/// The symbol number, data capacity in bits and error correction codeword
/// count of `(version, ecc)`, from `symbols`.
fn symbol(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(#(Int, Int, Int), EncodeError) {
  list.index_fold(symbols, Error(Nil), fn(found, entry, number) {
    case found, entry {
      Error(Nil), #(entry_version, entry_ecc, data_bits, ec_count)
        if entry_version == version && entry_ecc == ecc
      -> Ok(#(number, data_bits, ec_count))
      _, _ -> found
    }
  })
  |> result.replace_error(ErrorCorrectionNotSupported(Micro, ecc))
}

fn validate_version(version: Int) -> Result(Nil, EncodeError) {
  case version >= min_version && version <= max_version {
    True -> Ok(Nil)
    False -> Error(InvalidVersion(version))
  }
}

fn validate_ecc(ecc: ErrorCorrection) -> Result(Nil, EncodeError) {
  case ecc {
    Low | Medium | Quartile -> Ok(Nil)
    High -> Error(ErrorCorrectionNotSupported(Micro, High))
  }
}

fn do_find_version(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
  candidate: Int,
) -> Result(#(Int, List(segment.Segment)), EncodeError) {
  case candidate > max_version {
    True -> Error(no_version_fits_error(text, ecc, preference))
    False ->
      case check_version(text, ecc, preference, candidate) {
        Ok(found) -> Ok(found)
        Error(_) -> do_find_version(text, ecc, preference, candidate + 1)
      }
  }
}

/// Build a `DataExceedsCapacity` error for the bailout case where no Micro QR
/// version in `min_version..=max_version` accepts the payload at `ecc`. The
/// fields point at the M4 ceiling (every Micro QR mode is supported at M4) so
/// the caller can see how far over the Micro-QR ceiling the input is.
fn no_version_fits_error(
  text: String,
  ecc: ErrorCorrection,
  preference: ModePreference,
) -> EncodeError {
  let bits_needed = case segments_at(text, preference, max_version) {
    Ok(segments) -> segments_bits(segments, max_version)
    Error(_) -> mode.utf8_byte_length(text) * 8
  }
  let bits_available = case data_capacity_bits(max_version, ecc) {
    Ok(value) -> value
    Error(_) -> 0
  }
  DataExceedsCapacity(bits_needed, bits_available)
}

fn mode_supported(selected_mode: Mode, version: Int) -> Bool {
  case version, selected_mode {
    1, Numeric -> True
    1, _ -> False
    2, Numeric | 2, Alphanumeric -> True
    2, _ -> False
    _, _ -> True
  }
}

/// Width of the mode indicator at `version` (M1 has none).
pub fn mode_indicator_bits(version: Int) -> Int {
  version - 1
}

fn mode_indicator_value(selected_mode: Mode) -> Int {
  case selected_mode {
    Numeric -> 0
    Alphanumeric -> 1
    Byte -> 2
    Kanji -> 3
  }
}

/// Width of the character count indicator of `selected_mode` at `version`.
pub fn char_count_bits_for_mode(
  selected_mode: Mode,
  version: Int,
) -> Result(Int, Nil) {
  case version, selected_mode {
    1, Numeric -> Ok(3)
    2, Numeric -> Ok(4)
    2, Alphanumeric -> Ok(3)
    3, Numeric -> Ok(5)
    3, Alphanumeric -> Ok(4)
    3, Byte -> Ok(4)
    3, Kanji -> Ok(3)
    4, Numeric -> Ok(6)
    4, Alphanumeric -> Ok(5)
    4, Byte -> Ok(5)
    4, Kanji -> Ok(4)
    _, _ -> Error(Nil)
  }
}

fn create_codewords(
  segments: List(segment.Segment),
  ecc: ErrorCorrection,
  version: Int,
) -> Result(List(Int), EncodeError) {
  use capacity <- result.try(data_capacity_bits(version, ecc))
  use stream <- result.try(
    segment.append_segments(bitstream.new(), segments, fn(seg) {
      char_count_bits_for_mode(seg.mode, version)
      |> result.map(segment.Header(
        mode_indicator_value(seg.mode),
        mode_indicator_bits(version),
        _,
      ))
      |> result.replace_error(
        first_unsupported_character(util.characters(seg.data), seg.index, fn(_) {
          False
        }),
      )
    }),
  )
  let total_bits = bitstream.length_bits(stream)
  case total_bits > capacity {
    True -> Error(DataExceedsCapacity(total_bits, capacity))
    False -> {
      let terminator_bits = terminator_size(version, capacity - total_bits)
      let with_terminator =
        bitstream.append_bits(stream, 0, size: terminator_bits)
      let padded = pad_to_capacity(with_terminator, version, ecc)
      let data_bytes = bitstream.to_byte_list(padded)
      use ec_bytes <- result.try(compute_ec(data_bytes, version, ecc))
      Ok(list.append(data_bytes, ec_bytes))
    }
  }
}

fn terminator_size(version: Int, remaining: Int) -> Int {
  let target = version * 2 + 1
  case remaining < target {
    True -> remaining
    False -> target
  }
}

fn pad_to_capacity(
  stream: bitstream.BitStream,
  version: Int,
  ecc: ErrorCorrection,
) -> bitstream.BitStream {
  let aligned = bitstream.pad_to_byte_boundary(stream)
  let data_bytes_count = case data_codewords(version, ecc) {
    Ok(value) -> value
    Error(_) -> 0
  }
  case has_half_codeword(version, ecc) {
    // The final data codeword of M1, M3-L and M3-M holds only 4 bits, and
    // ISO/IEC 18004 7.4.10 pads it with 0000: alternate pad codewords fill
    // the full codewords, then the half codeword stays zero. A full 0xEC
    // there would put 1100 into the error correction input that the symbol
    // never carries, and a reader would see one codeword error.
    True ->
      bitstream.append_pad_codewords(aligned, until: data_bytes_count - 1)
      |> pad_zero(data_bytes_count)
    False -> bitstream.append_pad_codewords(aligned, until: data_bytes_count)
  }
}

fn pad_zero(
  stream: bitstream.BitStream,
  target_bytes: Int,
) -> bitstream.BitStream {
  case bitstream.length_bits(stream) / 8 >= target_bytes {
    True -> stream
    False -> pad_zero(bitstream.append_byte(stream, 0), target_bytes)
  }
}

/// Total number of full data codewords for `(version, ecc)`. Half-byte cases
/// (M1-L, M3-L, M3-M) round up to the next byte; the half-codeword behaviour is
/// applied during matrix placement.
fn data_codewords(
  version: Int,
  ecc: ErrorCorrection,
) -> Result(Int, EncodeError) {
  case data_capacity_bits(version, ecc) {
    Ok(bits) -> Ok({ bits + 7 } / 8)
    Error(error) -> Error(error)
  }
}

fn compute_ec(
  data: List(Int),
  version: Int,
  ecc: ErrorCorrection,
) -> Result(List(Int), EncodeError) {
  case ec_codewords(version, ecc) {
    Ok(degree) -> Ok(reed_solomon.encode(data, degree))
    Error(error) -> Error(error)
  }
}

/// M1, M3-L and M3-M end their data with a 4-bit codeword.
fn has_half_codeword(version: Int, ecc: ErrorCorrection) -> Bool {
  case version, ecc {
    1, Low -> True
    3, Low -> True
    3, Medium -> True
    _, _ -> False
  }
}

/// The `(row, col)` of every data module of M`version`, in placement order.
pub fn data_module_positions(version: Int) -> List(#(Int, Int)) {
  case symbol_size(version) {
    Ok(size) ->
      matrix.data_positions(function_patterns(size), skip_column: None)
    Error(_) -> []
  }
}

fn function_patterns(size: Int) -> matrix.Matrix {
  matrix.new(size, size)
  |> draw_finder
  |> draw_timing(size)
  |> reserve_format_info
}

/// The 15-bit format information of a symbol given as `module(row, col)`,
/// in the bit order `place_format_info` writes.
pub fn read_format(module: fn(Int, Int) -> Bool) -> Int {
  let horizontal =
    int.range(from: 0, to: 8, with: 0, run: fn(acc, index) {
      acc
      + util.bool_to_int(module(8, index + 1))
      * int.bitwise_shift_left(1, 14 - index)
    })
  int.range(from: 0, to: 7, with: horizontal, run: fn(acc, index) {
    acc
    + util.bool_to_int(module(7 - index, 8))
    * int.bitwise_shift_left(1, 6 - index)
  })
}

/// The version, error correction level and mask whose format information is
/// within 3 bits of `bits`.
pub fn decode_format(bits: Int) -> Result(#(Int, ErrorCorrection, Int), Nil) {
  let candidates =
    list.index_map(symbols, fn(entry, number) {
      let #(version, ecc, _, _) = entry
      list.map([0, 1, 2, 3], fn(mask_number) {
        #(
          #(version, ecc, mask_number),
          util.at_or(format_info_table, number * 4 + mask_number, default: -1),
        )
      })
    })
    |> list.flatten
  format_info.nearest(candidates, [bits], 3)
}

fn build_matrix(
  chosen_version: Int,
  ecc: ErrorCorrection,
  codewords: List(Int),
) -> Result(#(Int, matrix.Matrix), EncodeError) {
  case symbol_size(chosen_version) {
    Error(error) -> Error(error)
    Ok(size) -> {
      let with_data =
        place_codewords(function_patterns(size), codewords, chosen_version, ecc)
      let #(best_mask, masked) =
        choose_best_mask(with_data, chosen_version, ecc, size)
      Ok(#(best_mask, place_format_info(masked, chosen_version, ecc, best_mask)))
    }
  }
}

fn draw_finder(target: matrix.Matrix) -> matrix.Matrix {
  int.range(from: 0, to: finder_size + 1, with: target, run: fn(acc, row) {
    int.range(from: 0, to: finder_size + 1, with: acc, run: fn(acc2, col) {
      draw_finder_module(acc2, row, col)
    })
  })
}

fn draw_finder_module(
  target: matrix.Matrix,
  row: Int,
  col: Int,
) -> matrix.Matrix {
  let dark = case row == finder_size || col == finder_size {
    True -> False
    False ->
      row == 0
      || row == finder_size - 1
      || col == 0
      || col == finder_size - 1
      || { row >= 2 && row <= 4 && col >= 2 && col <= 4 }
  }
  matrix.set(target, row, col, dark, reserved: True)
}

fn draw_timing(target: matrix.Matrix, size: Int) -> matrix.Matrix {
  int.range(from: finder_size + 1, to: size, with: target, run: fn(acc, index) {
    let dark = index % 2 == 0
    acc
    |> matrix.set(0, index, dark, reserved: True)
    |> matrix.set(index, 0, dark, reserved: True)
  })
}

fn reserve_format_info(target: matrix.Matrix) -> matrix.Matrix {
  let horizontal =
    int.range(from: 1, to: 9, with: target, run: fn(acc, col) {
      matrix.set(acc, 8, col, False, reserved: True)
    })
  int.range(from: 1, to: 8, with: horizontal, run: fn(acc, row) {
    matrix.set(acc, row, 8, False, reserved: True)
  })
}

fn place_codewords(
  target: matrix.Matrix,
  codewords: List(Int),
  version: Int,
  ecc: ErrorCorrection,
) -> matrix.Matrix {
  let half = has_half_codeword(version, ecc)
  let data_count = case data_codewords(version, ecc) {
    Ok(value) -> value
    Error(_) -> 0
  }
  let bits = codewords_to_bits(codewords, data_count, half, 0, [])
  matrix.write_bits(
    target,
    matrix.data_positions(target, skip_column: None),
    bits,
  )
}

fn codewords_to_bits(
  codewords: List(Int),
  data_count: Int,
  half_codeword: Bool,
  index: Int,
  acc: List(Bool),
) -> List(Bool) {
  case codewords {
    [] -> list.reverse(acc)
    [byte, ..rest] -> {
      let bit_count = case half_codeword && index + 1 == data_count {
        True -> 4
        False -> 8
      }
      // Write bit_count bits starting from the high end (MSB first) so a half
      // codeword contributes bits 7..4 — ISO/IEC 18004 §6.4.10.
      let next_acc = append_byte_bits(byte, 7, bit_count, acc)
      codewords_to_bits(rest, data_count, half_codeword, index + 1, next_acc)
    }
  }
}

fn append_byte_bits(
  byte: Int,
  bit_position: Int,
  remaining: Int,
  acc: List(Bool),
) -> List(Bool) {
  case remaining <= 0 {
    True -> acc
    False ->
      append_byte_bits(byte, bit_position - 1, remaining - 1, [
        util.bit_at(byte, bit_position),
        ..acc
      ])
  }
}

/// Try the four Micro QR masks and keep the one with the highest Annex K
/// score; the lowest mask number wins a tie.
fn choose_best_mask(
  target: matrix.Matrix,
  version: Int,
  ecc: ErrorCorrection,
  size: Int,
) -> #(Int, matrix.Matrix) {
  let evaluate = fn(candidate) {
    let placed =
      mask.apply_with(target, fn(row, col) { mask_at(candidate, row, col) })
      |> place_format_info(version, ecc, candidate)
    #(candidate, placed, micro_penalty(placed, size))
  }
  let #(best_mask, best_matrix, _) =
    list.fold([1, 2, 3], evaluate(0), fn(best, candidate) {
      let next = evaluate(candidate)
      case next.2 > best.2 {
        True -> next
        False -> best
      }
    })
  #(best_mask, best_matrix)
}

/// Micro QR data mask `mask` (0..3) at `(row, col)`.
pub fn mask_at(mask: Int, row: Int, col: Int) -> Bool {
  case mask {
    0 -> row % 2 == 0
    1 -> { row / 2 + col / 3 } % 2 == 0
    2 -> { row * col % 2 + row * col % 3 } % 2 == 0
    _ -> { { row + col } % 2 + row * col % 3 } % 2 == 0
  }
}

/// Annex K evaluation: count dark modules on the right column and bottom row
/// of the symbol; pick the mask that maximises the score
/// `min(rp1, rp2) * 16 + max(rp1, rp2)` (ISO/IEC 18004 §G.2 / Annex K).
fn micro_penalty(target: matrix.Matrix, size: Int) -> Int {
  let last = size - 1
  let dark_right = count_dark_edge(target, last, 1, last, True)
  let dark_bottom = count_dark_edge(target, 1, last, last, False)
  let high = case dark_right >= dark_bottom {
    True -> dark_right
    False -> dark_bottom
  }
  let low = case dark_right >= dark_bottom {
    True -> dark_bottom
    False -> dark_right
  }
  low * 16 + high
}

fn count_dark_edge(
  target: matrix.Matrix,
  axis: Int,
  from: Int,
  to: Int,
  vertical: Bool,
) -> Int {
  do_count_dark_edge(target, axis, from, to, vertical, 0)
}

fn do_count_dark_edge(
  target: matrix.Matrix,
  axis: Int,
  current: Int,
  to: Int,
  vertical: Bool,
  acc: Int,
) -> Int {
  case current > to {
    True -> acc
    False -> {
      let dark = case vertical {
        True -> matrix.get(target, current, axis)
        False -> matrix.get(target, axis, current)
      }
      let next_acc = case dark {
        True -> acc + 1
        False -> acc
      }
      do_count_dark_edge(target, axis, current + 1, to, vertical, next_acc)
    }
  }
}

fn place_format_info(
  target: matrix.Matrix,
  version: Int,
  ecc: ErrorCorrection,
  mask: Int,
) -> matrix.Matrix {
  let bits = format_bits(version, ecc, mask)
  let horizontal = place_horizontal_format(target, bits)
  place_vertical_format(horizontal, bits)
}

fn place_horizontal_format(target: matrix.Matrix, bits: Int) -> matrix.Matrix {
  int.range(from: 0, to: 8, with: target, run: fn(acc, index) {
    let col = index + 1
    let dark = util.bit_at(bits, 14 - index)
    matrix.set(acc, 8, col, dark, reserved: True)
  })
}

fn place_vertical_format(target: matrix.Matrix, bits: Int) -> matrix.Matrix {
  int.range(from: 0, to: 7, with: target, run: fn(acc, index) {
    let row = 7 - index
    let dark = util.bit_at(bits, 6 - index)
    matrix.set(acc, row, 8, dark, reserved: True)
  })
}

fn format_bits(version: Int, ecc: ErrorCorrection, mask: Int) -> Int {
  case symbol(version, ecc) {
    Ok(#(number, _, _)) -> {
      let index = number * 4 + mask
      util.at_or(format_info_table, index, default: format_xor_mask)
    }
    Error(_) -> format_xor_mask
  }
}
