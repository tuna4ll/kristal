module Syscalls
  @@seen = false

  def self.fail(frame : UInt64*, error : Int64) : UInt64*
    frame[Frame::RAX] = (0_i64 &- error).to_u64!
    frame
  end

  def self.dispatch(frame : UInt64*) : UInt64*
    panic("syscall privilege") if frame[Frame::CS] != 0x23 || frame[Frame::SS] != 0x1b || frame[Frame::FLAGS] & 0x3000 != 0
    unless @@seen
      Console.write("[Kristal] Syscall from CPL 3\n")
      @@seen = true
    end
    number = frame[Frame::RAX]
    a = frame[Frame::RDI]
    b = frame[Frame::RSI]
    if number == Sys::EXIT
      return Processes.exit((a & 255) << 8)
    elsif number == Sys::SLEEP
      return Processes.sleep(frame, a)
    elsif number == Sys::WAIT
      return Processes.wait(frame, a, b)
    elsif number == Sys::CALL
      return IPC.call(frame, a, b)
    elsif number == Sys::RECEIVE
      return IPC.receive(frame, a, b)
    elsif number == Sys::REPLY
      return IPC.reply(frame, a, b)
    elsif number == Sys::DISPLAY
      frame[Frame::RAX] = Display.info(a).to_u64!
    else
      return fail(frame, Errno::ENOSYS)
    end
    frame
  end
end
