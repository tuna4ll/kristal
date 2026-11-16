struct Pointer(T)
  def [](index : Int)
    (self + index.to_i64!).value
  end

  def []=(index : Int, value : T)
    (self + index.to_i64!).value = value
  end
end

class String
  def bytesize : Int32
    @bytesize
  end

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
