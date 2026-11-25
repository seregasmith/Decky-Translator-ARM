"""Package a self-contained Linux ARM64 Decky install ZIP."""

import argparse
import json
import shutil
import tarfile
import tempfile
import zipfile
from pathlib import Path


def check_arm64(dependencies):
    elf_count = 0
    for path in dependencies.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as binary:
            header = binary.read(20)
        if header[:4] != b"\x7fELF":
            continue
        # ELF64, little-endian, EM_AARCH64.
        if header[4:6] != b"\x02\x01" or header[18:20] != b"\xb7\x00":
            raise ValueError(f"Expected an ARM64 Linux binary: {path}")
        elf_count += 1
    if not elf_count:
        raise ValueError("No ARM64 Linux binaries found")
    print(f"Verified {elf_count} ARM64 ELF files")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dependencies", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent

    for required in (
        "python313/python/bin/python3.13",
        "py_modules/PIL",
        "py_modules/ctranslate2",
        "py_modules/onnxruntime",
        "py_modules/rapidocr",
        "loader_py_modules/cp314/PIL",
        "loader_py_modules/cp314/evdev",
    ):
        if not (args.dependencies / required).exists():
            raise FileNotFoundError(args.dependencies / required)
    check_arm64(args.dependencies)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as stage:
        package = Path(stage) / "decky-translator"
        package.mkdir()
        for name in ("LICENSE", "README.md", "THIRD_PARTY_LICENSES", "main.py", "plugin.json"):
            shutil.copyfile(root / name, package / name)
        for name in ("dist", "py_modules"):
            shutil.copytree(
                root / name, package / name,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.map"),
            )

        metadata = json.loads((root / "package.json").read_text())
        metadata["version"] += "-arm64.2"
        metadata.pop("remote_binary", None)
        (package / "package.json").write_text(json.dumps(metadata, indent=2) + "\n")

        archive = package / "bin" / "plugin-dependencies.tar.gz"
        archive.parent.mkdir()
        with tarfile.open(archive, "w:gz", compresslevel=3) as deps:
            for name in ("py_modules", "python313", "loader_py_modules"):
                deps.add(args.dependencies / name, arcname=name)

        temporary_zip = Path(stage) / "plugin.zip"
        with zipfile.ZipFile(temporary_zip, "w", compression=zipfile.ZIP_DEFLATED) as plugin:
            for path in sorted(package.rglob("*")):
                if path.is_file():
                    compress = zipfile.ZIP_STORED if path == archive else zipfile.ZIP_DEFLATED
                    plugin.write(path, path.relative_to(stage), compress_type=compress)
        temporary_zip.replace(args.output)


if __name__ == "__main__":
    main()
