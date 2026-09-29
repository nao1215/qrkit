//// Segment building for standard QR Code symbols.

import gleam/list
import gleam/option.{type Option, None, Some}
import qrkit/error.{type EncodeError, InvalidEciDesignator}
import qrkit/internal/bitstream
import qrkit/internal/mode
import qrkit/internal/util
import qrkit/types.{
  type Mode, type ModePreference, Alphanumeric, Auto, Byte, ForceByte, Kanji,
  Numeric,
}

pub opaque type Segment {
  Segment(mode: Mode, data: String, count: Int, bits: Int, index: Int)
}

pub fn mode(segment: Segment) -> Mode {
  let Segment(mode, _, _, _, _) = segment
  mode
}

pub fn data(segment: Segment) -> String {
  let Segment(_, data, _, _, _) = segment
  data
}

pub fn count(segment: Segment) -> Int {
  let Segment(_, _, count, _, _) = segment
  count
}

pub fn bits(segment: Segment) -> Int {
  let Segment(_, _, _, bits, _) = segment
  bits
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
      header_bits(mode(segment)) != Error(Nil)
      && list.all(util.characters(data(segment)), fn(char) {
        char_cost(char, mode(segment)) < unreachable
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

/// Index of the segment's first character in the whole payload.
pub fn index(segment: Segment) -> Int {
  segment_index(segment)
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
    acc + 4 + mode.char_count_bits(mode(segment), version) + bits(segment)
  })
}

pub fn append_to_stream(
  stream: bitstream.BitStream,
  segments: List(Segment),
  version: Int,
  eci: Option(Int),
) -> Result(bitstream.BitStream, EncodeError) {
  let with_eci = case eci {
    None -> Ok(stream)
    Some(value) -> append_eci(stream, value)
  }
  case with_eci {
    Error(error) -> Error(error)
    Ok(stream_with_eci) ->
      do_append_segments(stream_with_eci, segments, version)
  }
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
        |> result_or(current)
      trace_back(rest, previous, [previous, ..acc])
    }
  }
}

fn result_or(result: Result(a, Nil), default: a) -> a {
  case result {
    Ok(value) -> value
    Error(Nil) -> default
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

fn do_append_segments(
  stream: bitstream.BitStream,
  segments: List(Segment),
  version: Int,
) -> Result(bitstream.BitStream, EncodeError) {
  case segments {
    [] -> Ok(stream)
    [segment, ..rest] ->
      case
        mode.encode(
          data(segment),
          mode(segment),
          at_index: segment_index(segment),
        )
      {
        Ok(bits) ->
          do_append_segments(
            bitstream.append_bits(
              stream,
              mode.mode_bits(mode(segment)),
              size: 4,
            )
              |> bitstream.append_bits(
                count(segment),
                size: mode.char_count_bits(mode(segment), version),
              )
              |> bitstream.append_bytes(bits),
            rest,
            version,
          )
        Error(error) -> Error(error)
      }
  }
}

fn append_eci(
  stream: bitstream.BitStream,
  designator: Int,
) -> Result(bitstream.BitStream, EncodeError) {
  case designator < 0 || designator > 999_999 {
    True -> Error(InvalidEciDesignator(designator))
    False ->
      case designator < 128 {
        True ->
          Ok(
            stream
            |> bitstream.append_bits(0b0111, size: 4)
            |> bitstream.append_bits(designator, size: 8),
          )
        False ->
          case designator < 16_384 {
            True ->
              Ok(
                stream
                |> bitstream.append_bits(0b0111, size: 4)
                |> bitstream.append_bits(0b10, size: 2)
                |> bitstream.append_bits(designator, size: 14),
              )
            False ->
              Ok(
                stream
                |> bitstream.append_bits(0b0111, size: 4)
                |> bitstream.append_bits(0b110, size: 3)
                |> bitstream.append_bits(designator, size: 21),
              )
          }
      }
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

fn segment_index(segment: Segment) -> Int {
  let Segment(_, _, _, _, index) = segment
  index
}
