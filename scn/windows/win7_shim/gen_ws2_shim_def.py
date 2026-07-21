#!/usr/bin/env python3
"""Generate scn_ws2 .def with ordinal + name forwards for flutter WS2 imports."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


def _ws2_imports(pe_path: str) -> tuple[list[int], list[str]]:
    import pefile

    pe = pefile.PE(pe_path, fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )
    ordinals: list[int] = []
    names: list[str] = []
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() != "ws2_32.dll":
            continue
        lookup_rva = entry.struct.OriginalFirstThunk or entry.struct.FirstThunk
        offset = 0
        while True:
            value = struct.unpack("<Q", pe.get_data(lookup_rva + offset, 8))[0]
            if value == 0:
                break
            if value & (1 << 63):
                ordinals.append(value & 0xFFFF)
            else:
                raw = pe.get_data(value + 2, 256)
                names.append(raw.split(b"\x00", 1)[0].decode("ascii"))
            offset += 8
    return ordinals, names


def _ws2_ordinal_names(ws2_path: str | None = None) -> dict[int, str]:
    import pefile

    path = ws2_path or r"C:\Windows\System32\ws2_32.dll"
    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"]]
    )
    by_ordinal: dict[int, str] = {}
    for sym in pe.DIRECTORY_ENTRY_EXPORT.symbols:
        if sym.name:
            by_ordinal[sym.ordinal] = sym.name.decode("ascii")
    pe.close()
    return by_ordinal


def generate_def(flutter_dll: str, ws2_dll: str | None = None) -> str:
    ordinals, names = _ws2_imports(flutter_dll)
    ordinal_names = _ws2_ordinal_names(ws2_dll)
    lines = [
        "LIBRARY scn_ws2",
        "EXPORTS",
        "    GetHostNameW=ScnGetHostNameW",
    ]
    for name in sorted(set(names)):
        if name == "GetHostNameW":
            continue
        lines.append(f"    {name}=WS2_32.{name}")
    for ordinal in sorted(set(ordinals)):
        export_name = ordinal_names.get(ordinal)
        if not export_name:
            raise SystemExit(f"WS2_32 ordinal {ordinal} has no named export")
        lines.append(f"    {export_name}=WS2_32.{export_name} @{ordinal}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate ws2_hostname_shim.def")
    parser.add_argument(
        "flutter_dll",
        help="Path to flutter_windows.dll (unpatched ephemeral copy)",
    )
    parser.add_argument(
        "--ws2-dll",
        default=r"C:\Windows\System32\ws2_32.dll",
        help="Path to WS2_32.dll for ordinal name lookup",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=str(
            Path(__file__).resolve().parent / "ws2_hostname_shim.def"
        ),
        help="Output .def path",
    )
    args = parser.parse_args()

    content = generate_def(args.flutter_dll, args.ws2_dll)
    Path(args.output).write_text(content, encoding="ascii")
    print(f"Wrote {args.output} ({content.count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
