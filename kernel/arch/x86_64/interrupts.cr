module Frame
  RAX    = 14
  VECTOR = 15
  ERROR  = 16
  RIP    = 17
  CS     = 18
  FLAGS  = 19
  RSP    = 20
  SS     = 21
  WORDS  = 22
end

module Timer
  @@ticks = 0_u64

  def self.pic(port : UInt16, value : UInt8)
    Arch.port_out(port, value)
    Arch.port_out(0x80_u16, 0_u8)
  end

  def self.init
    pic(0x21_u16, 0xff_u8)
    pic(0xa1_u16, 0xff_u8)
    pic(0x20_u16, 0x11_u8)
    pic(0xa0_u16, 0x11_u8)
    pic(0x21_u16, 0x20_u8)
    pic(0xa1_u16, 0x28_u8)
    pic(0x21_u16, 4_u8)
    pic(0xa1_u16, 2_u8)
    pic(0x21_u16, 1_u8)
    pic(0xa1_u16, 1_u8)
    pic(0x21_u16, 0xfe_u8)
    pic(0xa1_u16, 0xff_u8)
    # PIT channel 0, mode 2; 1193182 / 11932 is approximately 100 Hz.
    Arch.port_out(0x43_u16, 0x34_u8)
    Arch.port_out(0x40_u16, 0x9c_u8)
    Arch.port_out(0x40_u16, 0x2e_u8)
  end

  def self.interrupt(vector : UInt64)
    if vector == 39
      Arch.port_out(0x20_u16, 0x0b_u8)
      return if Arch.port_in(0x20_u16) & 0x80 == 0
    elsif vector == 47
      Arch.port_out(0xa0_u16, 0x0b_u8)
      if Arch.port_in(0xa0_u16) & 0x80 == 0
        Arch.port_out(0x20_u16, 0x20_u8)
        return
      end
    end
    @@ticks = @@ticks &+ 1 if vector == 32
    Arch.port_out(0xa0_u16, 0x20_u8) if vector >= 40
    Arch.port_out(0x20_u16, 0x20_u8)
  end

  def self.ticks : UInt64
    @@ticks
  end
end

fun interrupt_dispatch(frame : UInt64*) : UInt64*
  vector = frame[Frame::VECTOR]
  if vector == 128
    return Syscalls.dispatch(frame)
  elsif vector >= 32 && vector < 48
    Timer.interrupt(vector)
  else
    return exception(frame)
  end
  frame
end
