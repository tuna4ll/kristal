#!/usr/bin/env python3
import os
import subprocess
import sys
import threading
import time

QEMU = [
    "qemu-system-x86_64", "-machine", "q35", "-cpu", "qemu64,+nx", "-m", "128M",
    "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04", "-debugcon", "file:build/kernel.log",
    "-cdrom", "build/kristal.iso",
]

PROMPT = "$ "

# each command is typed into the shell and must print the expected text before the next prompt
STEPS = [
    ("echo hello kristal", "hello kristal"),
    ("cat /etc/motd", "Welcome to Kristal."),
    ("ls /bin", "selftest"),
    ("ls -l /dev", "crw--w---- 0 console"),
    ("cd /etc", ""),
    ("pwd", "/etc"),
    ("cat < motd", "Welcome to Kristal."),
    ("cd ..", ""),
    ("uname -a", "Kristal kristal 0.1 microkernel x86_64"),
    ("echo $HOME '$HOME' \"$PATH\"", "/ $HOME /bin:/sbin"),
    ("ls /bin | cat | wc -l", "7"),
    ("echo one two|cat|cat", "one two"),
    ("cat /bin/sh | cat | wc -c", str(os.path.getsize("build/initrd/bin/sh"))),
    ("cat < /etc/motd | wc -w", "3"),
    ("nosuch", "sh: nosuch: not found"),
    ("echo $?", "127"),
    ("selftest", "selftest: exiting"),
    ("echo $?", "0"),
]


class Machine:
    def __init__(self):
        self.process = subprocess.Popen(QEMU, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.output = ""
        self.cursor = 0
        self.lock = threading.Lock()
        threading.Thread(target=self.pump, daemon=True).start()

    def pump(self):
        while True:
            chunk = self.process.stdout.read1(4096)
            if not chunk:
                return
            with self.lock:
                self.output += chunk.decode(errors="replace").replace("\r", "")

    def expect(self, text, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                found = self.output.find(text, self.cursor)
                if found >= 0:
                    self.cursor = found + len(text)
                    return True
            time.sleep(0.02)
        return False

    def send(self, line):
        self.process.stdin.write(line.encode() + b"\r")
        self.process.stdin.flush()


def main():
    machine = Machine()
    failures = []
    if not machine.expect(PROMPT, 30):
        failures.append("no shell prompt")
    else:
        for command, expected in STEPS:
            machine.send(command)
            if not machine.expect(command):
                failures.append(f"{command!r} was not echoed")
                break
            if expected and not machine.expect(expected):
                failures.append(f"{command!r} did not print {expected!r}")
            if not machine.expect(PROMPT):
                failures.append(f"no prompt after {command!r}")
                break
        machine.send("exit 0")
    try:
        code = machine.process.wait(timeout=20)
    except subprocess.TimeoutExpired:
        machine.process.kill()
        code = None
        failures.append("did not power off")
    time.sleep(0.1)
    sys.stdout.write(machine.output)
    with open("build/kernel.log", errors="replace") as log:
        sys.stdout.write(log.read())
    # isa-debug-exit turns 0x10 into (0x10 << 1) | 1
    if code is not None and code != 33:
        failures.append(f"qemu exited with {code}")
    for failure in failures:
        print(f"test: {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
