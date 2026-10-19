lib Arch
  fun resume(frame : UInt64*) : NoReturn
  fun idle : NoReturn
  fun wait_interrupt
  fun invalidate(address : UInt64)
  fun read_cr3 : UInt64
  fun write_cr3(root : UInt64)
  fun cpu_load(gdt : UInt64*, idt : UInt64*)
  fun stack_address : UInt64
  fun fault_stack_address : UInt64
  fun interrupt_address(index : UInt64) : UInt64
  fun read_cr2 : UInt64
  fun tss_address : UInt8*
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
