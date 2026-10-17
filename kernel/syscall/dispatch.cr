module Syscalls
  @@seen = false

  def self.dispatch(frame : UInt64*)
    panic("syscall privilege") if frame[Frame::CS] != 0x23 || frame[Frame::SS] != 0x1b || frame[Frame::FLAGS] & 0x3000 != 0
    unless @@seen
      Console.write("[Kristal] Syscall from CPL 3\n")
      @@seen = true
    end
    if frame[Frame::RAX] == 1
      address = frame[9]
      length = frame[8]
      if length > 4096
        frame[Frame::RAX] = 0_u64 &- 22
        return
      end
      if length == 0
        frame[Frame::RAX] = 0_u64
        return
      end
      if address >= 0x80000000 || length > 0x80000000_u64 &- address
        frame[Frame::RAX] = 0_u64 &- 14
        return
      end
      page = address & ~4095_u64
      last = (address &+ length &- 1) & ~4095_u64
      while page <= last
        if Memory.lookup(page) == 0
          frame[Frame::RAX] = 0_u64 &- 14
          return
        end
        page = page &+ 4096
      end
      p = Pointer(UInt8).new(address)
      i = 0_u64
      while i < length
        Console.byte(p[i])
        i = i &+ 1
      end
      frame[Frame::RAX] = length
    elsif frame[Frame::RAX] == 2
      Console.write("[Kristal] Userspace exited status=")
      Console.hex(frame[9])
      Console.write("\n")
      Console.write("[Kristal] Timer ticks=")
      Console.hex(Timer.ticks)
      Console.write("\n")
      Arch.debug_exit(frame[9] == 0 ? 0x10_u32 : 0x11_u32)
      Arch.stop
    else
      frame[Frame::RAX] = 0_u64 &- 38
    end
  end
end
