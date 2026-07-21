#!/usr/bin/env python3
"""Prepend a TLS callback stub to flutter_windows.dll for Win7 GetProcAddress IAT patch."""

from __future__ import annotations

import struct
from pathlib import Path


def _align(value: int, alignment: int) -> int:
    mask = alignment - 1
    return (value + mask) & ~mask


def _find_iat_rva(pe, dll_name: str, symbol: str) -> int:
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() != dll_name.lower():
            continue
        iat_rva = entry.struct.FirstThunk
        lookup_rva = entry.struct.OriginalFirstThunk or iat_rva
        index = 0
        while True:
            value = struct.unpack("<Q", pe.get_data(lookup_rva + index * 8, 8))[0]
            if value == 0:
                break
            if value & (1 << 63):
                name = f"#{value & 0xFFFF}"
            else:
                raw = pe.get_data(value + 2, 64)
                name = raw.split(b"\x00", 1)[0].decode("ascii")
            if name == symbol:
                return iat_rva + index * 8
            index += 1
    raise SystemExit(f"{dll_name}!{symbol} IAT not found")


def _rva(pe, address: int) -> int:
    image_base = pe.OPTIONAL_HEADER.ImageBase
    if address >= image_base:
        return address - image_base
    return address


def inject_tls_callback(path: str) -> None:
    import pefile

    data = bytearray(Path(path).read_bytes())
    pe = pefile.PE(data=data, fast_load=False)
    pe.parse_data_directories(
        directories=[
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
            pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_TLS"],
        ]
    )

    if not hasattr(pe, "DIRECTORY_ENTRY_TLS") or not pe.DIRECTORY_ENTRY_TLS:
        raise SystemExit(f"{path}: TLS directory missing")

    iat_rva = _find_iat_rva(pe, "scn_ntdll.dll", "ScnWin7TlsCallback")
    tls = pe.DIRECTORY_ENTRY_TLS.struct
    if tls.AddressOfCallBacks == 0:
        raise SystemExit(f"{path}: TLS callback array missing")

    image_base = pe.OPTIONAL_HEADER.ImageBase
    file_alignment = pe.OPTIONAL_HEADER.FileAlignment
    section_alignment = pe.OPTIONAL_HEADER.SectionAlignment

    callbacks_rva = _rva(pe, tls.AddressOfCallBacks)
    existing: list[int] = []
    index = 0
    while True:
        va = struct.unpack("<Q", pe.get_data(callbacks_rva + index * 8, 8))[0]
        if va == 0:
            break
        existing.append(va)
        index += 1

    last_section = pe.sections[-1]
    new_section_raw = _align(
        last_section.PointerToRawData + last_section.SizeOfRawData, file_alignment
    )
    new_section_rva = _align(
        last_section.VirtualAddress + last_section.Misc_VirtualSize, section_alignment
    )

    iat_va = image_base + iat_rva
    rip_next = image_base + new_section_rva + 6
    stub = bytearray([0xFF, 0x25])
    stub += struct.pack("<i", iat_va - rip_next)
    stub += b"\xCC" * (16 - len(stub))

    stub_va = image_base + new_section_rva
    callback_bytes = b"".join(
        struct.pack("<Q", va) for va in [stub_va, *existing]
    ) + struct.pack("<Q", 0)

    section_body = bytes(stub) + callback_bytes
    section_raw_size = _align(len(section_body), file_alignment)
    section_body = section_body.ljust(section_raw_size, b"\x00")

    if new_section_raw + section_raw_size > len(data):
        data.extend(b"\x00" * (new_section_raw + section_raw_size - len(data)))
    data[new_section_raw : new_section_raw + section_raw_size] = section_body

    sections_offset = pe.DOS_HEADER.e_lfanew + 4 + 20 + pe.FILE_HEADER.SizeOfOptionalHeader
    header_offset = sections_offset + len(pe.sections) * 40
    if header_offset + 40 > pe.OPTIONAL_HEADER.SizeOfHeaders:
        raise SystemExit(f"{path}: no room for new section header")

    new_header = bytearray(40)
    struct.pack_into("8s", new_header, 0, b".scn7tls")
    struct.pack_into("<I", new_header, 8, len(section_body))
    struct.pack_into("<I", new_header, 12, new_section_rva)
    struct.pack_into("<I", new_header, 16, section_raw_size)
    struct.pack_into("<I", new_header, 20, new_section_raw)
    struct.pack_into("<I", new_header, 36, 0x60000020)

    data[header_offset : header_offset + 40] = new_header
    struct.pack_into("<H", data, pe.DOS_HEADER.e_lfanew + 6, pe.FILE_HEADER.NumberOfSections + 1)

    size_of_image = _align(new_section_rva + len(section_body), section_alignment)
    struct.pack_into("<I", data, pe.DOS_HEADER.e_lfanew + 24 + 56, size_of_image)

    array_rva = new_section_rva + len(stub)
    tls_dir_rva = pe.OPTIONAL_HEADER.DATA_DIRECTORY[
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_TLS"]
    ].VirtualAddress
    struct.pack_into("<Q", data, pe.get_offset_from_rva(tls_dir_rva + 24), image_base + array_rva)

    Path(path).write_bytes(data)

    verify = pefile.PE(path, fast_load=True)
    verify.parse_data_directories(
        directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]]
    )
    for entry in verify.DIRECTORY_ENTRY_IMPORT:
        if entry.dll.decode().lower() == "ntdll.dll":
            names = [(imp.name or b"").decode() for imp in entry.imports if imp.name]
            if names.count("RtlUnwindEx") > 1:
                raise SystemExit(f"{path}: corrupted ntdll imports after TLS inject")
    verify.close()

    print(
        f"Injected Win7 TLS callback into {path} "
        f"(stub_rva=0x{new_section_rva:x}, callbacks={len(existing) + 1})"
    )


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Inject Win7 TLS callback into flutter PE.")
    parser.add_argument("path", help="flutter_windows.dll to modify")
    args = parser.parse_args()
    inject_tls_callback(args.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
