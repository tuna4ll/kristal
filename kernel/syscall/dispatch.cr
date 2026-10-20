module Syscalls
  @@seen = false

  def self.dispatch(frame : UInt64*) : UInt64*
    panic("syscall privilege") if frame[Frame::CS] != 0x23 || frame[Frame::SS] != 0x1b || frame[Frame::FLAGS] & 0x3000 != 0
    unless @@seen
      Console.write("[Kristal] Syscall from CPL 3\n")
      @@seen = true
    end
    if frame[Frame::RAX] == 2
      return Processes.exit(frame[9])
    elsif frame[Frame::RAX] == 3
      return IPC.call(frame, frame[9], frame[8])
    elsif frame[Frame::RAX] == 4
      return IPC.receive(frame, frame[9], frame[8])
    elsif frame[Frame::RAX] == 5
      return IPC.reply(frame, frame[9], frame[8])
    elsif frame[Frame::RAX] == 6
      return Processes.sleep(frame, frame[9])
    elsif frame[Frame::RAX] == 7
      frame[Frame::RAX] = Display.info(frame[9]).to_u64!
    elsif frame[Frame::RAX] == 8
      return Processes.wait(frame, frame[9], frame[8])
    else
      frame[Frame::RAX] = 0_u64 &- 38
    end
    frame
  end
end
