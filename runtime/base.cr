struct Pointer(T)
  def [](index : Int)
    (self + index.to_i64!).value
  end

  def []=(index : Int, value : T)
    (self + index.to_i64!).value = value
  end
end

class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
end

struct Int
  def >>(count : Int)
    unsafe_shr(count)
  end

  def <<(count : Int)
    unsafe_shl(count)
  end

  def ~
    self ^ ((self &* 0) &- 1)
  end
end

# Volatile stores prevent LLVM from lowering this loop to a recursive memset.
fun memset(dest : UInt8*, value : Int32, size : UInt64) : UInt8*
  i = 0_u64
  while i < size
    asm("movb $1, ($0)" :: "r"(dest + i.to_i64!), "r"(value.to_u8!) : "memory" : "volatile")
    i = i &+ 1
  end
  dest
end
