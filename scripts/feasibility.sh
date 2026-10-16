#!/bin/sh
set -eu
mkdir -p build
scripts/compile.sh scripts/probe.cr build/probe small
ld.lld -static -e probe -o build/probe.elf build/probe.o
test -z "$(nm -u build/probe.elf)"
readelf -h build/probe.elf
readelf -r build/probe.elf
objdump -d build/probe.elf
cat > build/checked.cr <<'CRYSTAL'
fun checked(a : UInt64) : UInt64
  a + 1_u64
end
CRYSTAL
if crystal build build/checked.cr --prelude=empty --cross-compile --target=x86_64-unknown-none --release -o build/checked >build/checked.log 2>&1; then
    echo 'checked arithmetic unexpectedly compiled without an overflow runtime' >&2
    exit 1
fi
grep -q 'Missing __crystal_raise_overflow' build/checked.log
