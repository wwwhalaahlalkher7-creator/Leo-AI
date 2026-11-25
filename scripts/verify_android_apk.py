#!/usr/bin/env python3
"""Check that an Android ARM64 APK contains Leo's native runtime safely."""
from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path, PurePosixPath

EXPECTED_ABI = "arm64-v8a"
REQUIRED_PAGE_ALIGNMENT = 16 * 1024
REQUIRED_NATIVE_LIBRARIES = {
    f"lib/{EXPECTED_ABI}/libleo_llama_backend.so",
    f"lib/{EXPECTED_ABI}/libc++_shared.so",
}
MODEL_SUFFIXES = {
    ".gguf",
    ".onnx",
    ".safetensors",
    ".tflite",
    ".pt",
    ".pth",
}


class AndroidApkValidationError(ValueError):
    """Raised when an APK fails Leo's ARM64 packaging contract."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AndroidApkValidationError(message)


def _is_arm64_elf(header: bytes) -> bool:
    # ELF e_ident: magic, class=ELF64, data=LSB; e_machine at bytes 18..19.
    return (
        len(header) >= 64
        and header[:4] == b"\x7fELF"
        and header[4] == 2
        and header[5] == 1
        and int.from_bytes(header[18:20], "little") == 183
    )


def _verify_elf_load_alignment(native_file, member_name: str, file_size: int) -> list[int]:
    """Require each ELF PT_LOAD segment to satisfy Android's 16 KB page size."""
    header = native_file.read(64)
    _require(_is_arm64_elf(header), f"Native library is not a 64-bit little-endian AArch64 ELF: {member_name}")
    program_offset = int.from_bytes(header[32:40], "little")
    entry_size = int.from_bytes(header[54:56], "little")
    entry_count = int.from_bytes(header[56:58], "little")
    _require(entry_size >= 56, f"ELF program-header entry is invalid: {member_name}")
    _require(entry_count > 0, f"ELF has no program headers: {member_name}")
    table_size = entry_size * entry_count
    _require(
        program_offset <= file_size and table_size <= file_size - program_offset,
        f"ELF program-header table is outside the file: {member_name}",
    )
    native_file.seek(program_offset)
    table = native_file.read(table_size)
    _require(len(table) == table_size, f"ELF program-header table is truncated: {member_name}")

    load_alignments: list[int] = []
    for index in range(entry_count):
        entry = table[index * entry_size:(index + 1) * entry_size]
        segment_type = int.from_bytes(entry[0:4], "little")
        if segment_type != 1:  # PT_LOAD
            continue
        file_offset = int.from_bytes(entry[8:16], "little")
        virtual_address = int.from_bytes(entry[16:24], "little")
        alignment = int.from_bytes(entry[48:56], "little")
        _require(
            alignment >= REQUIRED_PAGE_ALIGNMENT and alignment & (alignment - 1) == 0,
            f"ELF LOAD segment is not 16 KB aligned ({alignment:#x}): {member_name}",
        )
        _require(
            file_offset % REQUIRED_PAGE_ALIGNMENT == virtual_address % REQUIRED_PAGE_ALIGNMENT,
            f"ELF LOAD segment offset/address are not 16 KB congruent: {member_name}",
        )
        load_alignments.append(alignment)
    _require(bool(load_alignments), f"ELF contains no LOAD segments: {member_name}")
    return load_alignments


def validate_android_apk(apk_path: Path) -> dict[str, object]:
    apk_path = apk_path.resolve()
    _require(apk_path.is_file(), f"APK does not exist: {apk_path}")
    _require(apk_path.stat().st_size > 0, "APK is empty.")

    try:
        with zipfile.ZipFile(apk_path) as archive:
            corrupt_member = archive.testzip()
            _require(corrupt_member is None, f"APK ZIP integrity check failed at {corrupt_member}.")
            names = set(archive.namelist())
            _require(bool(names), "APK archive is empty.")
            for name in names:
                normalized = PurePosixPath(name)
                _require(
                    not normalized.is_absolute() and ".." not in normalized.parts,
                    f"Unsafe archive path in APK: {name}",
                )

            missing = sorted(REQUIRED_NATIVE_LIBRARIES - names)
            _require(
                not missing,
                "APK is missing required ARM64 native runtime files: " + ", ".join(missing),
            )

            native_members = sorted(
                name for name in names if name.startswith("lib/") and name.endswith(".so")
            )
            _require(bool(native_members), "APK contains no packaged native libraries.")
            elf_alignments: dict[str, list[int]] = {}
            for name in native_members:
                parts = PurePosixPath(name).parts
                _require(
                    len(parts) >= 3 and parts[1] == EXPECTED_ABI,
                    f"Unexpected native ABI in ARM64-only APK: {name}",
                )
                info = archive.getinfo(name)
                with archive.open(name) as native_file:
                    elf_alignments[name] = _verify_elf_load_alignment(native_file, name, info.file_size)

            bundled_models = sorted(
                name
                for name in names
                if PurePosixPath(name).suffix.lower() in MODEL_SUFFIXES
                or (
                    any(part.lower() in {"models", "voice_packs", "voice-models"}
                        for part in PurePosixPath(name).parts)
                    and PurePosixPath(name).suffix.lower() in {".bin", ".model", ".data"}
                )
            )
            _require(
                not bundled_models,
                "Model/voice weight files must be imported by the user, not bundled: "
                + ", ".join(bundled_models[:8]),
            )
    except zipfile.BadZipFile as error:
        raise AndroidApkValidationError(f"APK is not a valid ZIP archive: {error}") from error

    digest_builder = hashlib.sha256()
    with apk_path.open("rb") as apk_file:
        for chunk in iter(lambda: apk_file.read(1024 * 1024), b""):
            digest_builder.update(chunk)
    digest = digest_builder.hexdigest()
    return {
        "path": str(apk_path),
        "size_bytes": apk_path.stat().st_size,
        "sha256": digest,
        "native_libraries": native_members,
        "elf_load_alignments": elf_alignments,
        "page_alignment_bytes": REQUIRED_PAGE_ALIGNMENT,
        "abi": EXPECTED_ABI,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="APK produced by Flutter for android-arm64")
    args = parser.parse_args()
    try:
        result = validate_android_apk(args.apk)
    except (OSError, AndroidApkValidationError) as error:
        print(f"ANDROID APK CHECK FAILED: {error}", file=sys.stderr)
        return 1
    print("ANDROID APK CHECK PASSED:")
    print(f"  ABI: {result['abi']}")
    print(f"  Size: {result['size_bytes']} bytes")
    print(f"  SHA-256: {result['sha256']}")
    print(f"  ELF LOAD alignment: >= {result['page_alignment_bytes']} bytes")
    print("  Native libraries:")
    for item in result["native_libraries"]:
        alignments = ", ".join(f"{value:#x}" for value in result["elf_load_alignments"][item])
        print(f"    - {item} (PT_LOAD: {alignments})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
