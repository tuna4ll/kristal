module Devices
  @@irqs = uninitialized UInt64[16]

  def self.irqs : UInt64*
    pointerof(@@irqs).as(UInt64*)
  end

  def self.allowed?(kind : UInt64) : Bool
    Processes.current.value.devices & kind != 0
  end

  def self.request(frame : UInt64*, kind : UInt64, address : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::EPERM) unless allowed?(kind)
    if kind == Device::DISPLAY
      frame[Frame::RAX] = Display.info(address).to_u64!
      return frame
    end
    Syscalls.fail(frame, Errno::EINVAL)
  end

  def self.drop(frame : UInt64*, mask : UInt64) : UInt64*
    task = Processes.current
    task.value.devices = task.value.devices & ~mask
    CPU.set_io(task.value.devices)
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.line(kind : UInt64) : UInt64
    return 1_u64 if kind == Device::KEYBOARD
    return 4_u64 if kind == Device::SERIAL
    0_u64
  end

  def self.bind(frame : UInt64*, handle : UInt64, kind : UInt64) : UInt64*
    line = line(kind)
    return Syscalls.fail(frame, Errno::EINVAL) if line == 0
    return Syscalls.fail(frame, Errno::EPERM) unless allowed?(kind)
    id = IPC.resolve(Processes.current, handle, IPC::RECEIVE)
    return Syscalls.fail(frame, 0_i64 &- id) if id < 0
    irqs[line] = id.to_u64!
    Timer.unmask(line)
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.unbind(id : UInt64)
    line = 0_u64
    while line < 16
      if irqs[line] == id
        irqs[line] = 0_u64
        Timer.mask(line)
      end
      line = line &+ 1
    end
  end

  # the handler only wakes the driver, reading the device is its job
  def self.interrupt(line : UInt64)
    IPC.notify(irqs[line], 1_u64 << line) if irqs[line] != 0
  end
end
