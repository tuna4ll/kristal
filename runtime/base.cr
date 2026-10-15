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
