# the posix layer as an object for c programs built against musl
require "../../runtime/base"

lib LibC
  fun memset(dest : UInt8*, value : Int32, size : UInt64) : UInt8*
  fun memcpy(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  fun memmove(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  fun memcmp(a : UInt8*, b : UInt8*, size : UInt64) : Int32
end

def memset(dest : UInt8*, value : Int32, size : UInt64) : UInt8*
  LibC.memset(dest, value, size)
end

def memcpy(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  LibC.memcpy(dest, src, size)
end

def memmove(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  LibC.memmove(dest, src, size)
end

def memcmp(a : UInt8*, b : UInt8*, size : UInt64) : Int32
  LibC.memcmp(a, b, size)
end

require "../../runtime/abi"
require "./system"
require "./text"
require "./posix"
require "./linux"

fun kristal_boot(stack : UInt64*)
  argc = stack[0]
  aux = stack + (argc &+ 2).to_i64!
  while aux.value != 0
    aux += 1_i64
  end
  aux += 1_i64
  data = 0_u64
  size = 0_u64
  phdr = 0_u64
  count = 0_u64
  while aux[0] != 0
    data = aux[1] if aux[0] == Aux::DATA
    size = aux[1] if aux[0] == Aux::SIZE
    phdr = aux[1] if aux[0] == Aux::PHDR
    count = aux[1] if aux[0] == Aux::PHNUM
    aux += 2_i64
  end
  Posix.image(phdr, count)
  Posix.init(Pointer(UInt8).new(data), size)
end

fun kristal_entry_code
  asm("
    .pushsection .text
    .globl _kristal_start, kristal_linux_entry
    # runs before musl's own _start: set up the posix layer, then hand over the untouched stack
    _kristal_start:
      lea kristal_linux_entry(%rip), %rdi
      mov $$19, %eax
      int $$0x80
      mov %rsp, %rdi
      call kristal_boot
      xor %edx, %edx
      jmp _start

    # entered in place of a syscall instruction, rcx holds the return address
    kristal_linux_entry:
      cmp $$15, %rax
      je .Lsigreturn
      sub $$128, %rsp
      push %rcx
      push %rdi
      push %rsi
      push %rdx
      push %r8
      push %r9
      push %r10
      push %rbp
      mov %rsp, %rbp
      and $$-16, %rsp
      sub $$8, %rsp
      push %r9
      mov %r8, %r9
      mov %r10, %r8
      mov %rdx, %rcx
      mov %rsi, %rdx
      mov %rdi, %rsi
      mov %rax, %rdi
      call kristal_syscall
      mov %rbp, %rsp
      pop %rbp
      pop %r10
      pop %r9
      pop %r8
      pop %rdx
      pop %rsi
      pop %rdi
      pop %rcx
      add $$128, %rsp
      jmp *%rcx
    .Lsigreturn:
      mov %rsp, %rdi
      mov $$26, %eax
      int $$0x80
    .popsection
  " :::: "volatile")
end
