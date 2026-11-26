SHELL := /bin/sh
LIMINE_COMMIT := aad3edd370955449717a334f0289dee10e2c5f01
MUSL_COMMIT := 0784374d561435f7c787a555aeab8ede699ed298
MUSL := build/musl
QEMU := qemu-system-x86_64 -machine q35 -cpu qemu64,+nx -m 128M -display gtk -vga std -serial stdio -monitor none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 -debugcon file:build/kernel.log
RUNTIME := $(wildcard runtime/*.cr userspace/lib/*.cr) scripts/compile.sh
SBIN := console fs
UTILS := cat echo ls uname wc sleep
BIN := sh selftest $(UTILS)
CBIN := hello sigtest
PROGRAMS := $(SBIN) $(BIN) $(CBIN)

.PHONY: all run test clean feasibility
.SECONDEXPANSION:
.SECONDARY:
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

vendor/musl/configure:
	mkdir -p vendor
	test -d vendor/musl/.git || git clone --depth 1 --branch v1.2.5 https://git.musl-libc.org/git/musl vendor/musl
	test "$$(git -C vendor/musl rev-parse HEAD)" = "$(MUSL_COMMIT)"

# stock musl, its syscall instructions are bounced into the posix layer at run time
$(MUSL)/lib/libc.a: vendor/musl/configure | build
	rm -rf build/musl-build
	mkdir -p build/musl-build
	cd build/musl-build && ../../vendor/musl/configure --prefix=$(CURDIR)/$(MUSL) --target=x86_64-linux-musl --disable-shared CC=clang AR=llvm-ar RANLIB=llvm-ranlib >/dev/null
	$(MAKE) -C build/musl-build install >build/musl.log 2>&1

build/kristal.o: userspace/lib/kristal.cr $(RUNTIME) | build
	scripts/compile.sh $< build/kristal small
	llvm-objcopy --localize-symbol=main $@

$(CBIN:%=build/%.c.o): build/%.c.o: userspace/%/main.c $(MUSL)/lib/libc.a | build
	clang --target=x86_64-linux-musl -nostdinc -isystem $(MUSL)/include -O2 -fno-pie -fno-stack-protector -c $< -o $@

$(CBIN:%=build/%.elf): build/%.elf: build/%.c.o build/kristal.o
	ld.lld -static -nostdlib -z max-page-size=4096 -e _kristal_start $(MUSL)/lib/crt1.o $(MUSL)/lib/crti.o $< build/kristal.o $(MUSL)/lib/libc.a $(MUSL)/lib/crtn.o -o $@
	test -z "$$(nm -u $@ | grep -v ' _DYNAMIC$$')"

build/%.o: userspace/%/main.cr $$(wildcard userspace/%/*.cr) $(RUNTIME) | build
	scripts/compile.sh $< build/$* small

build/%.o: userspace/kristalutils/%/main.cr $(RUNTIME) | build
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
	for name in $(BIN) $(CBIN); do cp build/$$name.elf build/initrd/bin/$$name; done
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
