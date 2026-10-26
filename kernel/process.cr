lib Kernel
  struct Process
    root : UInt64
    stack : UInt64
    frame : UInt64*
    pid : UInt64
    slot : UInt64
    state : UInt64
    quanta : UInt64
    wake_tick : UInt64
    ipc_endpoint : UInt64
    ipc_buffer : UInt64
    ipc_next : UInt64
    devices : UInt64
    parent : UInt64
    exit_status : UInt64
    collected : UInt64
    wait_pid : UInt64
    wait_buffer : UInt64
  end
end

module Processes
  FREE       =                  0_u64
  READY      =                  1_u64
  RUNNING    =                  2_u64
  ZOMBIE     =                  3_u64
  SLEEPING   =                  4_u64
  CALLING    =                  5_u64
  RECEIVING  =                  6_u64
  DEAD       =                  7_u64
  WAITING    =                  8_u64
  MAX        =                 64_u64
  STACK_BASE = 0xfffffe0000000000_u64
  STACK_SIZE =              16384_u64
  @@table = Pointer(Kernel::Process).new(0_u64)
  @@current = Pointer(Kernel::Process).new(0_u64)
  @@last_pid = 0_u64
  @@slice = 0_u64
  @@cursor = 0_u64

  def self.init
    size = MAX &* sizeof(Kernel::Process).to_u64!
    @@table = Memory.alloc_pages((size &+ 4095) >> 12).as(Kernel::Process*)
  end

  def self.slot(index : UInt64) : Kernel::Process*
    @@table + index.to_i64!
  end

  def self.find(pid : UInt64) : Kernel::Process*
    i = 0_u64
    while i < MAX
      task = slot(i)
      return task if task.value.state != FREE && task.value.pid == pid
      i = i &+ 1
    end
    Pointer(Kernel::Process).new(0_u64)
  end

  def self.task(pid : UInt64) : Kernel::Process*
    task = find(pid)
    panic("invalid process id") if task.address == 0
    task
  end

  # takes a free slot and gives it a kernel stack, the caller fills in the rest
  def self.allocate : Kernel::Process*
    i = 0_u64
    while i < MAX
      task = slot(i)
      if task.value.state == FREE
        memset(task.as(UInt8*), 0, sizeof(Kernel::Process).to_u64!)
        bottom = STACK_BASE &+ (i << 16) &+ Memory::PAGE
        offset = 0_u64
        while offset < STACK_SIZE
          Memory.map(Memory.kernel_root, bottom &+ offset, Memory.page, Memory::NX | Memory::WRITE, false)
          offset = offset &+ Memory::PAGE
        end
        @@last_pid = @@last_pid &+ 1
        task.value.pid = @@last_pid
        task.value.slot = i
        task.value.stack = bottom &+ STACK_SIZE
        task.value.state = SLEEPING
        task.value.wake_tick = 0xffffffffffffffff_u64
        return task
      end
      i = i &+ 1
    end
    Pointer(Kernel::Process).new(0_u64)
  end

  def self.create(file : UInt64*, name : String, devices : UInt64 = 0_u64)
    task = allocate
    panic("process limit") if task.address == 0
    root = Memory.create_space
    entry = ELF.load(root, 0_u64, file[1], file[2])
    panic("boot module is not a valid executable") if entry < 0
    args = uninitialized UInt64[2]
    argv = pointerof(args).as(UInt64*)
    argv[0] = name.to_unsafe.address
    argv[1] = 0_u64
    sp = ELF.stack(root, 0_u64, argv.address, 0_u64, 0_u64, 0_u64)
    panic("boot module stack") if sp < 0
    Display.grant(root) if devices & 1 != 0
    frame = Pointer(UInt64).new(task.value.stack &- (Frame::WORDS.to_u64! &* 8))
    frame[Frame::RIP] = entry.to_u64!
    frame[Frame::CS] = 0x23_u64
    frame[Frame::FLAGS] = 0x202_u64
    frame[Frame::RSP] = sp.to_u64!
    frame[Frame::SS] = 0x1b_u64
    task.value.devices = devices
    task.value.root = root
    task.value.frame = frame
    task.value.parent = task.value.pid == 1 ? 0_u64 : 1_u64
    task.value.state = READY
    Console.write("[Kristal] Process pid=")
    Console.hex(task.value.pid)
    Console.write(" cr3=")
    Console.hex(root)
    Console.write("\n")
  end

  def self.root : UInt64
    @@current.value.root
  end

  def self.activate(task : Kernel::Process*) : UInt64*
    @@current = task
    @@cursor = task.value.slot &+ 1
    task.value.state = RUNNING
    @@slice = 0_u64
    CPU.set_stack(task.value.stack)
    CPU.set_io(task.value.devices & 1 != 0)
    Arch.write_cr3(task.value.root)
    task.value.frame
  end

  def self.next_ready : Kernel::Process*
    index = @@cursor
    scanned = 0_u64
    while scanned < MAX
      index = 0_u64 if index >= MAX
      task = slot(index)
      return task if task.value.state == READY
      index = index &+ 1
      scanned = scanned &+ 1
    end
    Pointer(Kernel::Process).new(0_u64)
  end

  def self.current : Kernel::Process*
    @@current
  end

  def self.schedule : UInt64*
    chosen = next_ready
    return activate(chosen) if chosen.address != 0
    @@current = Pointer(Kernel::Process).new(0_u64)
    Arch.write_cr3(Memory.kernel_root)
    Arch.idle
  end

  def self.block(frame : UInt64*, state : UInt64) : UInt64*
    @@current.value.frame = frame
    @@current.value.state = state
    schedule
  end

  def self.sleep(frame : UInt64*, ticks : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::EINVAL) if ticks > 6000
    frame[Frame::RAX] = 0_u64
    @@current.value.wake_tick = Timer.ticks &+ ticks
    block(frame, ticks == 0 ? READY : SLEEPING)
  end

  def self.exited?(task : Kernel::Process*) : Bool
    task.value.state == ZOMBIE || task.value.state == DEAD
  end

  def self.matches?(task : Kernel::Process*, parent : UInt64, pid : UInt64) : Bool
    task.value.state != FREE && task.value.collected == 0 && task.value.parent == parent && (pid == Wait::ANY || task.value.pid == pid)
  end

  def self.collect(task : Kernel::Process*)
    task.value.collected = 1_u64
    task.value.state = FREE if task.value.state == DEAD
  end

  def self.wait(frame : UInt64*, pid : UInt64, address : UInt64) : UInt64*
    return Syscalls.fail(frame, Errno::EFAULT) unless address == 0 || Memory.access(root, address, 8_u64, true)
    parent = @@current.value.pid
    found = false
    i = 0_u64
    while i < MAX
      child = slot(i)
      if matches?(child, parent, pid)
        found = true
        if exited?(child)
          status = child.value.exit_status
          Memory.copy_user(root, address, pointerof(status).as(UInt8*), 8_u64, true) if address != 0
          frame[Frame::RAX] = child.value.pid
          collect(child)
          return frame
        end
      end
      i = i &+ 1
    end
    return Syscalls.fail(frame, Errno::ECHILD) unless found
    @@current.value.wait_pid = pid
    @@current.value.wait_buffer = address
    block(frame, WAITING)
  end

  def self.wake_sleepers
    i = 0_u64
    while i < MAX
      process = slot(i)
      if process.value.state == SLEEPING && (Timer.ticks &- process.value.wake_tick).to_i64! >= 0
        process.value.state = READY
      end
      i = i &+ 1
    end
  end

  def self.start : NoReturn
    Arch.resume(activate(@@table))
  end

  def self.tick(frame : UInt64*) : UInt64*
    return frame if frame[Frame::CS] != 0x23
    @@current.value.frame = frame
    @@slice = @@slice &+ 1
    return frame if @@slice < 5
    @@current.value.quanta = @@current.value.quanta &+ 1
    @@current.value.state = READY
    activate(next_ready)
  end

  def self.reap
    i = 0_u64
    while i < MAX
      task = slot(i)
      if task.value.state == ZOMBIE && task.address != @@current.address
        before = Memory.used
        Memory.destroy_space(task.value.root)
        address = task.value.stack &- STACK_SIZE
        while address < task.value.stack
          Memory.unmap_stack(address)
          address = address &+ Memory::PAGE
        end
        task.value.state = task.value.collected != 0 ? FREE : DEAD
        task.value.root = 0_u64
        task.value.frame = Pointer(UInt64).new(0_u64)
        Console.write("[Kristal] Reaped pid=")
        Console.hex(task.value.pid)
        Console.write(" pages=")
        Console.hex(before &- Memory.used)
        Console.write("\n")
      end
      i = i &+ 1
    end
  end

  def self.shutdown(status : UInt64) : NoReturn
    Console.write("[Kristal] init exited, powering off\n")
    Arch.debug_exit(status == 0 ? 0x10_u32 : 0x12_u32)
    Arch.stop
  end

  # status uses the unix wait layout: exit code in bits 8-15, signal in 0-6
  def self.exit(status : UInt64) : UInt64*
    task = @@current
    Console.write("[Kristal] Exit pid=")
    Console.hex(task.value.pid)
    Console.write(" status=")
    Console.hex(status)
    Console.write(" ticks=")
    Console.hex(Timer.ticks)
    Console.write(" quanta=")
    Console.hex(task.value.quanta)
    Console.write("\n")
    shutdown(status) if task.value.pid == 1
    task.value.exit_status = status
    parent = find(task.value.parent)
    if parent.address != 0 && parent.value.state == WAITING && (parent.value.wait_pid == Wait::ANY || parent.value.wait_pid == task.value.pid)
      Memory.copy_user(parent.value.root, parent.value.wait_buffer, pointerof(status).as(UInt8*), 8_u64, true) if parent.value.wait_buffer != 0
      parent.value.frame[Frame::RAX] = task.value.pid
      parent.value.state = READY
      task.value.collected = 1_u64
    end
    i = 0_u64
    while i < MAX
      child = slot(i)
      if child.value.state != FREE && child.value.parent == task.value.pid
        child.value.parent = 1_u64
      end
      i = i &+ 1
    end
    IPC.detach(task)
    task.value.state = ZOMBIE
    orphan_wake
    schedule
  end

  # a reparented zombie may satisfy a wait(-1) init is already blocked in
  def self.orphan_wake
    init = find(1_u64)
    return if init.address == 0 || init.value.state != WAITING || init.value.wait_pid != Wait::ANY
    i = 0_u64
    while i < MAX
      child = slot(i)
      if matches?(child, 1_u64, Wait::ANY) && exited?(child) && child.address != @@current.address
        status = child.value.exit_status
        Memory.copy_user(init.value.root, init.value.wait_buffer, pointerof(status).as(UInt8*), 8_u64, true) if init.value.wait_buffer != 0
        init.value.frame[Frame::RAX] = child.value.pid
        init.value.state = READY
        collect(child)
        return
      end
      i = i &+ 1
    end
  end
end

fun idle_main : NoReturn
  Processes.reap
  CPU.set_stack(Arch.stack_address)
  CPU.set_io(false)
  while true
    chosen = Processes.next_ready
    Arch.resume(Processes.activate(chosen)) if chosen.address != 0
    Arch.wait_interrupt
  end
end
