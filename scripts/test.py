#!/usr/bin/env python3
import subprocess
import sys

QEMU = [
    "qemu-system-x86_64", "-machine", "q35", "-cpu", "qemu64,+nx", "-m", "128M",
    "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04", "-debugcon", "file:build/kernel.log",
    "-cdrom", "build/kristal.iso",
]

EXPECT = [
    "Hello World from Userspace",
    "worker: exiting",
    "init: worker exited normally",
    "[Kristal] init exited, powering off",
]


def main():
    try:
        run = subprocess.run(QEMU, stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    except subprocess.TimeoutExpired as error:
        sys.stdout.write((error.stdout or b"").decode(errors="replace"))
        print("test: timed out")
        return 1
    output = run.stdout.decode(errors="replace")
    with open("build/kernel.log", errors="replace") as log:
        output += log.read()
    sys.stdout.write(output)
    missing = [line for line in EXPECT if line not in output]
    for line in missing:
        print(f"test: missing {line!r}")
    # isa-debug-exit turns 0x10 into (0x10 << 1) | 1
    if run.returncode != 33:
        print(f"test: qemu exited with {run.returncode}")
        return 1
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
