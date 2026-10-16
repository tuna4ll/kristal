lib Arch
  fun enter_user(entry : UInt64, stack : UInt64) : NoReturn
  fun read_cr3 : UInt64
  fun write_cr3(root : UInt64)
  fun cpu_load(gdt : UInt64*, idt : UInt64*)
  fun stack_address : UInt64
  fun fault_stack_address : UInt64
  fun interrupt_address(index : UInt64) : UInt64
  fun read_cr2 : UInt64
end

module CPU
  def self.init
    gdt = Memory.alloc
    tss = Memory.alloc
    idt = Memory.alloc
    gdt[1] = 0x00af9a000000ffff_u64
    gdt[2] = 0x00cf92000000ffff_u64
    gdt[3] = 0x00cff2000000ffff_u64
    gdt[4] = 0x00affa000000ffff_u64
    base = tss.address
    gdt[5] = 103_u64 | ((base & 0xffffff) << 16) | (0x89_u64 << 40) | (((base >> 24) & 255) << 56)
    gdt[6] = base >> 32
    bytes = tss.as(UInt8*)
    store64(bytes, 4, Arch.stack_address)
    store64(bytes, 36, Arch.fault_stack_address)
    bytes[102] = 104_u8
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

fun exception(frame : UInt64*) : NoReturn
  Serial.write("[Kristal] Exception vector=")
  Serial.hex(frame[0])
  Serial.write(" error=")
  Serial.hex(frame[1])
  Serial.write(" rip=")
  Serial.hex(frame[2])
  Serial.write(" cs=")
  Serial.hex(frame[3])
  Serial.write(" cr2=")
  Serial.hex(Arch.read_cr2)
  Serial.write("\n")
  Arch.debug_exit(0x11_u32)
  Arch.stop
end
