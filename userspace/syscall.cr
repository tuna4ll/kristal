require "../runtime/base"

lib Syscall
  fun invoke(number : UInt64, arg1 : UInt64, arg2 : UInt64) : Int64
end

module User
  def self.write(text : String)
    length = text.bytesize.to_u64!
    exit(1_u64) if Syscall.invoke(1_u64, text.to_unsafe.address, length) != length
  end

  def self.exit(status : UInt64) : NoReturn
    Syscall.invoke(2_u64, status, 0_u64)
    while true
      asm("ud2" ::: "memory" : "volatile")
    end
  end
end
