require "../runtime/base"

lib Arch
  fun port_out(port : UInt16, value : UInt8)
  fun port_in(port : UInt16) : UInt8
  fun debug_exit(value : UInt32)
  fun stop : NoReturn
end

module Serial
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
  Serial.write("[Kristal] Crystal boot verified\n")
  Arch.debug_exit(0x10_u32)
  Arch.stop
end
