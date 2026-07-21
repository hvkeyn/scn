#!/usr/bin/env python3
"""Rename PE import DLLs to Win7 shims without moving IAT slots.

LIEF (and import-table rebuilders) remove/repack import entries, which shifts
IAT slot indices while call sites still target the original RVAs. That crashes
on Win10 at ntdll+0x52e1a during flutter_windows.dll load.

Safe approach: keep every thunk/IAT slot exactly where the linker placed it and
only change the import descriptor DLL name string so the loader resolves symbols
through our shim DLLs instead of the system ones.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

# Rename entire import descriptors (all symbols stay in place).
# scn_ntdll / scn_kernel32 / scn_ws2 are FULL proxies: their .def files are
# generated from flutter_windows.dll's imports (gen_proxy_shim_def.py /
# gen_ws2_shim_def.py) so every symbol forwards to the real system DLL, except
# a handful of Win8+ symbols replaced by local Scn* shims. This makes the
# rename IAT-safe and lets the Windows loader resolve imports normally on both
# Win7 and Win10.
# Per-target renames: libwebrtc only needs GPU shims; kernel32/ws2 proxies are
# generated from flutter_windows.dll imports and cannot satisfy libwebrtc's table.
RENAME_BY_TARGET: dict[str, tuple[tuple[str, str], ...]] = {
    "flutter_windows.dll": (
        ("ntdll.dll", "scn_ntdll.dll"),
        ("kernel32.dll", "scn_kernel32.dll"),
        ("ws2_32.dll", "scn_ws2.dll"),
        ("dxgi.dll", "scn_dxgi.dll"),
    ),
    "libwebrtc.dll": (
        ("dxgi.dll", "scn_dxgi.dll"),
        ("d3d11.dll", "scn_d3d11.dll"),
    ),
}

SKIP_NAME_PREFIXES = ("scn_", "api-ms-win-")
PATCH_TARGETS = tuple(RENAME_BY_TARGET.keys())


def _should_patch(path: Path) -> bool:
    name = path.name.lower()
    if any(name.startswith(prefix) for prefix in SKIP_NAME_PREFIXES):
        return False
    return name.endswith((".dll", ".exe"))


def _iter_release_pes(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    seen: set[Path] = set()
    for path in root.rglob("*"):
        if path.is_file() and _should_patch(path):
            seen.add(path.resolve())
    return sorted(seen)


def _align(value: int, alignment: int) -> int:
    mask = alignment - 1
    return (value + mask) & ~mask


def _append_section(data: bytearray, pe, name: bytes, body: bytes) -> int:
    """Append a new PE section; return its RVA."""
    file_align = pe.OPTIONAL_HEADER.FileAlignment
    sect_align = pe.OPTIONAL_HEADER.SectionAlignment

    if len(body) % file_align:
        body = body.ljust(_align(len(body), file_align), b"\x00")

    new_rva = _align(pe.OPTIONAL_HEADER.SizeOfImage, sect_align)
    raw_off = _align(len(data), file_align)
    if raw_off > len(data):
        data.extend(b"\x00" * (raw_off - len(data)))
    data.extend(body)

    pe.OPTIONAL_HEADER.SizeOfImage = _align(new_rva + len(body), sect_align)

    coff_off = pe.DOS_HEADER.e_lfanew + 4
    num_sections = struct.unpack_from("<H", data, coff_off + 2)[0]
    struct.pack_into("<H", data, coff_off + 2, num_sections + 1)

    opt_size = struct.unpack_from("<H", data, coff_off + 16)[0]
    sections_off = coff_off + 20 + opt_size + num_sections * 40

    header = bytearray(40)
    header[0:8] = name[:8].ljust(8, b"\x00")
    struct.pack_into("<I", header, 8, len(body))
    struct.pack_into("<I", header, 12, new_rva)
    struct.pack_into("<I", header, 16, len(body))
    struct.pack_into("<I", header, 20, raw_off)
    struct.pack_into("<I", header, 36, 0x40000040)
    data[sections_off : sections_off + 40] = header

    opt_off = pe.DOS_HEADER.e_lfanew + 4 + 20
    struct.pack_into("<I", data, opt_off + 56, pe.OPTIONAL_HEADER.SizeOfImage)
    return new_rva


def _write_string(data: bytearray, pe, text: str) -> int:
    encoded = text.encode("ascii") + b"\x00"
    rva = _append_section(data, pe, b".w7str", encoded)
    return rva


def _patch_descriptor_name(
    data: bytearray,
    pe,
    desc_file_offset: int,
    name_rva: int,
    new_dll: str,
) -> None:
    old_bytes = pe.get_data(name_rva, 64)
    old_name = old_bytes.split(b"\x00", 1)[0].decode("ascii")
    new_encoded = new_dll.encode("ascii") + b"\x00"

    if len(new_encoded) <= len(old_bytes.split(b"\x00", 1)[0]) + 1:
        # In-place when the new name fits (e.g. WS2_32.dll -> scn_ws2.dll).
        name_off = pe.get_offset_from_rva(name_rva)
        data[name_off : name_off + len(new_encoded)] = new_encoded
        if len(new_encoded) < len(old_name.encode("ascii")) + 1:
            data[name_off + len(new_encoded)] = 0
        return

    new_name_rva = _write_string(data, pe, new_dll)
    struct.pack_into("<I", data, desc_file_offset + 12, new_name_rva)


def _rename_map_for(path: str) -> dict[str, str]:
    target = Path(path).name.lower()
    pairs = RENAME_BY_TARGET.get(target, ())
    return {old.lower(): new for old, new in pairs}


def _already_patched(path: str) -> bool:
    try:
        import pefile
    except ImportError:
        return False

    rename_map = _rename_map_for(path)
    if not rename_map:
        return False

    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )
    names = {entry.dll.decode().lower() for entry in pe.DIRECTORY_ENTRY_IMPORT}
    pe.close()
    required = {rename_map[old].lower() for old in names if old in rename_map}
    if not required:
        return False
    allowed_new = {new.lower() for new in rename_map.values()}
    unexpected = {n for n in names if n.startswith("scn_") and n not in allowed_new}
    if unexpected:
        return False
    old = set(rename_map.keys())
    return required.issubset(names) and not names.intersection(old)


def _validate_patched(path: str) -> None:
    import pefile

    pe = pefile.PE(path, fast_load=True)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )
    imports = {
        entry.dll.decode().lower(): [
            (imp.name.decode() if imp.name else f"#{imp.ordinal}")
            for imp in entry.imports
        ]
        for entry in pe.DIRECTORY_ENTRY_IMPORT
    }
    pe.close()

    for old, _ in _rename_map_for(path).items():
        if imports.get(old):
            raise SystemExit(
                f"{path}: {old} import descriptor still present after rename"
            )


def patch_file(path: str) -> None:
    try:
        import pefile
    except ImportError as exc:
        raise SystemExit("Win7 PE patch requires pefile: pip install pefile") from exc

    if Path(path).name.lower() not in PATCH_TARGETS:
        print(f"{path}: not a Win7 patch target (skipped)")
        return

    if _already_patched(path):
        print(f"{path}: Win7 import rename already applied (skipped)")
        return

    with open(path, "rb") as handle:
        data = bytearray(handle.read())

    pe = pefile.PE(data=data, fast_load=False)
    pe.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )

    rename_map = _rename_map_for(path)
    renamed: list[str] = []

    import_dir = pe.OPTIONAL_HEADER.DATA_DIRECTORY[
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]
    ]
    desc_rva = import_dir.VirtualAddress
    index = 0
    while True:
        desc_off = pe.get_offset_from_rva(desc_rva + index * 20)
        oft, ts, fc, name_rva, ft = struct.unpack_from("<IIIII", data, desc_off)
        if name_rva == 0 and ft == 0 and oft == 0:
            break

        dll_name = pe.get_data(name_rva, 64).split(b"\x00", 1)[0].decode("ascii")
        new_dll = rename_map.get(dll_name.lower())
        if new_dll:
            _patch_descriptor_name(data, pe, desc_off, name_rva, new_dll)
            renamed.append(f"{dll_name}->{new_dll}")

        index += 1

    if not renamed:
        print(f"{path}: no import descriptors renamed (skipped)")
        pe.close()
        return

    with open(path, "wb") as handle:
        handle.write(data)

    pe.close()
    _validate_patched(path)
    print(f"Patched {path}: {', '.join(renamed)}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rename Win7 import DLL descriptors (IAT-safe)."
    )
    parser.add_argument("paths", nargs="*", help="PE files to patch")
    parser.add_argument(
        "--dir",
        help="Patch flutter_windows.dll under this release directory",
    )
    args = parser.parse_args()

    targets: list[str] = list(args.paths)
    if args.dir:
        targets.extend(
            str(p)
            for p in _iter_release_pes(Path(args.dir))
            if p.name.lower() in PATCH_TARGETS
        )

    if not targets:
        print(
            "usage: patch_flutter_win7.py [--dir RELEASE] [flutter_windows.dll ...]",
            file=sys.stderr,
        )
        return 2

    for target in targets:
        patch_file(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
