#!/usr/bin/env python3
"""Generate a proxy-style .def for a Win7 shim DLL.

The shim must re-export EVERY symbol that the target PE (flutter_windows.dll)
imports from a given system DLL, otherwise the loader fails to resolve imports.
For each imported symbol the shim forwards to the real system DLL, except for
an explicit set of overridden names which instead resolve to local (Scn*)
implementations.

This is what lets patch_flutter_win7.py safely RENAME the import descriptor
(ntdll.dll -> scn_ntdll.dll, kernel32.dll -> scn_kernel32.dll): the shim is a
drop-in proxy for all imports, with only a handful of Win8+ symbols replaced
by Win7-compatible fallbacks.

Usage:
    gen_proxy_shim_def.py <target_pe> <system_dll> <shim_libname> \
        [--override NAME=LOCALSYMBOL ...] [-o out.def]

Example:
    gen_proxy_shim_def.py flutter_windows.dll ntdll.dll scn_ntdll \
        --override RtlAddGrowableFunctionTable=ScnRtlAddGrowableFunctionTable \
        --override RtlDeleteGrowableFunctionTable=ScnRtlDeleteGrowableFunctionTable \
        --override RtlGrowFunctionTable=ScnRtlGrowFunctionTable \
        --override VerSetConditionMask=ScnVerSetConditionMask \
        -o ntdll_shim.def
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _system_imports(pe_path: str, system_dll: str) -> tuple[list[int], list[str]]:
    """Return (ordinals, names) imported from system_dll by pe_path."""
    import pefile

    pe = pefile.PE(pe_path, fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )
    target = system_dll.lower()
    ordinals: list[int] = []
    names: list[str] = []
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() != target:
            continue
        for imp in entry.imports:
            if imp.name:
                names.append(imp.name.decode("ascii"))
            elif imp.ordinal:
                ordinals.append(imp.ordinal)
    pe.close()
    return ordinals, names


def generate_def(
    pe_path: str,
    system_dll: str,
    shim_libname: str,
    overrides: dict[str, str],
    extras: list[tuple[str, str | None]],
) -> str:
    ordinals, names = _system_imports(pe_path, system_dll)

    # The system DLL base name used in forwarders (e.g. "ntdll", "KERNEL32").
    # .def forwarders use the DLL name without path, case-insensitive on load.
    forward_base = Path(system_dll).stem

    lines = [f"LIBRARY {shim_libname}", "EXPORTS"]
    seen: set[str] = set()

    # Named imports first (deterministic order).
    for name in sorted(set(names)):
        if name in seen:
            continue
        seen.add(name)
        local = overrides.get(name)
        if local:
            lines.append(f"    {name}={local}")
        else:
            lines.append(f"    {name}={forward_base}.{name}")

    # Ordinal imports (rare for ntdll/kernel32, but handle anyway).
    for ordinal in sorted(set(ordinals)):
        lines.append(f"    #{ordinal}={forward_base}.#{ordinal} @{ordinal}")

    # Extra local exports not part of the mirrored imports (e.g. internal
    # Scn* helpers resolved via GetProcAddress redirect).
    for export_name, local in extras:
        if export_name in seen:
            continue
        seen.add(export_name)
        if local:
            lines.append(f"    {export_name}={local}")
        else:
            lines.append(f"    {export_name}")

    return "\n".join(lines) + "\n"


def _parse_override(spec: str) -> tuple[str, str]:
    if "=" not in spec:
        raise SystemExit(f"invalid --override {spec!r}; expected NAME=LOCALSYMBOL")
    name, local = spec.split("=", 1)
    return name.strip(), local.strip()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a proxy .def for a Win7 shim DLL."
    )
    parser.add_argument("target_pe", help="PE file whose imports to mirror (flutter_windows.dll)")
    parser.add_argument("system_dll", help="System DLL being proxied (e.g. ntdll.dll)")
    parser.add_argument("shim_libname", help="LIBRARY name for the generated .def (e.g. scn_ntdll)")
    parser.add_argument(
        "--override",
        action="append",
        default=[],
        help="NAME=LOCALSYMBOL: re-export NAME as LOCALSYMBOL instead of forwarding",
    )
    parser.add_argument(
        "--extra",
        action="append",
        default=[],
        help="NAME[=LOCALSYMBOL]: add an extra local export (no forwarder). "
        "Useful for internal Scn* helpers resolved via GetProcAddress.",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Output .def path (defaults to <shim_libname>.def next to this script)",
    )
    args = parser.parse_args()

    overrides = dict(_parse_override(spec) for spec in args.override)
    extras: list[tuple[str, str | None]] = []
    for spec in args.extra:
        if "=" in spec:
            n, local = spec.split("=", 1)
            extras.append((n.strip(), local.strip()))
        else:
            extras.append((spec.strip(), None))

    content = generate_def(
        args.target_pe, args.system_dll, args.shim_libname, overrides, extras
    )

    if args.output:
        out_path = Path(args.output)
    else:
        out_path = Path(__file__).resolve().parent / f"{args.shim_libname}.def"
    out_path.write_text(content, encoding="ascii")
    print(f"Wrote {out_path} ({content.count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
