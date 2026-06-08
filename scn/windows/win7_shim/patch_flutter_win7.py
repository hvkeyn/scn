#!/usr/bin/env python3
"""Patch PE imports for Windows 7 compatibility."""

from __future__ import annotations

import sys

PATCHES: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("WS2_32.dll", "scn_ws2.dll", ("GetHostNameW",)),
    (
        "ntdll.dll",
        "scn_ntdll.dll",
        (
            "RtlAddGrowableFunctionTable",
            "RtlDeleteGrowableFunctionTable",
            "VerSetConditionMask",
        ),
    ),
    (
        "KERNEL32.dll",
        "scn_kernel32.dll",
        (
            "CompareStringEx",
            "LCMapStringEx",
            "GetFileInformationByHandleEx",
        ),
    ),
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


def patch_file(path: str) -> None:
    try:
        import lief
    except ImportError as exc:
        raise SystemExit("Win7 build requires LIEF: pip install lief") from exc

    pe = lief.PE.parse(path)
    summary: list[str] = []

    for source_dll, target_dll, entries in PATCHES:
        moved = _redirect_entries(pe, source_dll, target_dll, entries)
        for name in moved:
            summary.append(f"{target_dll}!{name}")

    if not summary:
        raise SystemExit(f"{path}: no Win7 imports redirected")

    config = lief.PE.Builder.config_t()
    config.imports = True
    builder = lief.PE.Builder(pe, config)
    builder.build()
    builder.write(path)
    print(f"Patched {path}: {', '.join(summary)}")


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <pe-file> [<pe-file> ...]", file=sys.stderr)
        return 2
    for path in sys.argv[1:]:
        patch_file(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
