SHELL := /bin/sh
LIMINE_COMMIT := aad3edd370955449717a334f0289dee10e2c5f01
QEMU := qemu-system-x86_64 -machine q35 -cpu qemu64,+nx -m 128M -display none -serial stdio -monitor none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04

.PHONY: all run test clean feasibility
all: build/kristal.iso

build:
	mkdir -p $@

vendor/limine/limine:
	mkdir -p vendor
	test -d vendor/limine/.git || git clone --depth 1 --branch v8.7.0-binary https://github.com/limine-bootloader/limine.git vendor/limine
	test "$$(git -C vendor/limine rev-parse HEAD)" = "$(LIMINE_COMMIT)"
	$(MAKE) -C vendor/limine

build/kernel.o: $(shell find kernel runtime -name '*.cr') scripts/compile.sh | build
	scripts/compile.sh kernel/main.cr build/kernel kernel

build/entry.o: kernel/arch/x86_64/entry.asm | build
	nasm -f elf64 $< -o $@

build/kernel.elf: build/kernel.o build/entry.o linker/kernel.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/kernel.ld build/entry.o build/kernel.o -o $@
	test -z "$$(nm -u $@)"

build/user.o: userspace/init/main.cr runtime/base.cr scripts/compile.sh | build
	scripts/compile.sh userspace/init/main.cr build/user small

build/user-entry.o: userspace/init/entry.asm | build
	nasm -f elf64 $< -o $@

build/init.elf: build/user.o build/user-entry.o linker/user.ld
	ld.lld -nostdlib -static -z max-page-size=4096 -T linker/user.ld build/user-entry.o build/user.o -o $@
	test -z "$$(nm -u $@)"

build/kristal.iso: build/init.elf build/kernel.elf limine.conf vendor/limine/limine
	mkdir -p build/iso/boot/limine build/iso/EFI/BOOT
	cp build/kernel.elf build/init.elf build/iso/boot/
	cp limine.conf build/iso/boot/limine/
	cp vendor/limine/limine-bios.sys vendor/limine/limine-bios-cd.bin vendor/limine/limine-uefi-cd.bin build/iso/boot/limine/
	cp vendor/limine/BOOTX64.EFI build/iso/EFI/BOOT/
	xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label build/iso -o $@ 2>build/iso.log
	vendor/limine/limine bios-install $@

run: all
	$(QEMU) -cdrom build/kristal.iso

test: all
	@status=0; timeout 15s $(QEMU) -cdrom build/kristal.iso > build/serial.log 2>&1 || status=$$?; cat build/serial.log; test $$status -eq 33
	grep -q 'ELF loaded' build/serial.log

feasibility:
	scripts/feasibility.sh

clean:
	rm -rf build
