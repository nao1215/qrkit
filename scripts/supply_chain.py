#!/usr/bin/env python3
"""Supply-chain helpers for a Gleam escript (sqlode, oaspec).

The escript is what users download from the GitHub Release, so the SBOM
and the license bundle are derived from the OTP applications packed in
the escript itself (its embedded zip holds one `<app>.app` per bundled
application), not from gleam.toml. Versions and checksums come from
manifest.toml.

Without --escript (library repositories), the dependency set is the
runtime closure of gleam.toml's [dependencies] as locked in manifest.toml;
dev-dependencies are left out because they never reach users.

Subcommands:
  contents <escript> [--strict]            list bundled apps and test modules
  sbom --manifest M [--escript E] [--out F]
                                           CycloneDX 1.5 JSON (pkg:hex purls)
  licenses --manifest M [--escript E] [--bundle DIR]
                                           judge each dependency's license
                                           (fails on GPL/LGPL/AGPL/unknown);
                                           with --bundle, write the license
                                           texts from the Hex tarballs (or the
                                           SPDX text when a tarball has none)

Exit status: 0 ok, 1 policy failure (denied or unknown license, test
modules in the escript with --strict), 2 usage or input error.

Only the Python standard library is used. `licenses` talks to hex.pm and
repo.hex.pm; the other subcommands work offline.
"""

import argparse
import io
import json
import re
import sys
import tarfile
import tomllib
import urllib.request
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

DENY = re.compile(r"\b(A?GPL|LGPL)\b", re.IGNORECASE)
LICENSE_FILE = re.compile(r"^(LICEN[CS]E|COPYING|NOTICE)(\.[A-Za-z]+)?$", re.IGNORECASE)


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def escript_zip(path):
    data = Path(path).read_bytes()
    start = data.find(b"PK\x03\x04")
    if start < 0:
        die(f"{path}: no zip archive inside; is this an escript built by gleescript?")
    return zipfile.ZipFile(io.BytesIO(data[start:]))


def bundled(path):
    names = escript_zip(path).namelist()
    apps = sorted(n[: -len(".app")] for n in names if n.endswith(".app"))
    tests = sorted(n for n in names if re.search(r"_test\.beam$|^test_helpers\.beam$", n))
    return apps, tests


def manifest_packages(path):
    with open(path, "rb") as f:
        doc = tomllib.load(f)
    return {p["name"]: p for p in doc.get("packages", [])}


def root_name(manifest_path):
    gleam_toml = Path(manifest_path).with_name("gleam.toml")
    with open(gleam_toml, "rb") as f:
        doc = tomllib.load(f)
    return doc["name"], doc.get("version", "0.0.0"), doc.get("licences", [])


def runtime_closure(manifest):
    pkgs = manifest_packages(manifest)
    with open(Path(manifest).with_name("gleam.toml"), "rb") as f:
        direct = list((tomllib.load(f).get("dependencies") or {}).keys())
    seen, stack = set(), direct
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        if n not in pkgs:
            die(f"{n} is a dependency in gleam.toml but not in manifest.toml; run gleam deps download")
        seen.add(n)
        stack.extend(pkgs[n].get("requirements", []))
    return sorted(seen)


def deps_of(escript, manifest):
    pkgs = manifest_packages(manifest)
    root, _, _ = root_name(manifest)
    apps = bundled(escript)[0] if escript else runtime_closure(manifest)
    out, unknown = [], []
    for app in apps:
        if app == root:
            continue
        p = pkgs.get(app)
        if p is None:
            unknown.append(app)
            continue
        out.append(p)
    if unknown:
        die("apps in the escript that manifest.toml does not list: " + ", ".join(unknown))
    return out


def hex_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "gleam-supply-chain/1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def cmd_contents(a):
    apps, tests = bundled(a.escript)
    print("apps:")
    for app in apps:
        print(f"  {app}")
    print(f"test modules: {len(tests)}")
    for t in tests:
        print(f"  {t}")
    if a.strict and tests:
        print("error: the escript ships test modules", file=sys.stderr)
        return 1
    return 0


def cmd_sbom(a):
    root, version, licences = root_name(a.manifest)
    comps = []
    for p in deps_of(a.escript, a.manifest):
        c = {
            "type": "library",
            "bom-ref": f"pkg:hex/{p['name']}@{p['version']}",
            "name": p["name"],
            "version": p["version"],
            "purl": f"pkg:hex/{p['name']}@{p['version']}",
        }
        if p.get("outer_checksum"):
            c["hashes"] = [{"alg": "SHA-256", "content": p["outer_checksum"].lower()}]
        comps.append(c)
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "component": {
                "type": "application",
                "bom-ref": f"pkg:hex/{root}@{version}",
                "name": root,
                "version": version,
                "purl": f"pkg:hex/{root}@{version}",
                "licenses": [{"license": {"id": l}} for l in licences],
            },
        },
        "components": comps,
    }
    text = json.dumps(bom, indent=2) + "\n"
    if a.out:
        Path(a.out).write_text(text)
    else:
        sys.stdout.write(text)
    return 0


def cmd_licenses(a):
    status = 0
    bundle = Path(a.bundle) if a.bundle else None
    for p in deps_of(a.escript, a.manifest):
        name, ver = p["name"], p["version"]
        if p.get("source") != "hex":
            print(f"{name} {ver}: source {p.get('source')} is not hex; judge by hand", file=sys.stderr)
            status = 1
            continue
        meta = hex_json(f"https://hex.pm/api/packages/{name}")
        lic = (meta.get("meta") or {}).get("licenses") or []
        verdict = "ok"
        if not lic:
            verdict, status = "UNKNOWN", 1
        elif any(DENY.search(l) for l in lic):
            verdict, status = "DENIED", 1
        print(f"{name} {ver}: {', '.join(lic) or '-'} [{verdict}]")
        if bundle is not None and not save_texts(name, ver, bundle):
            if not save_spdx(name, ver, lic, bundle):
                status = 1
    return status


def save_texts(name, ver, bundle):
    url = f"https://repo.hex.pm/tarballs/{name}-{ver}.tar"
    req = urllib.request.Request(url, headers={"User-Agent": "gleam-supply-chain/1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        outer = tarfile.open(fileobj=io.BytesIO(r.read()))
    inner = tarfile.open(fileobj=outer.extractfile("contents.tar.gz"), mode="r:gz")
    dest = bundle / f"{name}-{ver}"
    found = False
    for m in inner.getmembers():
        if m.isfile() and "/" not in m.name and LICENSE_FILE.match(m.name):
            dest.mkdir(parents=True, exist_ok=True)
            (dest / m.name).write_bytes(inner.extractfile(m).read())
            found = True
    return found


def save_spdx(name, ver, lic, bundle):
    # Some Hex tarballs carry no license file. Fall back to the standard
    # SPDX text of each declared license so the bundle is never silently
    # missing an entry; say so on stderr so the release notes can mention it.
    dest = bundle / f"{name}-{ver}"
    ok = bool(lic)
    for l in lic:
        spdx = l.strip().replace(" ", "-")
        url = f"https://raw.githubusercontent.com/spdx/license-list-data/main/text/{spdx}.txt"
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                text = r.read()
        except Exception:
            print(f"{name} {ver}: no license file and no SPDX text for {l!r}", file=sys.stderr)
            ok = False
            continue
        dest.mkdir(parents=True, exist_ok=True)
        (dest / f"LICENSE.spdx-{spdx}.txt").write_bytes(text)
        print(f"{name} {ver}: no license file in the Hex tarball; bundled the SPDX text of {spdx}", file=sys.stderr)
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("contents")
    c.add_argument("escript")
    c.add_argument("--strict", action="store_true", help="fail when test modules are bundled")
    s = sub.add_parser("sbom")
    s.add_argument("--manifest", required=True)
    s.add_argument("--escript")
    s.add_argument("--out")
    l = sub.add_parser("licenses")
    l.add_argument("--manifest", required=True)
    l.add_argument("--escript")
    l.add_argument("--bundle")
    a = ap.parse_args()
    return {"contents": cmd_contents, "sbom": cmd_sbom, "licenses": cmd_licenses}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
