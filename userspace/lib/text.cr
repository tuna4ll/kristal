module Text
  def self.length(text : UInt8*) : UInt64
    size = 0_u64
    while text[size] != 0
      size = size &+ 1
    end
    size
  end

  def self.equal?(a : UInt8*, b : UInt8*) : Bool
    i = 0_u64
    while a[i] == b[i]
      return true if a[i] == 0
      i = i &+ 1
    end
    false
  end

  def self.equal?(a : UInt8*, b : String) : Bool
    equal?(a, b.to_unsafe)
  end

  # copies a nul terminated string and returns the end of the copy
  def self.copy(target : UInt8*, source : UInt8*) : UInt8*
    i = 0_u64
    while source[i] != 0
      target[i] = source[i]
      i = i &+ 1
    end
    target[i] = 0_u8
    target + i.to_i64!
  end

  def self.decimal(value : UInt64, target : UInt8*) : UInt64
    digits = uninitialized UInt8[20]
    scratch = pointerof(digits).as(UInt8*)
    count = 0_u64
    while true
      scratch[count] = 48_u8 &+ value.unsafe_mod(10_u64).to_u8!
      count = count &+ 1
      value = value.unsafe_div(10_u64)
      break if value == 0
    end
    i = 0_u64
    while i < count
      target[i] = scratch[count &- 1 &- i]
      i = i &+ 1
    end
    target[count] = 0_u8
    count
  end

  def self.octal(text : UInt8*, width : UInt64) : UInt64
    value = 0_u64
    i = 0_u64
    while i < width && text[i] >= 48 && text[i] <= 55
      value = (value << 3) | (text[i] &- 48).to_u64!
      i = i &+ 1
    end
    value
  end
end
