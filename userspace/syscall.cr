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
  def self.invoke(number : UInt64, a : UInt64, b : UInt64, c : UInt64, d : UInt64, e : UInt64, f : UInt64) : Int64
    result = 0_i64
    asm("int $$0x80" : "={rax}"(result) : "{rax}"(number), "{rdi}"(a), "{rsi}"(b), "{rdx}"(c), "{r10}"(d), "{r8}"(e), "{r9}"(f) : "memory" : "volatile")
    result
  end
end

module User
  def self.write(text : String)
    message = uninitialized ABI::Message
    clear(pointerof(message))
    message.tag = Op::WRITE
    length = text.bytesize.to_u64!
    message.length = length
    exit(1_u64) if call(1_u64, pointerof(message), text.to_unsafe, 0_u64) != 0 || message.tag != length
  end

  def self.clear(message : ABI::Message*)
    memset(message.as(UInt8*), 0, 64_u64)
  end

  def self.invoke(number : UInt64, a : UInt64 = 0_u64, b : UInt64 = 0_u64, c : UInt64 = 0_u64, d : UInt64 = 0_u64, e : UInt64 = 0_u64, f : UInt64 = 0_u64) : Int64
    Syscall.invoke(number, a, b, c, d, e, f)
  end

  def self.call(handle : UInt64, message : ABI::Message*, buffer : UInt8*, capacity : UInt64) : Int64
    invoke(Sys::CALL, handle, message.address, buffer.address, capacity)
  end

  def self.receive(handle : UInt64, message : ABI::Message*, buffer : UInt8*, capacity : UInt64) : Int64
    invoke(Sys::RECEIVE, handle, message.address, buffer.address, capacity)
  end

  def self.reply(handle : UInt64, pid : UInt64, message : ABI::Message*, buffer : UInt8*) : Int64
    invoke(Sys::REPLY, handle, pid, message.address, buffer.address)
  end

  def self.wait(pid : UInt64, status : UInt64*) : Int64
    invoke(Sys::WAIT, pid, status.address)
  end

  def self.sleep(ticks : UInt64)
    exit(1_u64) if invoke(Sys::SLEEP, ticks) != 0
  end

  def self.exit(status : UInt64) : NoReturn
    invoke(Sys::EXIT, status)
    while true
      asm("ud2" ::: "memory" : "volatile")
    end
  end
end
