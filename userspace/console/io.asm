bits 64
default rel
section .text
global port_out, port_in, font_address
port_out:
    mov dx, di
    mov eax, esi
    out dx, al
    ret
port_in:
    mov dx, di
    xor eax, eax
    in al, dx
    ret
font_address:
    lea rax, [font]
    ret
section .rodata
font: incbin "kernel/console/font.bin"
section .note.GNU-stack noalloc noexec nowrite progbits
