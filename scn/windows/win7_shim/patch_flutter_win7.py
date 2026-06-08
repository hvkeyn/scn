#!/usr/bin/env python3
"""Redirect flutter_windows.dll GetHostNameW import from WS2_32 to scn_ws2.dll."""

from __future__ import annotations

import sys


def patch(path: str) -> None:
    try:
        import lief
    except ImportError as exc:
        raise SystemExit(
            "Win7 build requires LIEF: pip install lief"
        ) from exc

    pe = lief.PE.parse(path)
    for imp in pe.imports:
        if imp.name and imp.name.lower() == "ws2_32.dll":
            imp.remove_entry("GetHostNameW")
            break
    else:
        raise SystemExit(f"{path}: WS2_32.dll import not found")

    shim = pe.add_import("scn_ws2.dll")
    shim.add_entry("GetHostNameW")

    config = lief.PE.Builder.config_t()
    config.imports = True
    builder = lief.PE.Builder(pe, config)
    builder.build()
    builder.write(path)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <flutter_windows.dll>", file=sys.stderr)
        return 2
    patch(sys.argv[1])
    print(f"Patched {sys.argv[1]} for Win7 (GetHostNameW -> scn_ws2.dll)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
