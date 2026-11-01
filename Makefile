SHELL := /bin/sh
LIMINE_COMMIT := aad3edd370955449717a334f0289dee10e2c5f01
QEMU := qemu-system-x86_64 -machine q35 -cpu qemu64,+nx -m 128M -display gtk -vga std -serial stdio -monitor none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 -debugcon file:build/kernel.log
RUNTIME := $(wildcard runtime/*.cr userspace/lib/*.cr) scripts/compile.sh
SBIN := console
BIN := worker
PROGRAMS := $(SBIN) $(BIN)

.PHONY: all run test clean feasibility
.SECONDEXPANSION:
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

build/%.o: userspace/%/main.cr $$(wildcard userspace/%/*.cr) $(RUNTIME) | build
	scripts/compile.sh $< build/$* small

build/console.o: kernel/console/font.bin

build/%.elf: build/%.o linker/user.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/user.ld $(filter %.o,$^) -o $@
	test -z "$$(nm -u $@)"

build/initrd.tar: $(PROGRAMS:%=build/%.elf) $(shell find initrd -type f)
	rm -rf build/initrd
	mkdir -p build/initrd/bin build/initrd/sbin
	cp -R initrd/. build/initrd/
	for name in $(SBIN); do cp build/$$name.elf build/initrd/sbin/$$name; done
	for name in $(BIN); do cp build/$$name.elf build/initrd/bin/$$name; done
	tar --format=ustar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf $@ -C build/initrd .

build/kristal.iso: build/kernel.elf build/init.elf build/initrd.tar limine.conf vendor/limine/limine scripts/image.sh
	scripts/image.sh build/kernel.elf build/init.elf build/initrd.tar $@ >build/iso.log 2>&1

run: all
	$(QEMU) -cdrom build/kristal.iso

test: all
	scripts/test.py

feasibility:
	scripts/feasibility.sh

clean:
	rm -rf build
