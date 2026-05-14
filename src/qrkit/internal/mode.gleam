//// Mode detection and payload encoding for standard QR symbols.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import qrkit/error.{type EncodeError, UnsupportedCharacter}
import qrkit/internal/bitstream
import qrkit/internal/util
import qrkit/types.{type Mode, Alphanumeric, Byte, Kanji, Numeric}

const alphanumeric_chars = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F",
  "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V",
  "W", "X", "Y", "Z", " ", "$", "%", "*", "+", "-", ".", "/", ":",
]

pub fn mode_bits(mode: Mode) -> Int {
  case mode {
    Numeric -> 0b0001
    Alphanumeric -> 0b0010
    Byte -> 0b0100
    Kanji -> 0b1000
  }
}

pub fn char_count_bits(mode: Mode, version: Int) -> Int {
  case version < 10 {
    True ->
      case mode {
        Numeric -> 10
        Alphanumeric -> 9
        Byte -> 8
        Kanji -> 8
      }
    False ->
      case version < 27 {
        True ->
          case mode {
            Numeric -> 12
            Alphanumeric -> 11
            Byte -> 16
            Kanji -> 10
          }
        False ->
          case mode {
            Numeric -> 14
            Alphanumeric -> 13
            Byte -> 16
            Kanji -> 12
          }
      }
  }
}

pub fn character_count(data: String, mode: Mode) -> Int {
  case mode {
    Byte -> utf8_byte_length(data)
    _ -> list.length(util.characters(data))
  }
}

pub fn data_bits_length(data: String, mode: Mode) -> Int {
  case mode {
    Numeric -> numeric_bits_length(list.length(util.characters(data)))
    Alphanumeric -> alphanumeric_bits_length(list.length(util.characters(data)))
    Byte -> utf8_byte_length(data) * 8
    Kanji -> list.length(util.characters(data)) * 13
  }
}

pub fn utf8_byte_length(text: String) -> Int {
  text |> bit_array.from_string |> bit_array.byte_size
}

pub fn is_numeric_char(char: String) -> Bool {
  case int.parse(char) {
    Ok(value) -> value >= 0 && value <= 9
    Error(_) -> False
  }
}

pub fn is_alphanumeric_char(char: String) -> Bool {
  char |> alphanumeric_value |> is_ok
}

pub fn is_kanji_char(char: String) -> Bool {
  char |> to_sjis |> is_ok
}

pub fn encode(
  data: String,
  mode: Mode,
  at_index index: Int,
) -> Result(BitArray, EncodeError) {
  case mode {
    Numeric -> Ok(encode_numeric(data))
    Alphanumeric -> encode_alphanumeric(data, at_index: index)
    Byte -> Ok(encode_byte(data))
    Kanji -> encode_kanji(data, at_index: index)
  }
}

pub fn numeric_bits_length(length: Int) -> Int {
  10
  * { length / 3 }
  + case length % 3 {
    0 -> 0
    1 -> 4
    _ -> 7
  }
}

pub fn alphanumeric_bits_length(length: Int) -> Int {
  11
  * { length / 2 }
  + case length % 2 {
    0 -> 0
    _ -> 6
  }
}

pub fn numeric_increment_cost(mod3: Int) -> Int {
  case mod3 {
    0 -> 4
    _ -> 3
  }
}

pub fn alphanumeric_increment_cost(mod2: Int) -> Int {
  case mod2 {
    0 -> 6
    _ -> 5
  }
}

fn encode_numeric(data: String) -> BitArray {
  do_encode_numeric(util.characters(data), bitstream.new())
  |> bitstream.to_bit_array
}

fn do_encode_numeric(
  chars: List(String),
  stream: bitstream.BitStream,
) -> bitstream.BitStream {
  case chars {
    [a, b, c, ..rest] -> {
      let value = must_parse(a <> b <> c)
      do_encode_numeric(rest, bitstream.append_bits(stream, value, size: 10))
    }
    [a, b] -> {
      let value = must_parse(a <> b)
      bitstream.append_bits(stream, value, size: 7)
    }
    [a] -> {
      let value = must_parse(a)
      bitstream.append_bits(stream, value, size: 4)
    }
    [] -> stream
  }
}

fn encode_alphanumeric(
  data: String,
  at_index index: Int,
) -> Result(BitArray, EncodeError) {
  do_encode_alphanumeric(util.characters(data), index, bitstream.new())
}

fn do_encode_alphanumeric(
  chars: List(String),
  index: Int,
  stream: bitstream.BitStream,
) -> Result(BitArray, EncodeError) {
  case chars {
    [a, b, ..rest] ->
      case alphanumeric_value(a), alphanumeric_value(b) {
        Ok(first), Ok(second) ->
          do_encode_alphanumeric(
            rest,
            index + 2,
            bitstream.append_bits(stream, first * 45 + second, size: 11),
          )
        Error(_), _ -> Error(UnsupportedCharacter(index, a))
        _, Error(_) -> Error(UnsupportedCharacter(index + 1, b))
      }
    [a] ->
      case alphanumeric_value(a) {
        Ok(value) ->
          Ok(
            bitstream.append_bits(stream, value, size: 6)
            |> bitstream.to_bit_array,
          )
        Error(_) -> Error(UnsupportedCharacter(index, a))
      }
    [] -> Ok(bitstream.to_bit_array(stream))
  }
}

fn encode_byte(data: String) -> BitArray {
  bit_array.from_string(data)
}

fn encode_kanji(
  data: String,
  at_index index: Int,
) -> Result(BitArray, EncodeError) {
  do_encode_kanji(util.characters(data), index, bitstream.new())
}

fn do_encode_kanji(
  chars: List(String),
  index: Int,
  stream: bitstream.BitStream,
) -> Result(BitArray, EncodeError) {
  case chars {
    [char, ..rest] ->
      case to_sjis(char) {
        Ok(sjis) -> {
          let adjusted = case sjis >= 0x8140 && sjis <= 0x9FFC {
            True -> sjis - 0x8140
            False -> sjis - 0xC140
          }
          let value = { adjusted / 256 } * 0xC0 + adjusted % 256
          do_encode_kanji(
            rest,
            index + 1,
            bitstream.append_bits(stream, value, size: 13),
          )
        }
        Error(_) -> Error(UnsupportedCharacter(index, char))
      }
    [] -> Ok(bitstream.to_bit_array(stream))
  }
}

fn alphanumeric_value(char: String) -> Result(Int, Nil) {
  do_alphanumeric_value(alphanumeric_chars, char, 0)
}

fn do_alphanumeric_value(
  chars: List(String),
  needle: String,
  index: Int,
) -> Result(Int, Nil) {
  case chars {
    [] -> Error(Nil)
    [char, ..rest] ->
      case char == needle {
        True -> Ok(index)
        False -> do_alphanumeric_value(rest, needle, index + 1)
      }
  }
}

fn must_parse(text: String) -> Int {
  case int.parse(text) {
    Ok(value) -> value
    Error(_) -> 0
  }
}

fn is_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn to_sjis(char: String) -> Result(Int, Nil) {
  case util.characters(char) {
    [first] ->
      case string.to_utf_codepoints(first) {
        [codepoint] -> codepoint_to_sjis(string.utf_codepoint_to_int(codepoint))
        _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn codepoint_to_sjis(codepoint: Int) -> Result(Int, Nil) {
  case codepoint >= 0x3041 && codepoint <= 0x3093 {
    True -> Ok(0x829F + codepoint - 0x3041)
    False ->
      case codepoint >= 0x30A1 && codepoint <= 0x30F6 {
        True -> Ok(katakana_sjis(codepoint))
        False ->
          case codepoint >= 0xFF10 && codepoint <= 0xFF19 {
            True -> Ok(0x824F + codepoint - 0xFF10)
            False ->
              case codepoint >= 0xFF21 && codepoint <= 0xFF3A {
                True -> Ok(0x8260 + codepoint - 0xFF21)
                False ->
                  case codepoint >= 0xFF41 && codepoint <= 0xFF5A {
                    True -> Ok(0x8281 + codepoint - 0xFF41)
                    False -> punctuation_sjis(codepoint)
                  }
              }
          }
      }
  }
}

fn katakana_sjis(codepoint: Int) -> Int {
  let offset = codepoint - 0x30A1
  case offset >= 63 {
    True -> 0x8340 + offset + 1
    False -> 0x8340 + offset
  }
}

fn punctuation_sjis(codepoint: Int) -> Result(Int, Nil) {
  case codepoint {
    0x3000 -> Ok(0x8140)
    0x3001 -> Ok(0x8141)
    0x3002 -> Ok(0x8142)
    0x30FC -> Ok(0x815B)
    _ -> Error(Nil)
  }
}
