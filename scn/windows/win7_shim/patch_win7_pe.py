#!/usr/bin/env python3
"""Rebuild PE import tables for Windows 7 shim redirection (no LIEF)."""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass, field
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
    ("KERNEL32.dll", "scn_ntdll.dll", ("VerSetConditionMask",)),
    (
        "dxgi.dll",
        "scn_dxgi.dll",
        (
            "CreateDXGIFactory1",
            "CreateDXGIFactory",
        ),
    ),
    ("d3d11.dll", "scn_d3d11.dll", ("D3D11CreateDevice",)),
)

SKIP_NAME_PREFIXES = ("scn_", "api-ms-win-")


@dataclass
class ImportSymbol:
    name: str | None = None
    ordinal: int | None = None


@dataclass
class ImportDll:
    dll: str
    symbols: list[ImportSymbol] = field(default_factory=list)


def _align(value: int, alignment: int) -> int:
    if alignment <= 0:
        return value
    mask = alignment - 1
    return (value + mask) & ~mask


def _should_patch(path: Path) -> bool:
    name = path.name.lower()
    if any(name.startswith(prefix) for prefix in SKIP_NAME_PREFIXES):
        return False
    if name.endswith((".dll", ".exe")):
        return True
    return name == "app.so"


def _iter_release_pes(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    seen: set[Path] = set()
    for path in root.rglob("*"):
        if path.is_file() and _should_patch(path):
            seen.add(path.resolve())
    return sorted(seen)


def _read_imports(pe) -> list[ImportDll]:
    imports: list[ImportDll] = []
    if not hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
        return imports

    for desc in pe.DIRECTORY_ENTRY_IMPORT:
        dll = desc.dll.decode()
        symbols: list[ImportSymbol] = []
        lookup_rva = desc.struct.OriginalFirstThunk or desc.struct.FirstThunk
        offset = 0
        while True:
            value = struct.unpack("<Q", pe.get_data(lookup_rva + offset, 8))[0]
            if value == 0:
                break
            if value & (1 << 63):
                symbols.append(ImportSymbol(ordinal=value & 0xFFFF))
            else:
                raw = pe.get_data(value + 2, 256)
                name = raw.split(b"\x00", 1)[0].decode("ascii")
                symbols.append(ImportSymbol(name=name))
            offset += 8
        imports.append(ImportDll(dll=dll, symbols=symbols))
    return imports


def _apply_redirects(imports: list[ImportDll]) -> list[tuple[str, str, str]]:
    moved: list[tuple[str, str, str]] = []
    by_dll = {item.dll.lower(): item for item in imports}

    for source_dll, target_dll, entries in PATCHES:
        source = by_dll.get(source_dll.lower())
        if source is None:
            continue
        target = by_dll.get(target_dll.lower())
        if target is None:
            target = ImportDll(dll=target_dll, symbols=[])
            imports.append(target)
            by_dll[target_dll.lower()] = target

        for symbol in entries:
            idx = next((i for i, s in enumerate(source.symbols) if s.name == symbol), None)
            if idx is None:
                continue
            sym = source.symbols.pop(idx)
            target.symbols.append(sym)
            moved.append((source_dll, target_dll, symbol))
    return moved


def _validate_imports(imports: list[ImportDll]) -> None:
    for item in imports:
        if not item.symbols:
            continue
        names = [s.name for s in item.symbols if s.name]
        if len(names) != len(set(names)):
            raise ValueError(f"duplicate imports in {item.dll}: {names}")


def _non_empty_imports(imports: list[ImportDll]) -> list[ImportDll]:
    return [item for item in imports if item.symbols]


def _build_import_section(
    imports: list[ImportDll],
    section_rva: int,
) -> tuple[bytes, int, int]:
    blob = bytearray()
    ptr = 0

    def ensure(end: int) -> None:
        if len(blob) < end:
            blob.extend(b"\x00" * (end - len(blob)))

    def reserve(size: int, alignment: int = 1) -> int:
        nonlocal ptr
        ptr = _align(ptr, alignment)
        at = ptr
        ensure(at + size)
        ptr = at + size
        return at

    dll_infos: list[dict[str, int]] = []

    for item in imports:
        name_off = reserve(len(item.dll) + 1, 1)
        blob[name_off : name_off + len(item.dll) + 1] = item.dll.encode("ascii") + b"\x00"

        thunk_values: list[int] = []
        for sym in item.symbols:
            if sym.name:
                hint_off = reserve(2 + len(sym.name) + 1, 2)
                struct.pack_into("<H", blob, hint_off, 0)
                blob[hint_off + 2 : hint_off + 2 + len(sym.name) + 1] = (
                    sym.name.encode("ascii") + b"\x00"
                )
                thunk_values.append(section_rva + hint_off)
            else:
                thunk_values.append((sym.ordinal or 0) | (1 << 63))

        oft_off = reserve((len(thunk_values) + 1) * 8, 8)
        iat_off = reserve((len(thunk_values) + 1) * 8, 8)
        for i, value in enumerate(thunk_values):
            struct.pack_into("<Q", blob, oft_off + i * 8, value)
            struct.pack_into("<Q", blob, iat_off + i * 8, value)
        struct.pack_into("<Q", blob, oft_off + len(thunk_values) * 8, 0)
        struct.pack_into("<Q", blob, iat_off + len(thunk_values) * 8, 0)

        dll_infos.append(
            {
                "name_at": section_rva + name_off,
                "oft_at": section_rva + oft_off,
                "iat_at": section_rva + iat_off,
            }
        )

    desc_off = reserve((len(dll_infos) + 1) * 20, 8)
    for i, info in enumerate(dll_infos):
        struct.pack_into(
            "<IIIII",
            blob,
            desc_off + i * 20,
            info["oft_at"],
            0,
            0,
            info["name_at"],
            info["iat_at"],
        )
    struct.pack_into(
        "<IIIII",
        blob,
        desc_off + len(dll_infos) * 20,
        0,
        0,
        0,
        0,
        0,
    )
    return bytes(blob), section_rva + desc_off, len(dll_infos)


def _patch_optional_header(data: bytearray, pe, import_rva: int, import_count: int) -> None:
    opt_off = pe.DOS_HEADER.e_lfanew + 4 + 20
    size_of_image_off = opt_off + 56
    struct.pack_into("<I", data, size_of_image_off, pe.OPTIONAL_HEADER.SizeOfImage)
    import_entry_off = opt_off + 112 + 8 * 1
    struct.pack_into("<II", data, import_entry_off, import_rva, (import_count + 1) * 20)


def _append_section(data: bytearray, pe, section_name: bytes, section_data: bytes) -> None:
    file_align = pe.OPTIONAL_HEADER.FileAlignment
    sect_align = pe.OPTIONAL_HEADER.SectionAlignment

    if len(section_data) % file_align:
        section_data = section_data.ljust(
            _align(len(section_data), file_align),
            b"\x00",
        )

    new_rva = _align(pe.OPTIONAL_HEADER.SizeOfImage, sect_align)
    raw_off = _align(len(data), file_align)
    if raw_off > len(data):
        data.extend(b"\x00" * (raw_off - len(data)))
    data.extend(section_data)

    pe.OPTIONAL_HEADER.SizeOfImage = _align(
        new_rva + len(section_data),
        sect_align,
    )

    coff_off = pe.DOS_HEADER.e_lfanew + 4
    num_sections = struct.unpack_from("<H", data, coff_off + 2)[0]
    struct.pack_into("<H", data, coff_off + 2, num_sections + 1)

    opt_size = struct.unpack_from("<H", data, coff_off + 16)[0]
    sections_off = coff_off + 20 + opt_size + num_sections * 40

    header = bytearray(40)
    header[0:8] = section_name[:8].ljust(8, b"\x00")
    struct.pack_into("<I", header, 8, len(section_data))
    struct.pack_into("<I", header, 12, new_rva)
    struct.pack_into("<I", header, 16, len(section_data))
    struct.pack_into("<I", header, 20, raw_off)
    struct.pack_into("<I", header, 36, 0x40000040)  # initialized, readable data
    data[sections_off : sections_off + 40] = header


def patch_file(path: str) -> None:
    try:
        import pefile
    except ImportError as exc:
        raise SystemExit("Win7 PE patch requires pefile: pip install pefile") from exc

    with open(path, "rb") as handle:
        data = bytearray(handle.read())

    pe = pefile.PE(data=data, fast_load=False)
    imports = _read_imports(pe)
    moved = _apply_redirects(imports)
    if not moved:
        print(f"{path}: no Win7 imports redirected (skipped)")
        pe.close()
        return

    _validate_imports(imports)
    imports = _non_empty_imports(imports)

    sect_align = pe.OPTIONAL_HEADER.SectionAlignment
    section_rva = _align(pe.OPTIONAL_HEADER.SizeOfImage, sect_align)
    section_data, import_dir_rva, import_count = _build_import_section(imports, section_rva)
    _append_section(data, pe, b".w7imp", section_data)
    _patch_optional_header(data, pe, import_dir_rva, import_count)

    with open(path, "wb") as handle:
        handle.write(data)

    summary = ", ".join(f"{target}!{symbol}" for _, target, symbol in moved)
    print(f"Patched {path}: {summary}")
    pe.close()


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
        print("usage: patch_win7_pe.py [--dir RELEASE] [pe-file ...]", file=sys.stderr)
        return 2

    for target in targets:
        patch_file(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
