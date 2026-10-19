fun screen_font_data
  asm(".pushsection .rodata; screen_font: .incbin \"kernel/console/font.bin\"; .popsection" :::: "volatile")
end

module Arch
  def self.font_address : UInt8*
    value = 0_u64
    asm("lea screen_font(%rip), $0" : "=r"(value))
    Pointer(UInt8).new(value)
  end
end

module Screen
  # Modern DOS 8x16, CC0: https://github.com/susam/pcface/tree/master/out/moderndos-8x16
  @@address = 0_u64
  @@width = 0_u64
  @@height = 0_u64
  @@pitch = 0_u64
  @@color = 0_u32
  @@x = 0_u64
  @@y = 0_u64

  def self.init(address : UInt64, width : UInt64, height : UInt64, pitch : UInt64, red : UInt64, green : UInt64, blue : UInt64) : Bool
    return false if red > 24 || green > 24 || blue > 24
    r = 255_u32 << red
    g = 255_u32 << green
    b = 255_u32 << blue
    return false if r & g != 0 || r & b != 0 || g & b != 0
    return false if address == 0 || address & 3 != 0
    return false if width < 64 || width > 8192 || height < 64 || height > 8192
    return false if pitch < width &* 4 || pitch > 65536 || pitch & 3 != 0
    return false if pitch &* height > 64_u64 << 20
    @@address = address
    @@width = width & ~7_u64
    @@height = height & ~15_u64
    @@pitch = pitch
    @@color = (170_u32 << red) | (170_u32 << green) | (170_u32 << blue)
    y = 0_u64
    while y < @@height
      row = Pointer(UInt32).new(@@address &+ (y &* @@pitch))
      x = 0_u64
      while x < @@width
        row[x] = 0_u32
        x = x &+ 1
      end
      y = y &+ 1
    end
    @@x = 0_u64
    @@y = 0_u64
    true
  end

  def self.newline
    @@x = 0_u64
    @@y = @@y &+ 16
    return if @@y &+ 16 <= @@height
    y = 0_u64
    while y < @@height
      row = Pointer(UInt32).new(@@address &+ (y &* @@pitch))
      source = Pointer(UInt32).new(@@address &+ ((y &+ 16) &* @@pitch))
      x = 0_u64
      while x < @@width
        row[x] = y &+ 16 < @@height ? source[x] : 0_u32
        x = x &+ 1
      end
      y = y &+ 1
    end
    @@y = @@y &- 16
  end

  def self.byte(value : UInt8)
    return if @@address == 0
    if value == 10
      newline
      return
    elsif value == 13
      @@x = 0_u64
      return
    end
    if value == 8
      @@x = @@x &- 8 if @@x >= 8
      return
    elsif value == 9
      spaces = 8_u64 &- ((@@x >> 3) & 7)
      while spaces != 0
        byte(32_u8)
        spaces = spaces &- 1
      end
      return
    end
    return if value < 32 || value == 127
    value = 63_u8 if value > 126
    newline if @@x &+ 8 > @@width
    font = Arch.font_address + (value.to_i64! &* 16)
    y = 0_u64
    while y < 16
      bits = font[y]
      row = Pointer(UInt32).new(@@address &+ ((@@y &+ y) &* @@pitch))
      x = 0_u64
      while x < 8
        row[@@x &+ x] = bits & (128_u8 >> x) != 0 ? @@color : 0_u32
        x = x &+ 1
      end
      y = y &+ 1
    end
    @@x = @@x &+ 8
  end
end
