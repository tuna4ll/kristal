# ustar archives, which is what the initrd is
module Tar
  def self.name(header : UInt8*, target : UInt8*)
    cursor = target
    if header[345] != 0
      i = 0_u64
      while i < 155 && header[345 &+ i] != 0
        cursor.value = header[345 &+ i]
        cursor += 1_i64
        i = i &+ 1
      end
      cursor.value = 47_u8
      cursor += 1_i64
    end
    i = 0_u64
    while i < 100 && header[i] != 0
      cursor.value = header[i]
      cursor += 1_i64
      i = i &+ 1
    end
    cursor.value = 0_u8
    size = cursor.address &- target.address
    start = 0_u64
    start = 2_u64 if size >= 2 && target[0] == 46 && target[1] == 47
    start = 1_u64 if size == 1 && target[0] == 46
    size = size &- 1 if size > start && target[size &- 1] == 47
    target[size] = 0_u8
    memcpy(target, target + start.to_i64!, size &- start &+ 1) if start != 0
  end

  def self.each(base : UInt8*, length : UInt64, &)
    offset = 0_u64
    while offset &+ 512 <= length
      header = base + offset.to_i64!
      break if header[0] == 0
      size = Text.octal(header + 124_i64, 12_u64)
      yield header, size, header + 512_i64
      offset = offset &+ 512 &+ ((size &+ 511) & ~511_u64)
    end
  end

  def self.find(base : UInt8*, length : UInt64, path : UInt8*, size : UInt64*) : UInt8*
    path += 1_i64 if path[0] == 47
    buffer = uninitialized UInt8[260]
    name = pointerof(buffer).as(UInt8*)
    each(base, length) do |header, bytes, data|
      name(header, name)
      if Text.equal?(name, path) && (header[156] == 48 || header[156] == 0)
        size.value = bytes
        return data
      end
    end
    Pointer(UInt8).new(0_u64)
  end
end
