#!/usr/bin/env python3
"""Fetch fixed Termux PRoot runtime packages for the APK and the Android x86_64 emulator test."""
import argparse
import hashlib
import os
import shutil
import subprocess
import tempfile
import urllib.request

BASE = "https://packages.termux.dev/apt/termux-main/"
ARCHES = {
    "aarch64": {
        "termux": "aarch64", "elf_machine": 183,
        "packages": {
            "proot": ("pool/main/p/proot/proot_5.1.107.96_aarch64.deb", "8199dca06dccb693ec09fb1759e3e1ad08b4863f0c11c612f89c20bd9ecdc1a0"),
            "libtalloc": ("pool/main/libt/libtalloc/libtalloc_2.5.0_aarch64.deb", "556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7"),
            "libandroid-shmem": ("pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_aarch64.deb", "0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6"),
        },
    },
    "x86_64": {
        "termux": "x86_64", "elf_machine": 62,
        "packages": {
            "proot": ("pool/main/p/proot/proot_5.1.107.96_x86_64.deb", "77ea45540071ca543adda2b51aca2bc3761c52904d013fd0890682288eff9455"),
            "libtalloc": ("pool/main/libt/libtalloc/libtalloc_2.5.0_x86_64.deb", "b8c6d95f20075dc1f9ec6573575b2444e8d526e48e0d8d6d5cf4e071e6e06530"),
            "libandroid-shmem": ("pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_x86_64.deb", "ffa9e4c87467b158b148d0ff92dda796aa038276c2075af3269cdcdb06f25797"),
        },
    },
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def require_elf(path, machine):
    with open(path, "rb") as f:
        head = f.read(20)
    if len(head) < 20 or head[:4] != b"\x7fELF" or head[4] != 2 or int.from_bytes(head[18:20], "little") != machine:
        raise SystemExit(f"unexpected ELF architecture for runtime file: {path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", nargs="?", default="android/app/src/main/assets/proot")
    parser.add_argument("--arch", choices=sorted(ARCHES), default="aarch64")
    args = parser.parse_args()
    config = ARCHES[args.arch]
    packages = config["packages"]
    target = os.path.abspath(args.target)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target):
        shutil.rmtree(target)
    with tempfile.TemporaryDirectory(prefix="miniarino-proot-") as work:
        extracted = os.path.join(work, "extract")
        os.makedirs(extracted)
        roots = {}
        for name, (relative, expected) in packages.items():
            deb = os.path.join(work, name + ".deb")
            request = urllib.request.Request(BASE + relative, headers={"User-Agent": "MiniArino reproducible Android build"})
            with urllib.request.urlopen(request, timeout=60) as response, open(deb, "wb") as out:
                shutil.copyfileobj(response, out)
            actual = sha256(deb)
            if actual != expected:
                raise SystemExit(f"SHA-256 mismatch for pinned {name} package: {actual}")
            arch = subprocess.check_output(["dpkg-deb", "-f", deb, "Architecture"], text=True).strip()
            if arch != config["termux"]:
                raise SystemExit(f"unexpected {name} package architecture: {arch}")
            root = os.path.join(extracted, name)
            os.makedirs(root)
            subprocess.check_call(["dpkg-deb", "-x", deb, root])
            roots[name] = root
        def source(name, suffix):
            found = []
            for parent, _, files in os.walk(roots[name]):
                for filename in files:
                    if filename == suffix:
                        found.append(os.path.join(parent, filename))
            if len(found) != 1:
                raise SystemExit(f"expected one {suffix} in pinned {name} package, found {len(found)}")
            return found[0]
        proot = source("proot", "proot")
        loader = source("proot", "loader")
        talloc = source("libtalloc", "libtalloc.so.2.5.0")
        shmem = source("libandroid-shmem", "libandroid-shmem.so")
        for path in (proot, loader, talloc, shmem):
            require_elf(path, config["elf_machine"])
        os.makedirs(os.path.join(target, "bin"), exist_ok=True)
        os.makedirs(os.path.join(target, "lib"), exist_ok=True)
        os.makedirs(os.path.join(target, "libexec", "proot"), exist_ok=True)
        shutil.copy2(proot, os.path.join(target, "bin", "proot"))
        shutil.copy2(loader, os.path.join(target, "libexec", "proot", "loader"))
        shutil.copy2(talloc, os.path.join(target, "lib", "libtalloc.so.2"))
        shutil.copy2(shmem, os.path.join(target, "lib", "libandroid-shmem.so"))
    print(f"Staged pinned Termux PRoot for {args.arch} at {target}")


if __name__ == "__main__":
    main()
