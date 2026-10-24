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
  @@pitch = 0_u64
  @@color = 0_u32
  @@columns = 0_u64
  @@rows = 0_u64
  @@column = 0_u64
  @@row = 0_u64
  @@cells = uninitialized UInt8[65536]

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
    @@pitch = pitch
    @@color = (170_u32 << red) | (170_u32 << green) | (170_u32 << blue)
    @@columns = width >> 3
    @@rows = height >> 4
    @@rows = 65536_u64.unsafe_div(@@columns) if @@columns &* @@rows > 65536
    memset(cells, 32, @@columns &* @@rows)
    y = 0_u64
    while y < height
      memset(Pointer(UInt8).new(address &+ (y &* pitch)), 0, width << 2)
      y = y &+ 1
    end
    @@column = 0_u64
    @@row = 0_u64
    cursor(true)
    true
  end

  def self.cells : UInt8*
    pointerof(@@cells).as(UInt8*)
  end

  def self.draw(column : UInt64, row : UInt64, inverse : Bool)
    font = Arch.font_address + (cells[row &* @@columns &+ column].to_i64! &* 16)
    y = 0_u64
    while y < 16
      bits = font[y]
      bits = ~bits if inverse
      line = Pointer(UInt32).new(@@address &+ (((row << 4) &+ y) &* @@pitch) &+ (column << 5))
      x = 0_u64
      while x < 8
        line[x] = bits & (128_u8 >> x) != 0 ? @@color : 0_u32
        x = x &+ 1
      end
      y = y &+ 1
    end
  end

  def self.cursor(visible : Bool)
    draw(@@column, @@row, visible) if @@row < @@rows && @@column < @@columns
  end

  def self.newline
    @@column = 0_u64
    @@row = @@row &+ 1
    return if @@row < @@rows
    # scroll the grid and repaint it, the framebuffer is slow to read back
    size = @@columns &* (@@rows &- 1)
    memcpy(cells, cells + @@columns.to_i64!, size)
    memset(cells + size.to_i64!, 32, @@columns)
    @@row = @@rows &- 1
    row = 0_u64
    while row < @@rows
      column = 0_u64
      while column < @@columns
        draw(column, row, false)
        column = column &+ 1
      end
      row = row &+ 1
    end
  end

  def self.byte(value : UInt8)
    return if @@address == 0
    cursor(false)
    put(value)
    cursor(true)
  end

  def self.put(value : UInt8)
    if value == 10
      newline
    elsif value == 13
      @@column = 0_u64
    elsif value == 8
      @@column = @@column &- 1 if @@column != 0
    elsif value == 9
      put(32_u8)
      while @@column & 7 != 0
        put(32_u8)
      end
    elsif value >= 32 && value != 127
      value = 63_u8 if value > 126
      newline if @@column >= @@columns
      cells[@@row &* @@columns &+ @@column] = value
      draw(@@column, @@row, false)
      @@column = @@column &+ 1
    end
  end
end
