#!/usr/bin/env python3
"""Call the Python QR libraries for `gleam run -m interop`.

zxing-cpp, zbar and segno have no Gleam bindings, so this script only hands
symbols to them and writes what they return. Counting, the pass/fail rules
and the report are in dev/interop.gleam.

  interop.py read zxing|zbar CORPUS OUT
      Decode each symbol of CORPUS (written by `gleam run -m gen/interop_corpus`)
      and write the line again with the decoded text (UTF-8 hex, `-` when
      nothing was read) appended. zbar reads Standard QR only.

  interop.py segno OUT COUNT
      Encode COUNT random strings with segno (Standard QR, Micro QR, ECI and
      Structured Append parts) and write each with the text zxing-cpp reads
      from it. Symbols zxing-cpp cannot read are left out, so a later
      disagreement points at qrkit.

  interop.py fixtures OUT
      Write the fixed symbols test/decode_test.gleam reads: Standard QR with
      each of the 8 masks, Micro QR with each of the 4, and Byte data in
      Shift JIS, Latin-1 or UTF-8 without an ECI, part of it random from a
      fixed seed. The text is what zxing-cpp reads.

Each output starts with a `# name version` line. Install the packages from
scripts/interop-requirements.txt (pip --require-hashes) and libzbar0.
"""

import importlib.metadata
import pathlib
import random
import sys

import numpy as np

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
    image[quiet:quiet + height, quiet:quiet + width] = np.where(np.array(rows), 0, 255)
    return np.kron(image, np.ones((SCALE, SCALE), dtype=np.uint8))


def zxing_reader():
    import zxingcpp

    formats = {
        "qr": zxingcpp.BarcodeFormat.QRCode,
        "micro": zxingcpp.BarcodeFormat.MicroQRCode,
        "rmqr": zxingcpp.BarcodeFormat.RMQRCode,
    }

    def read(symbol, image):
        results = zxingcpp.read_barcodes(image, formats=formats[symbol])
        return results[0].text if results else None

    return f"# zxing-cpp {importlib.metadata.version('zxing-cpp')}", read


def zbar_reader():
    from ctypes import byref, c_uint

    from pyzbar import pyzbar, zbar_library

    library, _ = zbar_library.load()
    parts = [c_uint(), c_uint(), c_uint()]
    library.zbar_version(*(byref(p) for p in parts))
    version = ".".join(str(p.value) for p in parts)

    def read(_symbol, image):
        height, width = image.shape
        results = pyzbar.decode((image.tobytes(), width, height), symbols=[pyzbar.ZBarSymbol.QRCODE])
        return results[0].data.decode("utf-8", "replace") if results else None

    return f"# zbar {version}", read


def read(reader_name, corpus, out):
    header, reader = {"zxing": zxing_reader, "zbar": zbar_reader}[reader_name]()
    lines = [header]
    for line in pathlib.Path(corpus).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        symbol, _level, _eci, _text, rows_text = line.split("\t")
        if reader_name == "zbar" and symbol != "qr":
            continue
        rows = [[c == "1" for c in row] for row in rows_text.split("/")]
        got = reader(symbol, render(rows, QUIET[symbol]))
        lines.append(f"{line}\t{got.encode().hex() if got is not None else '-'}")
    pathlib.Path(out).write_text("\n".join(lines) + "\n")


def random_text(rng):
    length = rng.randint(1, 60)
    chars = []
    while len(chars) < length:
        pool = rng.choice(POOLS)
        chars.extend(rng.choice(pool) for _ in range(rng.randint(1, 10)))
    return "".join(chars[:length])


def segno_corpus(out, count):
    import segno

    _, zxing = zxing_reader()
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
            rows = [list(row) for row in qr.matrix_iter(border=0)]
            symbol = "micro" if qr.is_micro else "qr"
            expected = zxing(symbol, render(rows, QUIET[symbol]))
            if expected is None:
                skipped += 1
                continue
            label = f"sequence-{index}/{len(symbols)}" if variant == "sequence" else variant
            rows_text = "/".join("".join("1" if v else "0" for v in row) for row in rows)
            lines.append(f"{label}\t{expected.encode().hex()}\t{rows_text}")
    header = f"# segno {importlib.metadata.version('segno')}"
    pathlib.Path(out).write_text("\n".join([header, *lines]) + "\n")
    print(f"wrote {len(lines)} segno symbols to {out} ({skipped} skipped: zxing-cpp cannot read them either)")


def fixtures(out):
    import segno

    _, zxing = zxing_reader()
    cases = [(f"qr-mask-{m}", segno.make("qrkit mask test", error="m", mask=m, micro=False)) for m in range(8)]
    cases += [(f"micro-mask-{m}", segno.make("12345", micro=True, mask=m)) for m in range(4)]
    # The character-count fields get wider at versions 10 and 27
    # (ISO/IEC 18004 Table 3); each mode appears on both sides.
    for mode, text in (("numeric", "0123456789"), ("alphanumeric", "QRKIT 2026:/"), ("byte", "qrkit"), ("kanji", "日本語")):
        cases += [
            (f"qr-{mode}-version-{v}", segno.make(text, mode=mode, version=v, error="m", micro=False))
            for v in (9, 10, 26, 27)
        ]
    for name, text in (("kana", "ｱｲｳｴｵ"), ("kanji", "日本語のテキスト"), ("mixed", "abc漢字ｶﾅ123")):
        for encoding in ("shift_jis", "utf-8"):
            cases.append((f"byte-{encoding}-{name}", segno.make(text.encode(encoding), mode="byte", micro=False)))
    # Byte data without an ECI from a fixed seed, so readers must guess the
    # character set as zxing-cpp does.
    rng = random.Random(7)
    pools = {
        # ｡ and ﾟ are the first and last half-width katakana (0xA1, 0xDF);
        # 亜 and 滌 lead with 0x88 and 0x9F, 漾 and 熙 with 0xE0 and 0xEA.
        "shift_jis": "｡ｱｲｳｴｵｶｷｸｹｺﾟ日本語漢字東京亜滌漾熙あいうアイウ123abc ",
        # 0x80 and 0x9F are C1 controls; 0xA0, 0xBF, 0xC0, 0xD7, 0xF7 and
        # 0xFF border the ranges zxing-cpp counts as Latin-1 letters.
        "latin-1": "\x80\x9f\xa0¿ÀéèàüßÄÖ×÷ÿ£¥©®°±ÆØabc 12",
        "utf-8": "éü日本語ｱｲ😀abc ",
    }
    for index in range(120):
        encoding = rng.choice(sorted(pools))
        text = "".join(rng.choice(pools[encoding]) for _ in range(rng.randint(1, 12)))
        cases.append((f"random-{encoding}-{index}", segno.make(text.encode(encoding), mode="byte", micro=False)))
    # Strings on the edges of the guess: runs of one to three half-width
    # katakana or double-byte characters, and Latin-1 letters at 10% of
    # the bytes.
    edges = [
        ("shift_jis", "ｱ"), ("shift_jis", "ｱｲ"), ("shift_jis", "ｱｲｳ"), ("shift_jis", "ｱaｲ"),
        ("shift_jis", "ｱｲaｳ"), ("shift_jis", "日本"), ("shift_jis", "日本語"), ("shift_jis", "日a本"),
        ("shift_jis", "\u3000"), ("shift_jis", "\u3000ｱ"), ("shift_jis", "日本ｱｲ"),
        ("latin-1", "×"), ("latin-1", "÷a"), ("latin-1", "aaaaaaaaaé"), ("latin-1", "aaaaaaaaaaé"),
        ("latin-1", "\xa0"), ("latin-1", "\x80a"),
    ]
    for index, (encoding, text) in enumerate(edges):
        cases.append((f"edge-{encoding}-{index}", segno.make(text.encode(encoding), mode="byte", micro=False)))
    lines = [f"# segno {importlib.metadata.version('segno')}"]
    for label, qr in cases:
        rows = [list(row) for row in qr.matrix_iter(border=0)]
        symbol = "micro" if qr.is_micro else "qr"
        text = zxing(symbol, render(rows, QUIET[symbol]))
        if text is None:
            sys.exit(f"zxing-cpp cannot read fixture {label}; drop it or pick another input")
        rows_text = "/".join("".join("1" if v else "0" for v in row) for row in rows)
        lines.append(f"{label}\t{qr.mask}\t{text.encode().hex()}\t{rows_text}")
    pathlib.Path(out).write_text("\n".join(lines) + "\n")


def main():
    args = sys.argv[1:]
    if len(args) == 4 and args[0] == "read" and args[1] in ("zxing", "zbar"):
        read(args[1], args[2], args[3])
    elif len(args) == 2 and args[0] == "fixtures":
        fixtures(args[1])
    elif len(args) == 3 and args[0] == "segno":
        segno_corpus(args[1], int(args[2]))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
