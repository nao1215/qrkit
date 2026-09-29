#!/usr/bin/env python3
"""Cross-check qrkit against independent QR implementations.

  interop.py zxing  build/interop/qrkit.tsv
      Decode every symbol `gleam run -m gen/interop_corpus` wrote with
      zxing-cpp and compare the text. Exits 1 on any disagreement.

  interop.py segno  build/interop/segno.tsv [count]
      Encode random strings with segno (Standard QR, Micro QR, ECI and
      Structured Append parts) for `gleam run -m gen/interop_decode`, which
      must read each symbol as zxing-cpp does. zxing-cpp's text is the
      expected value rather than the input: Byte data without an ECI is
      ambiguous (0xDF 0xDF is "ßß" in ISO-8859-1 and "ﾟﾟ" in Shift JIS) and
      both readers guess the same way. Symbols zxing-cpp cannot read are
      left out, so a failure points at qrkit.

The nightly workflow installs the pinned packages from
scripts/interop-requirements.txt (pip --require-hashes).
"""

import pathlib
import random
import sys

import numpy as np
import segno
import zxingcpp

FORMATS = {
    "qr": zxingcpp.BarcodeFormat.QRCode,
    "micro": zxingcpp.BarcodeFormat.MicroQRCode,
    "rmqr": zxingcpp.BarcodeFormat.RMQRCode,
}
QUIET = {"qr": 4, "micro": 2, "rmqr": 2}
SCALE = 6
POOLS = [
    "0123456789",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:",
    "abcdefghijklmnopqrstuvwxyz",
    "あいうえおかきくけこアイウエオ",
    "東京都千代田区丸の内漢字日本語",
    "!?#&=@_~",
    "éß中",
    "\n",
]


def render(rows, quiet):
    height, width = len(rows), len(rows[0])
    image = np.full((height + 2 * quiet, width + 2 * quiet), 255, dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, cell in enumerate(row):
            if cell:
                image[y + quiet, x + quiet] = 0
    return np.kron(image, np.ones((SCALE, SCALE), dtype=np.uint8))


def zxing(path):
    failures = 0
    lines = [line for line in pathlib.Path(path).read_text().splitlines() if line]
    for line in lines:
        symbol, level, text_hex, rows_text = line.split("\t")
        text = bytes.fromhex(text_hex).decode("utf-8")
        rows = [[c == "1" for c in row] for row in rows_text.split("/")]
        results = zxingcpp.read_barcodes(render(rows, QUIET[symbol]), formats=FORMATS[symbol])
        got = results[0].text if results else None
        if got != text:
            failures += 1
            print(f"MISMATCH {symbol}-{level} {text!r} -> {got!r}")
    print(f"zxing-cpp read {len(lines) - failures} of {len(lines)} qrkit symbols")
    return 1 if failures else 0


def random_text(rng):
    length = rng.randint(1, 60)
    chars = []
    while len(chars) < length:
        pool = rng.choice(POOLS)
        chars.extend(rng.choice(pool) for _ in range(rng.randint(1, 10)))
    return "".join(chars[:length])


def zxing_text(qr):
    rows = [list(row) for row in qr.matrix_iter(border=0)]
    quiet = 2 if qr.is_micro else 4
    results = zxingcpp.read_barcodes(render(rows, quiet))
    return results[0].text if results else None


def rows_of(qr):
    return "/".join("".join("1" if v else "0" for v in row) for row in qr.matrix_iter(border=0))


def segno_corpus(path, count):
    rng = random.Random()
    lines, skipped = [], 0
    while len(lines) < count:
        text = random_text(rng)
        variant = rng.choice(["qr", "qr-eci", "micro", "sequence"])
        try:
            if variant == "sequence":
                symbols = list(segno.make_sequence(text, symbol_count=2, error=rng.choice("LMQH")))
            else:
                symbols = [
                    segno.make(
                        text,
                        error=rng.choice("LMQ" if variant == "micro" else "LMQH"),
                        micro=variant == "micro",
                        eci=variant == "qr-eci",
                    )
                ]
        except Exception:
            continue
        for index, qr in enumerate(symbols):
            expected = zxing_text(qr)
            if expected is None:
                skipped += 1
                continue
            label = f"sequence-{index}/{len(symbols)}" if variant == "sequence" else variant
            lines.append(f"{label}\t{expected.encode().hex()}\t{rows_of(qr)}")
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(path).write_text("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} segno symbols to {path} ({skipped} skipped: zxing-cpp cannot read them either)")
    return 0


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("zxing", "segno"):
        print(__doc__)
        return 2
    if sys.argv[1] == "zxing":
        return zxing(sys.argv[2])
    return segno_corpus(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 600)


if __name__ == "__main__":
    sys.exit(main())
