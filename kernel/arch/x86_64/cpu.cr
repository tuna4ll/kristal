module Arch
  def self.port_out(port : UInt16, value : UInt8)
    asm("outb %al, %dx" :: "{dx}"(port), "{al}"(value) :: "volatile")
  end

  def self.port_in(port : UInt16) : UInt8
    value = 0_u8
    asm("inb %dx, %al" : "={al}"(value) : "{dx}"(port) :: "volatile")
    value
  end

  def self.debug_exit(value : UInt32)
    asm("outl %eax, %dx" :: "{dx}"(0xf4_u16), "{eax}"(value) :: "volatile")
  end

  def self.stop : NoReturn
    while true
      asm("cli; hlt" :::: "volatile")
    end
  end

  def self.resume(frame : UInt64*) : NoReturn
    asm("mov $0, %rsp; mov $$0x1b, %ax; mov %ax, %ds; mov %ax, %es; jmp interrupt_return" :: "r"(frame) : "rax" : "volatile")
    stop
  end

  def self.idle : NoReturn
    asm("lea stack_top(%rip), %rsp; xor %ebp, %ebp; call idle_main" :::: "volatile")
    stop
  end

  def self.wait_interrupt
    asm("sti; hlt; cli" ::: "memory" : "volatile")
  end

  def self.invalidate(address : UInt64)
    asm("invlpg ($0)" :: "r"(address) : "memory" : "volatile")
  end

  def self.read_cr3 : UInt64
    value = 0_u64
    asm("mov %cr3, $0" : "=r"(value) ::: "volatile")
    value
  end

  def self.write_cr3(root : UInt64)
    asm("mov $0, %cr3" :: "r"(root) : "memory" : "volatile")
  end

  def self.read_cr2 : UInt64
    value = 0_u64
    asm("mov %cr2, $0" : "=r"(value) ::: "volatile")
    value
  end

  def self.stack_address : UInt64
    value = 0_u64
    asm("lea stack_top(%rip), $0" : "=r"(value))
    value
  end

  def self.fault_stack_address : UInt64
    value = 0_u64
    asm("lea fault_stack_top(%rip), $0" : "=r"(value))
    value
  end

  def self.tss_address : UInt8*
    value = 0_u64
    asm("lea tss(%rip), $0" : "=r"(value))
    Pointer(UInt8).new(value)
  end

  # every stub in entry.cr is padded to 16 bytes
  def self.interrupt_address(index : UInt64) : UInt64
    value = 0_u64
    asm("lea interrupt_stubs(%rip), $0" : "=r"(value))
    value &+ (index << 4)
  end

  # fpu and simd state is not switched yet, so those instructions trap
  def self.cpu_load(gdt : UInt64*, idt : UInt64*)
    asm("
      sub $$16, %rsp
      movw $$55, (%rsp)
      mov $0, 2(%rsp)
      lgdt (%rsp)
      movw $$4095, (%rsp)
      mov $1, 2(%rsp)
      lidt (%rsp)
      add $$16, %rsp
      pushq $$8
      lea 1f(%rip), %rax
      push %rax
      lretq
    1:
      mov $$16, %ax
      mov %ax, %ds
      mov %ax, %es
      mov %ax, %ss
      xor %eax, %eax
      mov %ax, %fs
      mov %ax, %gs
      mov $$40, %ax
      ltr %ax
      mov $$0xc0000080, %ecx
      rdmsr
      or $$(1 << 11), %eax
      wrmsr
      mov %cr0, %rax
      or $$((1 << 16) | (1 << 3) | (1 << 2)), %rax
      mov %rax, %cr0
    " :: "r"(gdt), "r"(idt) : "rax", "rcx", "rdx", "memory" : "volatile")
  end
end

module CPU
  @@tss = Pointer(UInt8).new(0_u64)

  def self.set_stack(top : UInt64)
    store64(@@tss, 4, top)
  end

  def self.set_io(serial : Bool)
    @@tss[104 &+ (0x3f8 >> 3)] = serial ? 0_u8 : 0xff_u8
  end

  def self.init
    gdt = Memory.alloc
    tss = Arch.tss_address
    idt = Memory.alloc
    gdt[1] = 0x00af9a000000ffff_u64
    gdt[2] = 0x00cf92000000ffff_u64
    gdt[3] = 0x00cff2000000ffff_u64
    gdt[4] = 0x00affa000000ffff_u64
    base = tss.address
    gdt[5] = 8296_u64 | ((base & 0xffffff) << 16) | (0x89_u64 << 40) | (((base >> 24) & 255) << 56)
    gdt[6] = base >> 32
    bytes = tss.as(UInt8*)
    @@tss = bytes
    store64(bytes, 4, Arch.stack_address)
    store64(bytes, 36, Arch.fault_stack_address)
    bytes[102] = 104_u8
    i = 104
    while i <= 8296
      bytes[i] = 0xff_u8
      i = i &+ 1
    end
    i = 0_u64
    while i < 256
      address = Arch.interrupt_address(i)
      ist = i == 8 ? 1_u64 : 0_u64
      gate = i == 128 ? 0xee_u64 : 0x8e_u64
      idt[i &* 2] = (address & 0xffff) | (8_u64 << 16) | (ist << 32) | (gate << 40) | (((address >> 16) & 0xffff) << 48)
      idt[(i &* 2) &+ 1] = address >> 32
      i = i &+ 1
    end
    Arch.cpu_load(gdt, idt)
  end
end

def exception(frame : UInt64*) : UInt64*
  Console.write("[Kristal] Exception vector=")
  Console.hex(frame[Frame::VECTOR])
  Console.write(" error=")
  Console.hex(frame[Frame::ERROR])
  Console.write(" rip=")
  Console.hex(frame[Frame::RIP])
  Console.write(" cs=")
  Console.hex(frame[Frame::CS])
  Console.write(" cr2=")
  Console.hex(Arch.read_cr2)
  Console.write("\n")
  vector = frame[Frame::VECTOR]
  if frame[Frame::CS] == 0x23 && vector != 2 && vector != 8 && vector != 18
    return Processes.exit(128_u64 &+ vector)
  end
  Arch.debug_exit(0x11_u32)
  Arch.stop
end
