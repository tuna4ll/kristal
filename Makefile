SHELL := /bin/sh
LIMINE_COMMIT := aad3edd370955449717a334f0289dee10e2c5f01
QEMU := qemu-system-x86_64 -machine q35 -cpu qemu64,+nx -m 128M -display gtk -vga std -serial stdio -monitor none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 -debugcon file:build/kernel.log

.PHONY: all run test clean feasibility
all: build/kristal.iso

build:
	mkdir -p $@

vendor/limine/limine:
	mkdir -p vendor
	test -d vendor/limine/.git || git clone --depth 1 --branch v8.7.0-binary https://github.com/limine-bootloader/limine.git vendor/limine
	test "$$(git -C vendor/limine rev-parse HEAD)" = "$(LIMINE_COMMIT)"
	$(MAKE) -C vendor/limine

build/kernel.o: $(shell find kernel runtime -name '*.cr') kernel/console/font.bin scripts/compile.sh | build
	scripts/compile.sh kernel/main.cr build/kernel kernel

build/kernel.elf: build/kernel.o linker/kernel.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/kernel.ld build/kernel.o -o $@
	test -z "$$(nm -u $@)"

build/user.o: userspace/init/main.cr userspace/syscall.cr runtime/base.cr runtime/abi.cr scripts/compile.sh | build
	scripts/compile.sh userspace/init/main.cr build/user small

build/init.elf: build/user.o linker/user.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/user.ld build/user.o -o $@
	test -z "$$(nm -u $@)"

build/worker.o: userspace/worker/main.cr userspace/syscall.cr runtime/base.cr runtime/abi.cr scripts/compile.sh | build
	scripts/compile.sh userspace/worker/main.cr build/worker small

build/worker.elf: build/worker.o linker/user.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/user.ld build/worker.o -o $@
	test -z "$$(nm -u $@)"

build/console.o: userspace/console/main.cr userspace/syscall.cr runtime/base.cr runtime/abi.cr runtime/screen.cr kernel/console/font.bin scripts/compile.sh | build
	scripts/compile.sh userspace/console/main.cr build/console small

build/console.elf: build/console.o linker/user.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/user.ld build/console.o -o $@
	test -z "$$(nm -u $@)"

build/kristal.iso: build/console.elf build/worker.elf build/init.elf build/kernel.elf limine.conf vendor/limine/limine scripts/image.sh
	scripts/image.sh build/kernel.elf build/init.elf build/console.elf build/worker.elf $@ >build/iso.log 2>&1

run: all
	$(QEMU) -cdrom build/kristal.iso

test: all
	scripts/test.py

feasibility:
	scripts/feasibility.sh

clean:
	rm -rf build
