//// Regression tests for #22: `DataExceedsCapacity(bits_needed, bits_available)`
//// must always carry informative, non-zero fields when the payload truly
//// cannot fit. Before the fix, three code paths returned `(0, 0)`:
////   - Micro QR `find_version` (no M1..M4 version accepts the payload)
////   - rMQR `find_version` (no R7×43..R17×139 version accepts the payload)
////   - `encode_split` (no Structured Append split with `total <= 16` fits)
//// The Standard-QR path already populated both fields; this file pins that
//// behaviour too so the Standard regression cannot silently break.

import gleam/string
import gleeunit/should
import qrkit
import qrkit/error
import qrkit/types

/// Assert the error is `DataExceedsCapacity` and both fields are strictly
/// positive — the whole point of #22 is that callers can render "your payload
/// is X bits over the ceiling," which is impossible if either field is zero.
fn expect_capacity_error(result: Result(a, error.EncodeError)) -> Nil {
  case result {
    Error(error.DataExceedsCapacity(bits_needed, bits_available)) -> {
      should.be_true(bits_needed > 0)
      should.be_true(bits_available > 0)
      should.be_true(bits_needed > bits_available)
    }
    _ -> should.fail()
  }
}

pub fn micro_qr_overflow_carries_informative_fields_test() -> Nil {
  // ~190 character Byte-mode payload — well beyond M4 / Low's 128-bit ceiling.
  // Before #22 this returned `DataExceedsCapacity(0, 0)`; now it must report
  // the encoded-bit count vs the M4 capacity so the caller can render a
  // useful overflow message.
  let payload = string.repeat("X", 190)
  qrkit.new(payload)
  |> qrkit.with_symbol(types.Micro)
  |> qrkit.with_ecc(types.Low)
  |> qrkit.build
  |> expect_capacity_error
}

pub fn rmqr_overflow_carries_informative_fields_test() -> Nil {
  // 200-character Byte-mode payload at rMQR + Medium. Even the largest rMQR
  // (R17×139, 152 data codewords = 1216 data bits at Medium) cannot hold
  // 200 bytes of header + Byte-mode payload comfortably once char-count and
  // mode overhead are accounted for. Before #22 this returned
  // `DataExceedsCapacity(0, 0)`.
  let payload = string.repeat("a", 200)
  // Force the encoder to pick rMQR and walk all 32 versions.
  qrkit.new(payload)
  |> qrkit.with_symbol(types.Rectangular)
  |> qrkit.with_ecc(types.Medium)
  |> qrkit.build
  |> expect_capacity_error
}

pub fn encode_split_overflow_carries_informative_fields_test() -> Nil {
  // `encode_split(payload, max_version=1)` caps every shard at v1 (≈ 17 byte
  // codewords at Medium). A "Hello, world! " × 200 payload (= 2800 bytes) is
  // far past 16 shards × v1 capacity, forcing the bailout in `find_split`.
  // Before #22 this returned `DataExceedsCapacity(0, 0)`.
  let payload = string.repeat("Hello, world! ", 200)
  qrkit.encode_split(payload, 1)
  |> expect_capacity_error
}

pub fn standard_overflow_carries_informative_fields_regression_test() -> Nil {
  // The Standard-QR `internal/standard.gleam:115` path already populates both
  // fields. Pin it so a refactor cannot silently regress to `(0, 0)`.
  let payload = string.repeat("A", 1000)
  qrkit.new(payload)
  |> qrkit.with_exact_version(1)
  |> qrkit.build
  |> expect_capacity_error
}
