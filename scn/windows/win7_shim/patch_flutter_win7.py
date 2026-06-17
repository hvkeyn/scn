#!/usr/bin/env python3
"""Patch PE imports for Windows 7 compatibility."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PATCHES: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    ("WS2_32.dll", "scn_ws2.dll", ("GetHostNameW",)),
    (
        "ntdll.dll",
        "scn_ntdll.dll",
        (
            "RtlAddGrowableFunctionTable",
            "RtlDeleteGrowableFunctionTable",
            "RtlGrowFunctionTable",
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
    (
        "KERNEL32.dll",
        "scn_ntdll.dll",
        ("VerSetConditionMask",),
    ),
    (
        "dxgi.dll",
        "scn_dxgi.dll",
        (
            "CreateDXGIFactory1",
            "CreateDXGIFactory",
        ),
    ),
    (
        "d3d11.dll",
        "scn_d3d11.dll",
        ("D3D11CreateDevice",),
    ),
)


SKIP_NAME_PREFIXES = ("scn_", "api-ms-win-")


def _should_patch(path: Path) -> bool:
    name = path.name.lower()
    if any(name.startswith(prefix) for prefix in SKIP_NAME_PREFIXES):
        return False
    if name.endswith((".dll", ".exe")):
        return True
    # Flutter AOT on Windows is a PE file named app.so.
    return name == "app.so"


def _iter_release_pes(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    seen: set[Path] = set()
    for path in root.rglob("*"):
        if not path.is_file() or not _should_patch(path):
            continue
        seen.add(path.resolve())
    return sorted(seen)


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
    if pe is None:
        print(f"{path}: not a PE file (skipped)")
        return

    summary: list[str] = []

    for source_dll, target_dll, entries in PATCHES:
        moved = _redirect_entries(pe, source_dll, target_dll, entries)
        for name in moved:
            summary.append(f"{target_dll}!{name}")

    if not summary:
        print(f"{path}: no Win7 imports redirected (skipped)")
        return

    config = lief.PE.Builder.config_t()
    config.imports = True
    builder = lief.PE.Builder(pe, config)
    builder.build()
    builder.write(path)
    print(f"Patched {path}: {', '.join(summary)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Redirect Win8+ imports to Win7 shims.")
    parser.add_argument("paths", nargs="*", help="PE files to patch")
    parser.add_argument(
        "--dir",
        help="Patch every .dll/.exe and data/app.so under this release directory",
    )
    args = parser.parse_args()

    targets: list[str] = list(args.paths)
    if args.dir:
        targets.extend(str(p) for p in _iter_release_pes(Path(args.dir)))

    if not targets:
        print("usage: patch_flutter_win7.py [--dir RELEASE] [pe-file ...]", file=sys.stderr)
        return 2

    for path in targets:
        patch_file(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
