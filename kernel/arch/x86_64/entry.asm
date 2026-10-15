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
section .bss
align 16
fault_stack: resb 16384
fault_stack_top:
section .text
global read_cr3, write_cr3, cpu_load, stack_address, fault_stack_address, interrupt_address, read_cr2
read_cr3:
    mov rax, cr3
    ret
write_cr3:
    mov cr3, rdi
    ret
read_cr2:
    mov rax, cr2
    ret
stack_address:
    lea rax, [stack_top]
    ret
fault_stack_address:
    lea rax, [fault_stack_top]
    ret
cpu_load:
    sub rsp, 16
    mov word [rsp], 55
    mov [rsp + 2], rdi
    lgdt [rsp]
    mov word [rsp], 4095
    mov [rsp + 2], rsi
    lidt [rsp]
    add rsp, 16
    push 8
    lea rax, [.reload]
    push rax
    retfq
.reload:
    mov ax, 16
    mov ds, ax
    mov es, ax
    mov ss, ax
    xor eax, eax
    mov fs, ax
    mov gs, ax
    mov ax, 40
    ltr ax
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1 << 11
    wrmsr
    mov rax, cr0
    or rax, 1 << 16
    mov cr0, rax
    ret
interrupt_address:
    lea rax, [interrupts]
    mov rax, [rax + rdi * 8]
    ret
extern exception
%assign n 0
%rep 256
isr_%+n:
%if n != 8 && n != 10 && n != 11 && n != 12 && n != 13 && n != 14 && n != 17 && n != 21 && n != 29 && n != 30
    push 0
%endif
    push n
    jmp fault_entry
%assign n n+1
%endrep
fault_entry:
    cld
    mov rdi, rsp
    and rsp, -16
    call exception
    jmp stop
section .rodata
align 8
interrupts:
%assign n 0
%rep 256
    dq isr_%+n
%assign n n+1
%endrep
section .text
global enter_user
enter_user:
    mov ax, 0x1b
    mov ds, ax
    mov es, ax
    push 0x1b
    push rsi
    push 2
    push 0x23
    push rdi
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor edi, edi
    xor ebp, ebp
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    iretq
