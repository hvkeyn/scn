#!/usr/bin/env python3
"""Patch flutter_windows.dll imports for Windows 7 compatibility."""

from __future__ import annotations

import sys

WS2_SHIM_DLL = "scn_ws2.dll"
WS2_REDIRECTS = ("GetHostNameW",)

NTDLL_SHIM_DLL = "scn_ntdll.dll"
NTDLL_REDIRECTS = (
    "RtlAddGrowableFunctionTable",
    "RtlDeleteGrowableFunctionTable",
    "VerSetConditionMask",
)


def _find_import(pe, dll_name: str):
    for imp in pe.imports:
        if imp.name and imp.name.lower() == dll_name.lower():
            return imp
    return None


def _redirect_entries(pe, source_dll: str, target_dll: str, entries: tuple[str, ...]) -> list[str]:
    source = _find_import(pe, source_dll)
    if source is None:
        return []

    moved: list[str] = []
    for name in entries:
        if source.remove_entry(name):
            moved.append(name)

    if not moved:
        return []

    target = _find_import(pe, target_dll)
    if target is None:
        target = pe.add_import(target_dll)
    for name in moved:
        target.add_entry(name)
    return moved


def patch(path: str) -> None:
    try:
        import lief
    except ImportError as exc:
        raise SystemExit("Win7 build requires LIEF: pip install lief") from exc

    pe = lief.PE.parse(path)

    ws2_moved = _redirect_entries(pe, "WS2_32.dll", WS2_SHIM_DLL, WS2_REDIRECTS)
    if not ws2_moved:
        raise SystemExit(f"{path}: WS2_32.dll GetHostNameW import not found")

    ntdll_moved = _redirect_entries(pe, "ntdll.dll", NTDLL_SHIM_DLL, NTDLL_REDIRECTS)
    if not ntdll_moved:
        raise SystemExit(f"{path}: ntdll Win7 imports not found")

    config = lief.PE.Builder.config_t()
    config.imports = True
    builder = lief.PE.Builder(pe, config)
    builder.build()
    builder.write(path)

    print(
        f"Patched {path} for Win7: "
        f"{', '.join(f'{WS2_SHIM_DLL}!{n}' for n in ws2_moved)}, "
        f"{', '.join(f'{NTDLL_SHIM_DLL}!{n}' for n in ntdll_moved)}"
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <flutter_windows.dll>", file=sys.stderr)
        return 2
    patch(sys.argv[1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
