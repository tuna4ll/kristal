require "../runtime/base"
require "../runtime/abi"

lib Syscall
  fun invoke(number : UInt64, arg1 : UInt64, arg2 : UInt64) : Int64
end

module User
  def self.write(text : String)
    length = text.bytesize.to_u64!
    exit(1_u64) if Syscall.invoke(1_u64, text.to_unsafe.address, length) != length
  end

  def self.clear(message : ABI::Message*)
    p = message.as(UInt64*)
    i = 0
    while i < 8
      p[i] = 0_u64
      i = i &+ 1
    end
  end

  def self.call(handle : UInt64, message : ABI::Message*) : Int64
    Syscall.invoke(3_u64, handle, message.address)
  end

  def self.receive(handle : UInt64, message : ABI::Message*) : Int64
    Syscall.invoke(4_u64, handle, message.address)
  end

  def self.reply(handle : UInt64, message : ABI::Message*) : Int64
    Syscall.invoke(5_u64, handle, message.address)
  end

  def self.sleep(ticks : UInt64)
    exit(1_u64) if Syscall.invoke(6_u64, ticks, 0_u64) != 0
  end

  def self.exit(status : UInt64) : NoReturn
    Syscall.invoke(2_u64, status, 0_u64)
    while true
      asm("ud2" ::: "memory" : "volatile")
    end
  end
end
