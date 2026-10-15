#!/bin/sh
set -eu
mkdir -p build
scripts/compile.sh scripts/probe.cr build/probe small
ld.lld -static -e probe -o build/probe.elf build/probe.o
test -z "$(nm -u build/probe.elf)"
readelf -h build/probe.elf
readelf -r build/probe.elf
objdump -d build/probe.elf
