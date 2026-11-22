lib Kernel
  # same layout as the linux kernel's struct k_sigaction
  struct Action
    handler : UInt64
    flags : UInt64
    restorer : UInt64
    mask : UInt64
  end
end

module Signals
  COUNT     =         64_u64
  KILL      =          9_u64
  SEGV      =         11_u64
  CHLD      =         17_u64
  STOP      =         19_u64
  IGNORE    =          1_u64
  NODEFER   = 0x40000000_u64
  RESETHAND = 0x80000000_u64
  FIXED     = (1_u64 << (KILL &- 1)) | (1_u64 << (STOP &- 1))
  CONTEXT   = 304_u64
  @@actions = Pointer(Kernel::Action).new(0_u64)

  def self.init
    @@actions = Memory.alloc_pages(Processes::MAX &* COUNT &* 32 >> 12).as(Kernel::Action*)
  end

  def self.action(task : Kernel::Process*, signal : UInt64) : Kernel::Action*
    @@actions + ((task.value.slot &* COUNT) &+ signal &- 1).to_i64!
  end

  def self.bit(signal : UInt64) : UInt64
    1_u64 << (signal &- 1)
  end

  # chld, cont, urg and winch do nothing by default, stopping is not supported yet
  def self.harmless?(signal : UInt64) : Bool
    signal == CHLD || signal == 18 || signal == 23 || signal == 28 || (signal >= STOP && signal <= 22)
  end

  def self.ignored?(task : Kernel::Process*, signal : UInt64) : Bool
    return false if signal == KILL
    handler = action(task, signal).value.handler
    return true if handler == IGNORE
    handler == 0 && (harmless?(signal) || task.value.pid == 1)
  end

  def self.reset(task : Kernel::Process*, exec : Bool)
    signal = 1_u64
    while signal <= COUNT
      entry = action(task, signal)
      memset(entry.as(UInt8*), 0, 32_u64) unless exec && entry.value.handler == IGNORE
      signal = signal &+ 1
    end
    task.value.signals = 0_u64 unless exec
  end

  def self.fork(parent : Kernel::Process*, child : Kernel::Process*)
    memcpy(action(child, 1_u64).as(UInt8*), action(parent, 1_u64).as(UInt8*), COUNT &* 32)
    child.value.mask = parent.value.mask
    child.value.signals = 0_u64
  end

  def self.post(task : Kernel::Process*, signal : UInt64, sender : UInt64)
    state = task.value.state
    return if state == Processes::FREE || state == Processes::ZOMBIE || state == Processes::DEAD
    return if ignored?(task, signal)
    task.value.signals = task.value.signals | bit(signal)
    task.value.sender = sender
    Processes.interrupt(task) if task.value.mask & bit(signal) == 0 || signal == KILL
  end

  def self.kill(frame : UInt64*, target : Int64, signal : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::EINVAL) if signal > COUNT
    sender = Processes.current.value.pid
    found = false
    i = 0_u64
    while i < Processes::MAX
      task = Processes.slot(i)
      hit = false
      if target > 0
        hit = task.value.pid == target.to_u64!
      elsif target == 0
        hit = task.value.group == Processes.current.value.group
      elsif target == -1
        hit = task.value.pid > 1 && task.value.pid != sender
      else
        hit = task.value.group == (0_i64 &- target).to_u64!
      end
      if hit && task.value.state != Processes::FREE && !Processes.exited?(task)
        found = true
        post(task, signal, sender) if signal != 0
      end
      i = i &+ 1
    end
    return Syscalls.fail(frame, Errno::ESRCH) unless found
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.sigaction(frame : UInt64*, signal : UInt64, address : UInt64, previous : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::EINVAL) if signal == 0 || signal > COUNT
    task = Processes.current
    entry = action(task, signal)
    if previous != 0
      return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, previous, entry.as(UInt8*), 32_u64, true)
    end
    if address != 0
      return Syscalls.fail(frame, Errno::EINVAL) if signal == KILL || signal == STOP
      return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, address, entry.as(UInt8*), 32_u64, false)
      entry.value.mask = entry.value.mask & ~FIXED
      task.value.signals = task.value.signals & ~bit(signal) if ignored?(task, signal)
    end
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.sigmask(frame : UInt64*, how : UInt64, address : UInt64, previous : UInt64) : UInt64*
    task = Processes.current
    old = task.value.mask
    if address != 0
      set = 0_u64
      return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, address, pointerof(set).as(UInt8*), 8_u64, false)
      if how == 0
        task.value.mask = old | set
      elsif how == 1
        task.value.mask = old & ~set
      elsif how == 2
        task.value.mask = set
      else
        return Syscalls.fail(frame, Errno::EINVAL)
      end
      task.value.mask = task.value.mask & ~FIXED
    end
    if previous != 0
      return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, previous, pointerof(old).as(UInt8*), 8_u64, true)
    end
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.suspend(frame : UInt64*, address : UInt64) : UInt64*
    task = Processes.current
    set = 0_u64
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, address, pointerof(set).as(UInt8*), 8_u64, false)
    task.value.saved_mask = task.value.mask
    task.value.suspended = 1_u64
    task.value.mask = set & ~FIXED
    frame[Frame::RAX] = (0_i64 &- Errno::EINTR).to_u64!
    return frame if task.value.signals & ~task.value.mask != 0
    task.value.wake_tick = 0xffffffffffffffff_u64
    Processes.block(frame, Processes::SLEEPING)
  end

  def self.store(root : UInt64, address : UInt64, value : UInt64) : Bool
    Memory.copy_user(root, address, pointerof(value).as(UInt8*), 8_u64, true)
  end

  # maps an index of the linux sigcontext gregs array to a frame slot
  def self.slot(index : Int32) : Int32
    return Frame::R8 &- index if index < 8
    return Frame::RDI if index == 8
    return Frame::RSI if index == 9
    return 10 if index == 10
    return 13 if index == 11
    return Frame::RDX if index == 12
    return Frame::RAX if index == 13
    return Frame::RCX if index == 14
    return Frame::RSP if index == 15
    return Frame::RIP if index == 16
    Frame::FLAGS
  end

  # builds a linux style rt_sigframe under the red zone and enters the handler
  def self.enter(task : Kernel::Process*, frame : UInt64*, signal : UInt64, entry : Kernel::Action*) : Bool
    root = task.value.root
    fpu = ((frame[Frame::RSP] &- 128 &- 512) & ~63_u64)
    info = (fpu &- 128) & ~15_u64
    context = (info &- CONTEXT) & ~15_u64
    top = context &- 8
    return false unless Memory.access(root, top, frame[Frame::RSP] &- top, true)
    Processes.fpu_flush(task)
    Memory.copy_user(root, fpu, Processes.fpu(task), 512_u64, true)
    scratch = uninitialized UInt8[432]
    buffer = pointerof(scratch).as(UInt8*)
    memset(buffer, 0, 432_u64)
    words = buffer.as(UInt64*)
    words[2] = 0_u64
    words[3] = 2_u64
    index = 0
    while index < 18
      words[5 &+ index] = frame[slot(index)]
      index = index &+ 1
    end
    words[5 &+ 18] = 0x23_u64 | (0x1b_u64 << 48)
    words[5 &+ 19] = frame[Frame::ERROR]
    words[5 &+ 20] = frame[Frame::VECTOR]
    words[5 &+ 21] = task.value.mask
    words[5 &+ 22] = Arch.read_cr2
    words[5 &+ 23] = fpu
    words[37] = task.value.suspended != 0 ? task.value.saved_mask : task.value.mask
    return false unless Memory.copy_user(root, context, buffer, CONTEXT, true)
    memset(buffer, 0, 128_u64)
    buffer.as(UInt32*)[0] = signal.to_u32!
    words[2] = task.value.sender & 0xffffffff_u64
    words[2] = Arch.read_cr2 if signal == SEGV || signal == 7
    return false unless Memory.copy_user(root, info, buffer, 128_u64, true)
    return false unless store(root, top, entry.value.restorer)
    task.value.mask = task.value.mask | entry.value.mask
    task.value.mask = task.value.mask | bit(signal) if entry.value.flags & NODEFER == 0
    task.value.mask = task.value.mask & ~FIXED
    task.value.suspended = 0_u64
    handler = entry.value.handler
    entry.value.handler = 0_u64 if entry.value.flags & RESETHAND != 0
    frame[Frame::RDI] = signal
    frame[Frame::RSI] = info
    frame[Frame::RDX] = context
    frame[Frame::RAX] = 0_u64
    frame[Frame::RIP] = handler
    frame[Frame::RSP] = top
    frame[Frame::FLAGS] = (frame[Frame::FLAGS] & ~0x500_u64) | 0x200_u64
    true
  end

  def self.sigreturn(frame : UInt64*, context : UInt64) : UInt64*
    task = Processes.current
    scratch = uninitialized UInt8[432]
    buffer = pointerof(scratch).as(UInt8*)
    return Processes.exit(SEGV) unless Memory.copy_user(task.value.root, context, buffer, CONTEXT, false)
    words = buffer.as(UInt64*)
    index = 0
    while index < 17
      frame[slot(index)] = words[5 &+ index]
      index = index &+ 1
    end
    frame[Frame::FLAGS] = (words[5 &+ 17] & 0xcd5_u64) | 0x202_u64
    frame[Frame::CS] = 0x23_u64
    frame[Frame::SS] = 0x1b_u64
    fpu = words[5 &+ 23]
    if fpu != 0
      area = Processes.fpu(task)
      Processes.fpu_flush(task)
      Memory.copy_user(task.value.root, fpu, area, 512_u64, false)
      (area + 24_i64).as(UInt32*).value = (area + 24_i64).as(UInt32*).value & 0xffbf_u32
      Processes.fpu_reload(task)
    end
    task.value.mask = words[37] & ~FIXED
    frame
  end

  def self.next_signal(task : Kernel::Process*) : UInt64
    ready = task.value.signals & ~task.value.mask
    ready = ready | (task.value.signals & bit(KILL))
    return 0_u64 if ready == 0
    signal = 1_u64
    while ready & bit(signal) == 0
      signal = signal &+ 1
    end
    signal
  end

  # runs on every return to user mode
  def self.deliver(frame : UInt64*) : UInt64*
    while frame[Frame::CS] == 0x23
      task = Processes.current
      return frame if task.address == 0
      signal = next_signal(task)
      if signal == 0
        if task.value.suspended != 0
          task.value.mask = task.value.saved_mask
          task.value.suspended = 0_u64
        end
        return frame
      end
      task.value.signals = task.value.signals & ~bit(signal)
      entry = action(task, signal)
      if signal != KILL && entry.value.handler > IGNORE
        return frame if enter(task, frame, signal, entry)
        signal = SEGV
      elsif ignored?(task, signal)
        next
      end
      frame = Processes.exit(signal)
    end
    frame
  end

  # a fault is delivered right away when a handler is ready for it, otherwise it kills
  def self.fault(frame : UInt64*, signal : UInt64) : UInt64*
    task = Processes.current
    entry = action(task, signal)
    if entry.value.handler > IGNORE && task.value.mask & bit(signal) == 0
      task.value.sender = 0_u64
      return frame if enter(task, frame, signal, entry)
    end
    Processes.exit(signal)
  end
end
