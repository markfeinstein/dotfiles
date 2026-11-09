#!/usr/bin/env python3
"""Relationally compare unsigned, signed, and signature-removed yabai Mach-O files."""

from __future__ import annotations

import os
import struct
import sys
from dataclasses import dataclass

MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
HEADER_SIZE = 32
SEGMENT_64_SIZE = 72
SECTION_64_SIZE = 80
CODE_SIGNATURE_COMMAND_SIZE = 16
PAGE_SIZE = 16 * 1024
SIGNATURE_ALIGNMENT = 16
MAX_FILE_SIZE = 512 * 1024 * 1024
MAX_LOAD_COMMANDS = 65535
MAX_LOAD_COMMAND_BYTES = 16 * 1024 * 1024
MAX_SIGNATURE_SIZE = 16 * 1024 * 1024


class ComparisonError(Exception):
    pass


@dataclass(frozen=True)
class LoadCommand:
    index: int
    offset: int
    command: int
    size: int


@dataclass(frozen=True)
class Linkedit:
    command: LoadCommand
    vmsize_offset: int
    filesize_offset: int
    vmsize: int
    fileoff: int
    filesize: int


@dataclass(frozen=True)
class CodeSignature:
    command: LoadCommand
    dataoff: int
    datasize: int


@dataclass(frozen=True)
class MachO:
    data: bytes
    path: str
    ncmds: int
    sizeofcmds: int
    commands_end: int
    commands: tuple[LoadCommand, ...]
    linkedit: Linkedit
    code_signatures: tuple[CodeSignature, ...]


def fail(message: str) -> None:
    raise ComparisonError(message)


def read_file(path: str) -> bytes:
    try:
        size = os.path.getsize(path)
    except OSError as error:
        fail(f"cannot stat {path!r}: {error}")
    if size < HEADER_SIZE:
        fail(f"{path!r}: file is too short for a 64-bit Mach-O header")
    if size > MAX_FILE_SIZE:
        fail(f"{path!r}: file exceeds the {MAX_FILE_SIZE}-byte limit")
    try:
        with open(path, "rb") as stream:
            data = stream.read(MAX_FILE_SIZE + 1)
    except OSError as error:
        fail(f"cannot read {path!r}: {error}")
    if len(data) != size:
        fail(f"{path!r}: file changed while being read")
    return data


def segment_name(raw: bytes, path: str, command_index: int) -> str:
    name, separator, padding = raw.partition(b"\0")
    if separator and any(padding):
        fail(f"{path!r}: load command {command_index} has a non-zero segment-name suffix")
    try:
        return name.decode("ascii")
    except UnicodeDecodeError:
        fail(f"{path!r}: load command {command_index} has a non-ASCII segment name")


def parse_macho(path: str) -> MachO:
    data = read_file(path)
    try:
        magic, cputype, _cpusubtype, _filetype, ncmds, sizeofcmds, _flags, _reserved = (
            struct.unpack_from("<IiiIIIII", data, 0)
        )
    except struct.error as error:
        fail(f"{path!r}: invalid Mach-O header: {error}")
    if magic != MH_MAGIC_64:
        fail(f"{path!r}: not a thin little-endian 64-bit Mach-O")
    if cputype != CPU_TYPE_ARM64:
        fail(f"{path!r}: Mach-O CPU type is not arm64")
    if ncmds > MAX_LOAD_COMMANDS:
        fail(f"{path!r}: ncmds exceeds {MAX_LOAD_COMMANDS}")
    if sizeofcmds > MAX_LOAD_COMMAND_BYTES:
        fail(f"{path!r}: sizeofcmds exceeds {MAX_LOAD_COMMAND_BYTES}")
    commands_end = HEADER_SIZE + sizeofcmds
    if commands_end > len(data):
        fail(f"{path!r}: load-command region extends beyond the file")

    offset = HEADER_SIZE
    commands: list[LoadCommand] = []
    linkedit_segments: list[Linkedit] = []
    code_signatures: list[CodeSignature] = []
    for index in range(ncmds):
        if offset + 8 > commands_end:
            fail(f"{path!r}: load command {index} header exceeds sizeofcmds")
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8:
            fail(f"{path!r}: load command {index} has cmdsize below 8")
        if cmdsize % 8 != 0:
            fail(f"{path!r}: load command {index} is not 8-byte aligned")
        next_offset = offset + cmdsize
        if next_offset > commands_end:
            fail(f"{path!r}: load command {index} exceeds sizeofcmds")
        command = LoadCommand(index, offset, cmd, cmdsize)
        commands.append(command)
        if cmd == LC_CODE_SIGNATURE:
            if cmdsize != CODE_SIGNATURE_COMMAND_SIZE:
                fail(f"{path!r}: LC_CODE_SIGNATURE command {index} is not 16 bytes")
            dataoff, datasize = struct.unpack_from("<II", data, offset + 8)
            code_signatures.append(CodeSignature(command, dataoff, datasize))
        if cmd == LC_SEGMENT_64:
            if cmdsize < SEGMENT_64_SIZE:
                fail(f"{path!r}: LC_SEGMENT_64 command {index} is truncated")
            nsects = struct.unpack_from("<I", data, offset + 64)[0]
            expected_size = SEGMENT_64_SIZE + nsects * SECTION_64_SIZE
            if expected_size != cmdsize:
                fail(f"{path!r}: LC_SEGMENT_64 command {index} has inconsistent section size")
            name = segment_name(data[offset + 8 : offset + 24], path, index)
            if name == "__LINKEDIT":
                _vmaddr, vmsize, fileoff, filesize = struct.unpack_from(
                    "<QQQQ", data, offset + 24
                )
                if fileoff > len(data) or filesize > len(data) - fileoff:
                    fail(f"{path!r}: __LINKEDIT file range exceeds the file")
                linkedit_segments.append(
                    Linkedit(
                        command=command,
                        vmsize_offset=offset + 32,
                        filesize_offset=offset + 48,
                        vmsize=vmsize,
                        fileoff=fileoff,
                        filesize=filesize,
                    )
                )
        offset = next_offset

    if offset != commands_end:
        fail(f"{path!r}: ncmds does not consume exactly sizeofcmds")
    if len(linkedit_segments) != 1:
        fail(f"{path!r}: expected exactly one LC_SEGMENT_64 named __LINKEDIT")
    return MachO(
        data=data,
        path=path,
        ncmds=ncmds,
        sizeofcmds=sizeofcmds,
        commands_end=commands_end,
        commands=tuple(commands),
        linkedit=linkedit_segments[0],
        code_signatures=tuple(code_signatures),
    )


def round_page(value: int) -> int:
    if value <= 0:
        fail("__LINKEDIT filesize must be non-zero")
    return (value + PAGE_SIZE - 1) // PAGE_SIZE * PAGE_SIZE


def require_source_layout(macho: MachO) -> None:
    if macho.code_signatures:
        fail("source contains LC_CODE_SIGNATURE")
    linkedit = macho.linkedit
    if linkedit.fileoff + linkedit.filesize != len(macho.data):
        fail("source __LINKEDIT does not end at EOF")
    minimum = round_page(linkedit.filesize)
    # The Nix input was itself ad-hoc signed before stripping. Current arm64
    # codesign may leave one 16KiB allocation page in vmsize after removal.
    if linkedit.vmsize not in (minimum, minimum + PAGE_SIZE):
        fail("source __LINKEDIT.vmsize is not a bounded 16KiB page allocation")


def require_removed_layout(macho: MachO) -> None:
    if macho.code_signatures:
        fail("signature-removed candidate contains LC_CODE_SIGNATURE")
    linkedit = macho.linkedit
    if linkedit.fileoff + linkedit.filesize != len(macho.data):
        fail("signature-removed __LINKEDIT does not end at EOF")
    if linkedit.vmsize <= 0 or linkedit.vmsize % PAGE_SIZE != 0:
        fail("signature-removed __LINKEDIT.vmsize is zero or not 16KiB aligned")
    maximum = round_page(linkedit.filesize + MAX_SIGNATURE_SIZE + SIGNATURE_ALIGNMENT - 1)
    if linkedit.vmsize > maximum:
        fail("signature-removed __LINKEDIT.vmsize exceeds the signature-size bound")


def compare_bytes_except(data_a: bytes, data_b: bytes, ignored: list[tuple[int, int]], message: str) -> None:
    if len(data_a) != len(data_b):
        fail(f"{message}: lengths differ")
    cursor = 0
    for start, end in sorted(ignored):
        if start < cursor or end < start or end > len(data_a):
            fail("internal comparison range is invalid")
        if data_a[cursor:start] != data_b[cursor:start]:
            fail(message)
        cursor = end
    if data_a[cursor:] != data_b[cursor:]:
        fail(message)


def compare(source_path: str, signed_path: str, removed_path: str) -> None:
    source = parse_macho(source_path)
    signed = parse_macho(signed_path)
    removed = parse_macho(removed_path)

    require_source_layout(source)
    require_removed_layout(removed)
    if len(source.data) != len(removed.data):
        fail("source and signature-removed candidate lengths differ")
    if source.ncmds != removed.ncmds or source.sizeofcmds != removed.sizeofcmds:
        fail("source and signature-removed load-command headers differ")
    if source.commands != removed.commands:
        fail("source and signature-removed load-command structures differ")
    source_linkedit = source.linkedit
    removed_linkedit = removed.linkedit
    if (
        source_linkedit.command.index != removed_linkedit.command.index
        or source_linkedit.command.offset != removed_linkedit.command.offset
        or source_linkedit.command.size != removed_linkedit.command.size
        or source_linkedit.fileoff != removed_linkedit.fileoff
        or source_linkedit.filesize != removed_linkedit.filesize
    ):
        fail("source and signature-removed __LINKEDIT structures differ")
    compare_bytes_except(
        source.data,
        removed.data,
        [(source_linkedit.vmsize_offset, source_linkedit.vmsize_offset + 8)],
        "source and signature-removed bytes differ outside __LINKEDIT.vmsize",
    )

    if len(signed.code_signatures) != 1:
        fail("signed candidate must contain exactly one LC_CODE_SIGNATURE")
    signature = signed.code_signatures[0]
    if signed.ncmds != source.ncmds + 1:
        fail("signed ncmds is not source ncmds plus one")
    if signed.sizeofcmds != source.sizeofcmds + CODE_SIGNATURE_COMMAND_SIZE:
        fail("signed sizeofcmds does not append exactly one signature command")
    if signed.commands[:-1] != source.commands:
        fail("signed pre-signature load-command structure differs from source")
    if signature.command.index != source.ncmds or signature.command.offset != source.commands_end:
        fail("LC_CODE_SIGNATURE is not the terminal appended load command")
    if signature.command != signed.commands[-1]:
        fail("LC_CODE_SIGNATURE is not the final load command")
    if signature.datasize <= 0 or signature.datasize > MAX_SIGNATURE_SIZE:
        fail("code-signature size is zero or exceeds the bound")
    if signature.dataoff % SIGNATURE_ALIGNMENT != 0:
        fail("code-signature data offset is not 16-byte aligned")
    if signature.dataoff < len(source.data):
        fail("code-signature data overlaps unsigned source bytes")
    padding_size = signature.dataoff - len(source.data)
    if padding_size >= SIGNATURE_ALIGNMENT:
        fail("pre-signature alignment padding is too large")
    if any(signed.data[len(source.data) : signature.dataoff]):
        fail("pre-signature alignment padding is non-zero")
    if signature.dataoff + signature.datasize != len(signed.data):
        fail("code-signature data range is not terminal")

    signed_linkedit = signed.linkedit
    if (
        signed_linkedit.command.index != source_linkedit.command.index
        or signed_linkedit.command.offset != source_linkedit.command.offset
        or signed_linkedit.command.size != source_linkedit.command.size
        or signed_linkedit.fileoff != source_linkedit.fileoff
    ):
        fail("signed __LINKEDIT structure/fileoff differs from source")
    expected_signed_filesize = len(signed.data) - signed_linkedit.fileoff
    if signed_linkedit.filesize != expected_signed_filesize:
        fail("signed __LINKEDIT.filesize does not cover the signed allocation")
    expected_signed_vmsize = round_page(signed_linkedit.filesize)
    if signed_linkedit.vmsize != expected_signed_vmsize:
        fail("signed __LINKEDIT.vmsize is not the canonical 16KiB page round-up")
    if removed_linkedit.vmsize != signed_linkedit.vmsize:
        fail("signature removal did not retain the validated signed __LINKEDIT.vmsize")

    ignored_signed = [
        (16, 24),  # ncmds and sizeofcmds
        (source_linkedit.vmsize_offset, source_linkedit.vmsize_offset + 8),
        (source_linkedit.filesize_offset, source_linkedit.filesize_offset + 8),
        (source.commands_end, source.commands_end + CODE_SIGNATURE_COMMAND_SIZE),
    ]
    compare_bytes_except(
        source.data,
        signed.data[: len(source.data)],
        ignored_signed,
        "signed bytes differ outside codesign-managed fields",
    )
    if any(source.data[source.commands_end : source.commands_end + CODE_SIGNATURE_COMMAND_SIZE]):
        fail("source has no zero padding for the appended signature command")


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(
            f"usage: {argv[0]} UNSIGNED_SOURCE SIGNED_CANDIDATE REMOVED_SIGNATURE_CANDIDATE",
            file=sys.stderr,
        )
        return 2
    try:
        compare(argv[1], argv[2], argv[3])
    except ComparisonError as error:
        print(f"compare-yabai-macho: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
