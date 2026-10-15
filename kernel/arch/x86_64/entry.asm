bits 64
default rel
section .limine_requests_start
    dq 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf
    dq 0x785c6ed015d3e316, 0x181e920a7852b9d9
section .limine_requests
align 8
base_revision: dq 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3
%macro request 3
%1: dq 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, %2, %3, 0, 0
%endmacro
request hhdm, 0x48dcf1cb8ad2b852, 0x63984e959a98244b
request memmap, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62
request modules, 0x3e7e279702be32af, 0xca1c4f3bd1280cee
section .limine_requests_end
    dq 0xadc0e0531bb10d03, 0x9572709f31764c62
section .bss
align 16
stack: resb 65536
stack_top:
section .text
global _start, port_out, port_in, stop, debug_exit
extern kernel_main
_start:
    cli
    cld
    lea rsp, [stack_top]
    xor ebp, ebp
    cmp qword [base_revision + 16], 0
    jne stop
    mov rdi, [hhdm + 40]
    mov rsi, [memmap + 40]
    mov rdx, [modules + 40]
    call kernel_main
stop:
    cli
    hlt
    jmp stop
port_out:
    mov dx, di
    mov eax, esi
    out dx, al
    ret
debug_exit:
    mov dx, 0xf4
    mov eax, edi
    out dx, eax
    ret
port_in:
    mov dx, di
    xor eax, eax
    in al, dx
    ret
section .note.GNU-stack noalloc noexec nowrite progbits
