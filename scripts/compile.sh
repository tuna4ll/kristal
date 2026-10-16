#!/bin/sh
set -eu
crystal --version | grep -q '^Crystal 1.22.0 ' || { echo 'Crystal 1.22.0 required' >&2; exit 1; }
llc --version | grep -q 'LLVM version 23.1.1$' || { echo 'LLVM 23.1.1 required' >&2; exit 1; }
ld.lld --version | grep -q '^LLD 23.1.1 ' || { echo 'LLD 23.1.1 required' >&2; exit 1; }
src=$1
out=$2
model=$3
shift 3
crystal build "$src" --prelude=empty --cross-compile --target=x86_64-unknown-none --release --no-debug --emit llvm-ir -o "$out" "$@" > "$out.link.txt"
# Interrupts may overwrite the SysV red zone; Crystal has no CLI switch for it.
sed -i -E 's/ uwtable//g; s/(attributes #[0-9]+ = \{)/\1 noredzone/' "$out.ll"
llc -filetype=obj -mtriple=x86_64-unknown-none -code-model="$model" -relocation-model=static -mattr=-sse,-sse2,-mmx "$out.ll" -o "$out.o"
