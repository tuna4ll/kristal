require "../runtime/base"

lib Arch
  fun port_out(port : UInt16, value : UInt8)
  fun port_in(port : UInt16) : UInt8
  fun debug_exit(value : UInt32)
  fun stop : NoReturn
end

require "./elf/loader"
require "./memory/pages"
require "./arch/x86_64/cpu"

def store64(p : UInt8*, offset : Int32, value : UInt64)
  i = 0
  while i < 8
    p[offset &+ i] = (value >> (i &* 8)).to_u8!
    i = i &+ 1
  end
end

def panic(message : String) : NoReturn
  Serial.write("[Kristal] Panic: ")
  Serial.write(message)
  Serial.write("\n")
  Arch.debug_exit(0x11_u32)
  Arch.stop
end

module Serial
  def self.hex(value : UInt64)
    digits = "0123456789abcdef".to_unsafe
    shift = 60
    while shift >= 0
      byte(digits[(value >> shift) & 15])
      shift = shift &- 4
    end
  end

  def self.init
    Arch.port_out(0x3f9_u16, 0_u8)
    Arch.port_out(0x3fb_u16, 0x80_u8)
    Arch.port_out(0x3f8_u16, 1_u8)
    Arch.port_out(0x3f9_u16, 0_u8)
    Arch.port_out(0x3fb_u16, 3_u8)
    Arch.port_out(0x3fa_u16, 0xc7_u8)
    Arch.port_out(0x3fc_u16, 0x0b_u8)
  end

  def self.byte(value : UInt8)
    while Arch.port_in(0x3fd_u16) & 0x20 == 0
    end
    Arch.port_out(0x3f8_u16, value)
  end

  def self.write(text : String)
    p = text.to_unsafe
    i = 0
    while p[i] != 0
      byte(p[i])
      i = i &+ 1
    end
  end
end

fun kernel_main(hhdm : UInt64*, memmap : UInt64*, modules : UInt64*) : NoReturn
  Serial.init
  Serial.write("[Kristal] Booting...\n")
  if hhdm.address == 0 || memmap.address == 0
    Serial.write("[Kristal] Missing Limine response\n")
    Arch.stop
  end
  Memory.init(hhdm[1], memmap)
  CPU.init
  Memory.address_space
  Serial.write("[Kristal] Kernel initialized\n")
  panic("missing userspace module") if modules.address == 0 || modules[1] != 1
  file = Pointer(UInt64).new(Pointer(UInt64).new(modules[2])[0])
  Serial.write("[Kristal] Loading userspace ELF\n")
  entry = ELF.load(Pointer(UInt8).new(file[1]), file[2])
  panic("ELF mapping self test") if Memory.lookup(entry) & Memory::NX != 0
  Serial.write("[Kristal] Entering Ring 3\n")
  Arch.enter_user(entry, ELF::STACK)
end
