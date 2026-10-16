lib Arch
  fun font_address : UInt8*
end

module Framebuffer
  @@address = 0_u64
  @@width = 0_u64
  @@height = 0_u64
  @@pitch = 0_u64
  @@color = 0_u32
  @@x = 0_u64
  @@y = 0_u64

  def self.init(response : UInt64*)
    return if response.address == 0 || response[1] == 0
    fb = Pointer(UInt64).new(Pointer(UInt64).new(response[2])[0])
    info = fb.as(UInt8*)
    return if info[32] != 32 || info[33] != 0 || info[34] != 1
    return if info[35] != 8 || info[37] != 8 || info[39] != 8
    red = info[36]
    green = info[38]
    blue = info[40]
    return if red > 24 || green > 24 || blue > 24
    r = 255_u32 << red
    g = 255_u32 << green
    b = 255_u32 << blue
    return if r & g != 0 || r & b != 0 || g & b != 0
    return if fb[0] == 0 || fb[0] & 3 != 0
    return if fb[1] < 64 || fb[1] > 8192 || fb[2] < 64 || fb[2] > 8192
    return if fb[3] < fb[1] &* 4 || fb[3] > 65536 || fb[3] & 3 != 0
    @@address = fb[0]
    @@width = fb[1]
    @@height = fb[2]
    @@pitch = fb[3]
    @@color = (224_u32 << red) | (224_u32 << green) | (224_u32 << blue)
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
    @@x = 16_u64
    @@y = 16_u64
  end

  def self.newline
    @@x = 16_u64
    @@y = @@y &+ 16
    return if @@y &+ 16 <= @@height &- 16
    y = 16_u64
    while y < @@height &- 16
      row = Pointer(UInt32).new(@@address &+ (y &* @@pitch))
      source = Pointer(UInt32).new(@@address &+ ((y &+ 16) &* @@pitch))
      x = 16_u64
      while x < @@width &- 16
        row[x] = y &+ 16 < @@height &- 16 ? source[x] : 0_u32
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
      @@x = 16_u64
      return
    end
    value = 63_u8 if value < 32 || value > 126
    newline if @@x &+ 16 > @@width &- 16
    font = Arch.font_address + (value.to_i64! &* 8)
    y = 0_u64
    while y < 16
      bits = font[y >> 1]
      row = Pointer(UInt32).new(@@address &+ ((@@y &+ y) &* @@pitch))
      x = 0_u64
      while x < 16
        row[@@x &+ x] = bits & (1_u8 << (x >> 1)) != 0 ? @@color : 0_u32
        x = x &+ 1
      end
      y = y &+ 1
    end
    @@x = @@x &+ 16
  end
end
