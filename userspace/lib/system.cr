module Syscall
  def self.invoke(number : UInt64, a : UInt64, b : UInt64, c : UInt64, d : UInt64, e : UInt64, f : UInt64) : Int64
    result = 0_i64
    asm("int $$0x80" : "={rax}"(result) : "{rax}"(number), "{rdi}"(a), "{rsi}"(b), "{rdx}"(c), "{r10}"(d), "{r8}"(e), "{r9}"(f) : "memory" : "volatile")
    result
  end
end

module System
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

  def self.endpoint : Int64
    invoke(Sys::ENDPOINT)
  end

  def self.copy(handle : UInt64, rights : UInt64) : Int64
    invoke(Sys::COPY, handle, rights)
  end

  def self.close(handle : UInt64) : Int64
    invoke(Sys::CLOSE, handle)
  end

  def self.fork : Int64
    invoke(Sys::FORK)
  end

  def self.exec(image : UInt8*, length : UInt64, argv : UInt8**, envp : UInt8**, data : UInt8*, size : UInt64) : Int64
    invoke(Sys::EXEC, image.address, length, argv.address, envp.address, data.address, size)
  end

  def self.wait(pid : UInt64, status : UInt64*) : Int64
    invoke(Sys::WAIT, pid, status.address)
  end

  def self.map(address : UInt64, length : UInt64, flags : UInt64) : Int64
    invoke(Sys::MAP, address, length, flags)
  end

  def self.unmap(address : UInt64, length : UInt64) : Int64
    invoke(Sys::UNMAP, address, length)
  end

  def self.device(kind : UInt64, info : UInt8*) : Int64
    invoke(Sys::DEVICE, kind, info.address)
  end

  def self.drop(mask : UInt64) : Int64
    invoke(Sys::DROP, mask)
  end

  def self.sleep(ticks : UInt64) : Int64
    invoke(Sys::SLEEP, ticks)
  end

  def self.exit(status : UInt64) : NoReturn
    invoke(Sys::EXIT, status)
    while true
      asm("ud2" ::: "memory" : "volatile")
    end
  end
end
