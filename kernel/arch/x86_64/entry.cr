# never called, it only places the boot code, limine requests and interrupt stubs
fun kernel_entry_code
  asm("
    .pushsection .limine_requests_start, \"aw\"
    .quad 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf
    .quad 0x785c6ed015d3e316, 0x181e920a7852b9d9
    .popsection

    .pushsection .limine_requests, \"aw\"
    .balign 8
    base_revision: .quad 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3
    .macro request name, a, b
    \\name: .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, \\a, \\b, 0, 0
    .endm
    request hhdm, 0x48dcf1cb8ad2b852, 0x63984e959a98244b
    request memmap, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62
    request modules, 0x3e7e279702be32af, 0xca1c4f3bd1280cee
    request framebuffer, 0x9d5827dcd881dd75, 0xa3148604f6fab11b
    .popsection

    .pushsection .limine_requests_end, \"aw\"
    .quad 0xadc0e0531bb10d03, 0x9572709f31764c62
    .popsection

    .pushsection .bss
    .balign 16
    stack: .skip 65536
    stack_top:
    .balign 16
    fault_stack: .skip 16384
    fault_stack_top:
    .balign 16
    tss: .skip 8297
    .popsection

    .pushsection .text
    .globl _start
    _start:
      cli
      cld
      lea stack_top(%rip), %rsp
      xor %ebp, %ebp
      cmpq $$0, base_revision+16(%rip)
      jne 1f
      mov hhdm+40(%rip), %rdi
      mov memmap+40(%rip), %rsi
      mov modules+40(%rip), %rdx
      mov framebuffer+40(%rip), %rcx
      call kernel_main
    1:
      cli
      hlt
      jmp 1b

    .balign 16
    interrupt_stubs:
    .set vector, 0
    .rept 256
      .balign 16
      .if vector != 8 && vector != 10 && vector != 11 && vector != 12 && vector != 13 && vector != 14 && vector != 17 && vector != 21 && vector != 29 && vector != 30
        pushq $$0
      .endif
      pushq $$vector
      jmp interrupt_entry
      .set vector, vector + 1
    .endr

    interrupt_entry:
      cld
      push %rax
      push %rbx
      push %rcx
      push %rdx
      push %rbp
      push %rdi
      push %rsi
      push %r8
      push %r9
      push %r10
      push %r11
      push %r12
      push %r13
      push %r14
      push %r15
      mov %rsp, %rdi
      and $$-16, %rsp
      call interrupt_dispatch
      mov %rax, %rsp
    interrupt_return:
      pop %r15
      pop %r14
      pop %r13
      pop %r12
      pop %r11
      pop %r10
      pop %r9
      pop %r8
      pop %rsi
      pop %rdi
      pop %rbp
      pop %rdx
      pop %rcx
      pop %rbx
      pop %rax
      add $$16, %rsp
      iretq
    .popsection
  " :::: "volatile")
end
