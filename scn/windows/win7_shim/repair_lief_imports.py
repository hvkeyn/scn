#!/usr/bin/env python3
"""Repair LIEF-corrupted import thunks after Win7 redirect patch."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# Symbols moved off each DLL by patch_flutter_win7.py (must stay in sync).
MOVED: dict[str, frozenset[str]] = {
    "ws2_32.dll": frozenset({"GetHostNameW"}),
    "ntdll.dll": frozenset(
        {
            "RtlAddGrowableFunctionTable",
            "RtlDeleteGrowableFunctionTable",
            "RtlGrowFunctionTable",
            "VerSetConditionMask",
        }
    ),
}

# LIEF corrupts the INT of every DLL it removes entries from. Repair the INT
# (lookup table only; the loader fills the IAT from it) of the redirected DLLs.
REPAIR_DLLS = ("ntdll.dll", "ws2_32.dll")


def _thunk_map(pe, dll_name: str) -> dict[str, int]:
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() != dll_name.lower():
            continue
        lookup_rva = entry.struct.OriginalFirstThunk or entry.struct.FirstThunk
        symbols: dict[str, int] = {}
        index = 0
        while True:
            value = struct.unpack("<Q", pe.get_data(lookup_rva + index * 8, 8))[0]
            if value == 0:
                break
            if value & (1 << 63):
                name = f"#{value & 0xFFFF}"
            else:
                raw = pe.get_data(value + 2, 256)
                name = raw.split(b"\x00", 1)[0].decode("ascii")
            if name not in symbols:
                symbols[name] = value
            index += 1
        return symbols
    return {}


def _import_names(pe, dll_name: str) -> list[str]:
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() != dll_name.lower():
            continue
        lookup_rva = entry.struct.OriginalFirstThunk or entry.struct.FirstThunk
        names: list[str] = []
        index = 0
        while True:
            value = struct.unpack("<Q", pe.get_data(lookup_rva + index * 8, 8))[0]
            if value == 0:
                break
            if value & (1 << 63):
                names.append(f"#{value & 0xFFFF}")
            else:
                raw = pe.get_data(value + 2, 256)
                names.append(raw.split(b"\x00", 1)[0].decode("ascii"))
            index += 1
        return names
    return []


def _expected_remaining(orig_names: list[str], dll_name: str) -> list[str]:
    moved = MOVED.get(dll_name.lower(), frozenset())
    return [name for name in orig_names if name not in moved]


def _import_entry(pe, dll_name: str):
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() == dll_name.lower():
            return entry
    return None


def _write_thunks_raw(data: bytearray, pe, dll_name: str, thunk_values: list[int]) -> None:
    entry = _import_entry(pe, dll_name)
    if entry is None:
        raise SystemExit(f"{dll_name} import descriptor not found")

    lookup_rva = entry.struct.OriginalFirstThunk or entry.struct.FirstThunk
    iat_rva = entry.struct.FirstThunk
    # When OFT is present the loader resolves via INT and writes into IAT.
    # LIEF often leaves stale values in IAT; do not copy hint RVAs there.
    shared_thunks = (
        entry.struct.OriginalFirstThunk == 0
        or entry.struct.OriginalFirstThunk == iat_rva
    )

    def put_qword(rva: int, value: int) -> None:
        offset = pe.get_offset_from_rva(rva)
        struct.pack_into("<Q", data, offset, value)

    for index, value in enumerate(thunk_values):
        put_qword(lookup_rva + index * 8, value)
        if shared_thunks:
            put_qword(iat_rva + index * 8, value)
    put_qword(lookup_rva + len(thunk_values) * 8, 0)
    if shared_thunks:
        put_qword(iat_rva + len(thunk_values) * 8, 0)


def repair_file(path: str, original: bytes | None = None) -> list[str]:
    import pefile

    if original is None:
        with open(path, "rb") as handle:
            original = handle.read()

    orig_pe = pefile.PE(data=original, fast_load=True)
    orig_pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )

    with open(path, "rb") as handle:
        data = bytearray(handle.read())

    patch_pe = pefile.PE(data=bytes(data), fast_load=True)
    patch_pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )

    fixed: list[str] = []
    for dll_name in REPAIR_DLLS:
        orig_names = _import_names(orig_pe, dll_name)
        if not orig_names:
            continue

        orig_map = _thunk_map(orig_pe, dll_name)
        expected = _expected_remaining(orig_names, dll_name)
        current = _import_names(patch_pe, dll_name)
        if current == expected:
            continue

        missing = [symbol for symbol in expected if symbol not in orig_map]
        if missing:
            raise SystemExit(f"{path}: missing original imports for {dll_name}: {missing}")

        _write_thunks_raw(data, patch_pe, dll_name, [orig_map[symbol] for symbol in expected])
        fixed.append(f"{dll_name}({len(expected)} imports)")

    if fixed:
        with open(path, "wb") as handle:
            handle.write(data)
    return fixed


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair LIEF import table corruption.")
    parser.add_argument("path", help="Patched PE file to repair in place")
    parser.add_argument(
        "--original",
        help="Unpatched PE file (defaults to embedded backup if present)",
    )
    args = parser.parse_args()

    original_bytes: bytes | None = None
    if args.original:
        original_bytes = Path(args.original).read_bytes()
    else:
        backup = Path(args.path + ".orig")
        if backup.is_file():
            original_bytes = backup.read_bytes()

    if original_bytes is None:
        print("repair: original PE not provided", file=sys.stderr)
        return 2

    fixed = repair_file(args.path, original_bytes)
    if fixed:
        print(f"Repaired {args.path}: {', '.join(fixed)}")
    else:
        print(f"{args.path}: imports already valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
