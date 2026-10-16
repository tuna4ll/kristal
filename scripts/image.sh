#!/bin/sh
set -eu
kernel=$1
user=$2
output=$3
stage="${output%.iso}.root"
mkdir -p "$stage/boot/limine" "$stage/EFI/BOOT"
cp "$kernel" "$stage/boot/kernel.elf"
cp "$user" "$stage/boot/init.elf"
cp limine.conf "$stage/boot/limine/"
cp vendor/limine/limine-bios.sys vendor/limine/limine-bios-cd.bin vendor/limine/limine-uefi-cd.bin "$stage/boot/limine/"
cp vendor/limine/BOOTX64.EFI "$stage/EFI/BOOT/"
xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label "$stage" -o "$output"
vendor/limine/limine bios-install "$output"
