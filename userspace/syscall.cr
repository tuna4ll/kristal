require "../runtime/base"
require "../runtime/abi"

fun user_entry_code
  asm("
    .pushsection .text
    .globl _user_start
    _user_start:
      xor %ebp, %ebp
      call user_main
      ud2
    .popsection
  " :::: "volatile")
end

module Syscall
  def self.invoke(number : UInt64, arg1 : UInt64, arg2 : UInt64) : Int64
    result = 0_i64
    asm("int $$0x80" : "={rax}"(result) : "{rax}"(number), "{rdi}"(arg1), "{rsi}"(arg2) : "memory" : "volatile")
    result
  end
end

module User
  def self.write(text : String)
    message = uninitialized ABI::Message
    clear(pointerof(message))
    done = 0_u64
    length = text.bytesize.to_u64!
    while done < length
      count = length &- done
      count = 48_u64 if count > 48
      message.kind = 1_u64
      message.size = count
      bytes = pointerof(message).as(UInt8*) + 16_i64
      i = 0_u64
      while i < count
        bytes[i] = text.to_unsafe[done &+ i]
        i = i &+ 1
      end
      exit(1_u64) if call(1_u64, pointerof(message)) != 0 || message.kind != 0 || message.size != count
      done = done &+ count
    end
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

  def self.wait(pid : UInt64, status : UInt64*) : Int64
    Syscall.invoke(8_u64, pid, status.address)
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
