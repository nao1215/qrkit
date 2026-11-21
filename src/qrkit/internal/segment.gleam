//// Segment building for standard QR Code symbols.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import qrkit/error.{type EncodeError}
import qrkit/internal/bitstream
import qrkit/internal/mode
import qrkit/internal/util
import qrkit/types.{
  type Mode, type ModePreference, Alphanumeric, Auto, Byte, ForceByte, Kanji,
  Numeric,
}

/// A run of the payload in one mode: its characters, character count,
/// data length in bits and the index of its first character in the whole
/// payload.
pub type Segment {
  Segment(mode: Mode, data: String, count: Int, bits: Int, index: Int)
}

/// The segment header of a symbol family for one mode: the mode indicator
/// value and width, and the width of the character count.
pub type Header {
  Header(indicator: Int, indicator_bits: Int, count_bits: Int)
}

pub fn optimise(
  text: String,
  version: Int,
  preference: ModePreference,
) -> Result(List(Segment), EncodeError) {
  case preference {
    ForceByte -> Ok([build_segment(Byte, text, 0)])
    Auto -> {
      let optimal =
        optimal_segments(util.characters(text), fn(m) {
          { 4 + mode.char_count_bits(m, version) } * 6
        })
      let single_byte = [build_segment(Byte, text, 0)]
      // The search below weighs Numeric and Alphanumeric characters by their
      // average bit cost, so at segment boundaries it can be a few bits off
      // the exact length. Keep whole-payload Byte when that is shorter.
      case
        encoded_bits(optimal, version, None)
        <= encoded_bits(single_byte, version, None)
      {
        True -> Ok(optimal)
        False -> Ok(single_byte)
      }
    }
  }
}

/// Split `text` into the segments with the fewest bits for a symbol whose
/// segment header (mode indicator plus character count) takes
/// `header_bits(mode)` bits, or `Error(Nil)` for a mode the symbol cannot use.
/// Returns `Error(Nil)` when some character fits none of the usable modes.
/// Used by Micro QR and rMQR, whose headers differ from Standard QR's.
pub fn split(
  text: String,
  header_bits: fn(Mode) -> Result(Int, Nil),
) -> Result(List(Segment), Nil) {
  let segments =
    optimal_segments(util.characters(text), fn(m) {
      case header_bits(m) {
        Ok(bits) -> bits * 6
        Error(Nil) -> unreachable
      }
    })
  case
    list.all(segments, fn(segment) {
      header_bits(segment.mode) != Error(Nil)
      && list.all(util.characters(segment.data), fn(char) {
        char_cost(char, segment.mode) < unreachable
      })
    })
  {
    True -> Ok(segments)
    False -> Error(Nil)
  }
}

/// A single segment carrying all of `text` in `segment_mode`.
pub fn single(text: String, segment_mode: Mode) -> Segment {
  build_segment(segment_mode, text, 0)
}

pub fn encoded_bits(
  segments: List(Segment),
  version: Int,
  eci: Option(Int),
) -> Int {
  let eci_bits = case eci {
    None -> 0
    Some(value) -> 4 + eci_designator_bits(value)
  }
  eci_bits
  + list.fold(segments, 0, fn(acc, segment) {
    acc + 4 + mode.char_count_bits(segment.mode, version) + segment.bits
  })
}

pub fn append_to_stream(
  stream: bitstream.BitStream,
  segments: List(Segment),
  version: Int,
  eci: Option(Int),
) -> Result(bitstream.BitStream, EncodeError) {
  let with_eci = case eci {
    None -> stream
    Some(value) -> append_eci(stream, value)
  }
  append_segments(with_eci, segments, fn(segment_mode) {
    Ok(Header(
      mode.mode_bits(segment_mode),
      4,
      mode.char_count_bits(segment_mode, version),
    ))
  })
}

/// Append every segment to `stream`: the mode indicator and character count
/// that `header` gives for its mode, then its data.
pub fn append_segments(
  stream: bitstream.BitStream,
  segments: List(Segment),
  header: fn(Mode) -> Result(Header, EncodeError),
) -> Result(bitstream.BitStream, EncodeError) {
  list.try_fold(segments, stream, fn(stream, segment) {
    use Header(indicator, indicator_bits, count_bits) <- result.try(header(
      segment.mode,
    ))
    use payload <- result.try(mode.encode(
      segment.data,
      segment.mode,
      at_index: segment.index,
    ))
    Ok(
      stream
      |> bitstream.append_bits(indicator, size: indicator_bits)
      |> bitstream.append_bits(segment.count, size: count_bits)
      |> bitstream.append_bytes(payload),
    )
  })
}

// Costs are in sixths of a bit so that Numeric (10 bits per 3 digits) and
// Alphanumeric (11 bits per 2 characters) stay integral.
const unreachable: Int = 1_000_000_000

const modes: List(Mode) = [Numeric, Alphanumeric, Byte, Kanji]

/// Split `chars` into the segments with the fewest bits at `version`
/// (ISO/IEC 18004 Annex J; the same dynamic programme as Nayuki's and
/// shogo82148/qrcode's encoders). For every character and every mode it
/// keeps the cheapest encoding of the prefix that ends in that mode, where
/// switching mode costs the 4-bit mode indicator plus the character count.
fn optimal_segments(
  chars: List(String),
  header: fn(Mode) -> Int,
) -> List(Segment) {
  case chars {
    [] -> []
    [first, ..rest] -> {
      let start = list.map(modes, fn(m) { add(header(m), char_cost(first, m)) })
      let #(costs, back) =
        list.fold(rest, #(start, []), fn(state, char) {
          let #(previous, back) = state
          let step =
            list.map(modes, fn(m) {
              let #(from, cost) = cheapest_entry(previous, m, header)
              #(add(cost, char_cost(char, m)), from)
            })
          #(list.map(step, fn(entry) { entry.0 }), [
            list.map(step, fn(entry) { entry.1 }),
            ..back
          ])
        })
      let #(last, _) = argmin(costs)
      let char_modes = trace_back(back, last, [last])
      group_segments(list.zip(chars, char_modes), 0, [], None)
    }
  }
}

/// The cheapest way to be in `target` after the previous character: either
/// stay in `target` or switch into it from another mode.
fn cheapest_entry(
  previous: List(Int),
  target: Mode,
  header: fn(Mode) -> Int,
) -> #(Mode, Int) {
  list.zip(modes, previous)
  |> list.map(fn(entry) {
    let #(from, cost) = entry
    case from == target {
      True -> #(from, cost)
      False -> #(from, add(cost, header(target)))
    }
  })
  |> list.fold(#(target, unreachable), fn(best, entry) {
    case entry.1 < best.1 {
      True -> entry
      False -> best
    }
  })
}

fn argmin(costs: List(Int)) -> #(Mode, Int) {
  list.zip(modes, costs)
  |> list.fold(#(Byte, unreachable), fn(best, entry) {
    case entry.1 < best.1 {
      True -> entry
      False -> best
    }
  })
}

/// `back` holds, newest first, the mode each mode was entered from at every
/// character after the first. Walk it to recover every character's mode.
fn trace_back(
  back: List(List(Mode)),
  current: Mode,
  acc: List(Mode),
) -> List(Mode) {
  case back {
    [] -> acc
    [froms, ..rest] -> {
      let previous =
        list.zip(modes, froms)
        |> list.key_find(current)
        |> result.unwrap(current)
      trace_back(rest, previous, [previous, ..acc])
    }
  }
}

fn group_segments(
  chars: List(#(String, Mode)),
  index: Int,
  acc: List(Segment),
  current: Option(#(Mode, String, Int)),
) -> List(Segment) {
  case chars, current {
    [], None -> list.reverse(acc)
    [], Some(#(m, text, start)) ->
      list.reverse([build_segment(m, text, start), ..acc])
    [#(char, m), ..rest], Some(#(current_mode, text, start))
      if m == current_mode
    -> group_segments(rest, index + 1, acc, Some(#(m, text <> char, start)))
    [#(char, m), ..rest], Some(#(current_mode, text, start)) ->
      group_segments(
        rest,
        index + 1,
        [build_segment(current_mode, text, start), ..acc],
        Some(#(m, char, index)),
      )
    [#(char, m), ..rest], None ->
      group_segments(rest, index + 1, acc, Some(#(m, char, index)))
  }
}

fn char_cost(char: String, m: Mode) -> Int {
  case m {
    Numeric ->
      case mode.is_numeric_char(char) {
        True -> 20
        False -> unreachable
      }
    Alphanumeric ->
      case mode.is_alphanumeric_char(char) {
        True -> 33
        False -> unreachable
      }
    Byte -> mode.utf8_byte_length(char) * 48
    Kanji ->
      case mode.is_kanji_char(char) {
        True -> 78
        False -> unreachable
      }
  }
}

fn add(left: Int, right: Int) -> Int {
  case left >= unreachable || right >= unreachable {
    True -> unreachable
    False -> left + right
  }
}

fn build_segment(current_mode: Mode, text: String, index: Int) -> Segment {
  Segment(
    current_mode,
    text,
    mode.character_count(text, current_mode),
    mode.data_bits_length(text, current_mode),
    index,
  )
}

/// The ECI header for `designator`, which `qrkit.build` has checked is in
/// 0..999999.
fn append_eci(
  stream: bitstream.BitStream,
  designator: Int,
) -> bitstream.BitStream {
  let with_indicator = bitstream.append_bits(stream, 0b0111, size: 4)
  case designator < 128, designator < 16_384 {
    True, _ -> bitstream.append_bits(with_indicator, designator, size: 8)
    False, True ->
      with_indicator
      |> bitstream.append_bits(0b10, size: 2)
      |> bitstream.append_bits(designator, size: 14)
    False, False ->
      with_indicator
      |> bitstream.append_bits(0b110, size: 3)
      |> bitstream.append_bits(designator, size: 21)
  }
}

fn eci_designator_bits(value: Int) -> Int {
  case value < 128 {
    True -> 8
    False ->
      case value < 16_384 {
        True -> 16
        False -> 24
      }
  }
}
