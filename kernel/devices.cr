module Devices
  @@irqs = uninitialized UInt64[16]
  @@initrd = 0_u64
  @@initrd_size = 0_u64

  def self.initrd(file : UInt64*)
    @@initrd = file[1]
    @@initrd_size = file[2]
  end

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
    elsif kind == Device::INITRD
      return map_initrd(frame, address)
    end
    Syscalls.fail(frame, Errno::EINVAL)
  end

  def self.map_initrd(frame : UInt64*, address : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::ENODEV) if @@initrd == 0
    root = Processes.root
    start = @@initrd & ~4095_u64
    length = ((@@initrd & 4095) &+ @@initrd_size &+ 4095) & ~4095_u64
    if Memory.lookup(root, Layout::INITRD) == 0
      return Syscalls.fail(frame, Errno::ENOMEM) unless Memory.reserve((length >> 21) &+ 4)
      offset = 0_u64
      while offset < length
        Memory.map(root, Layout::INITRD &+ offset, Memory.physical(start &+ offset), Memory::NX | Memory::BORROWED)
        offset = offset &+ Memory::PAGE
      end
    end
    region = uninitialized ABI::Region
    region.address = Layout::INITRD &+ (@@initrd & 4095)
    region.length = @@initrd_size
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(root, address, pointerof(region).as(UInt8*), 16_u64, true)
    frame[Frame::RAX] = 0_u64
    frame
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
