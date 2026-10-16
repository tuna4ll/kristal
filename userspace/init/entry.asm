bits 64
section .text
global _user_start
extern user_main
_user_start:
    xor ebp, ebp
    call user_main
    ud2
section .note.GNU-stack noalloc noexec nowrite progbits
section .text
global invoke
invoke:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    int 0x80
    ret
