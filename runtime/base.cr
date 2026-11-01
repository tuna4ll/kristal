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

fun memmove(dest : UInt8*, src : UInt8*, size : UInt64) : UInt8*
  return memcpy(dest, src, size) if dest.address <= src.address || dest.address >= src.address &+ size
  asm("movq $0, %rdi; movq $1, %rsi; movq $2, %rcx; std; rep movsb; cld" :: "r"(dest + (size &- 1).to_i64!), "r"(src + (size &- 1).to_i64!), "r"(size) : "rdi", "rsi", "rcx", "memory" : "volatile")
  dest
end

fun memcmp(a : UInt8*, b : UInt8*, size : UInt64) : Int32
  i = 0_u64
  while i < size
    return a[i].to_i32! &- b[i].to_i32! if a[i] != b[i]
    i = i &+ 1
  end
  0
end

# llvm turns plain scanning loops into calls to this
fun strlen(text : UInt8*) : UInt64
  size = 0_u64
  asm("" ::: "memory" : "volatile")
  while text[size] != 0
    size = size &+ 1
  end
  size
end
