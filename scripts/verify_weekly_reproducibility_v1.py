#!/usr/bin/env python3
from __future__ import annotations
import csv
import math
import sys
from pathlib import Path


def die(msg: str) -> None:
    raise SystemExit(msg)


def read_kv(path: Path) -> dict[str, str]:
    if not path.is_file():
        die(f"missing provenance file: {path}")
    with path.open(newline="") as f:
        return {r["key"]: r["value"] for r in csv.DictReader(f, delimiter="\t")}


def read_cmp(path: Path) -> dict[tuple[str, int], dict[str, str]]:
    if not path.is_file():
        die(f"missing comparison file: {path}")
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 4:
        die(f"expected four A/B horizon rows in {path}, found {len(rows)}")
    out = {}
    for r in rows:
        key = (r["type"], int(r["horizon"]))
        if key in out:
            die(f"duplicate comparison row {key} in {path}")
        out[key] = r
    return out


def numeq(a: str, b: str, tol: float = 1e-12) -> bool:
    x, y = float(a), float(b)
    return math.isfinite(x) and math.isfinite(y) and abs(x - y) <= tol


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] in {"-h", "--help"}:
        print("Usage: scripts/verify_weekly_reproducibility_v1.py RUN_A RUN_B")
        return 0 if len(argv) >= 2 and argv[1] in {"-h", "--help"} else 2

    a, b = Path(argv[1]).resolve(), Path(argv[2]).resolve()
    for p in (a, b):
        if not p.is_dir():
            die(f"not a transaction directory: {p}")
        if not (p / "COMPLETED").exists():
            die(f"transaction is not sealed COMPLETE: {p}")

    ta, tb = read_kv(a / "source_transaction.tsv"), read_kv(b / "source_transaction.tsv")
    stable_keys = [
        "season",
        "origin_weekF",
        "release_id",
        "source_mode",
        "raw_source_sha256",
        "supplied_typed_panel_sha256",
        "effective_panel_sha256",
    ]
    mismatches: list[str] = []
    for k in stable_keys:
        if ta.get(k) != tb.get(k):
            mismatches.append(f"{k}: {ta.get(k)!r} != {tb.get(k)!r}")
    if ta.get("source_mode") != "orvt" or tb.get("source_mode") != "orvt":
        mismatches.append("both transactions must have source_mode=orvt")

    ca, cb = read_cmp(a / "v2_v3_comparison.csv"), read_cmp(b / "v2_v3_comparison.csv")
    if set(ca) != set(cb):
        mismatches.append(f"comparison row keys differ: {sorted(ca)} != {sorted(cb)}")
    else:
        for key in sorted(ca):
            ra, rb = ca[key], cb[key]
            for col in ("v2_forecast_pct", "v3_forecast_pct", "delta_v3_minus_v2_pp"):
                if not numeq(ra[col], rb[col]):
                    mismatches.append(f"{key} {col}: {ra[col]} != {rb[col]}")
            for col in ("v3_route", "release_id", "effective_panel_sha256"):
                if ra[col] != rb[col]:
                    mismatches.append(f"{key} {col}: {ra[col]!r} != {rb[col]!r}")

    if mismatches:
        print("REPRODUCIBILITY_CHECK=FAIL")
        for x in mismatches:
            print(" -", x)
        return 1

    print("REPRODUCIBILITY_CHECK=PASS")
    print(f"SEASON={ta['season']}")
    print(f"ORIGIN_WEEKF={ta['origin_weekF']}")
    print(f"RAW_SOURCE_SHA256={ta['raw_source_sha256']}")
    print(f"RELEASE_ID={ta['release_id']}")
    print(f"EFFECTIVE_PANEL_SHA256={ta['effective_panel_sha256']}")
    for key in sorted(ca):
        r = ca[key]
        print(
            f"{key[0]}+{key[1]} v2={r['v2_forecast_pct']}% "
            f"v3={r['v3_forecast_pct']}% route={r['v3_route']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
