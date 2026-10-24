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

fun memset(dest : UInt8*, value : Int32, size : UInt64) : UInt8*
  asm("movq $0, %rdi; movl $1, %eax; movq $2, %rcx; rep stosb" :: "r"(dest), "r"(value), "r"(size) : "rdi", "rax", "rcx", "memory" : "volatile")
  dest
end

fun memcpy(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  asm("movq $0, %rdi; movq $1, %rsi; movq $2, %rcx; rep movsb" :: "r"(dest), "r"(src), "r"(size) : "rdi", "rsi", "rcx", "memory" : "volatile")
  dest
end
