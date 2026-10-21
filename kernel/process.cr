lib Kernel
  struct Process
    root : UInt64
    stack : UInt64
    frame : UInt64*
    pid : UInt64
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
  READY      =                  1_u64
  RUNNING    =                  2_u64
  ZOMBIE     =                  3_u64
  SLEEPING   =                  4_u64
  CALLING    =                  5_u64
  RECEIVING  =                  6_u64
  DEAD       =                  7_u64
  WAITING    =                  8_u64
  MAX        =                  8_u64
  STACK_BASE = 0xfffffe0000000000_u64
  @@table = Pointer(Kernel::Process).new(0_u64)
  @@current = Pointer(Kernel::Process).new(0_u64)
  @@count = 0_u64
  @@slice = 0_u64
  @@cursor = 0_u64

  def self.init
    @@table = Memory.alloc.as(Kernel::Process*)
  end

  def self.create(file : UInt64*, devices : UInt64 = 0_u64)
    panic("process limit") if @@count == MAX
    task = @@table + @@count.to_i64!
    bottom = STACK_BASE &+ (@@count << 16) &+ Memory::PAGE
    offset = 0_u64
    while offset < 16384
      Memory.map(Memory.kernel_root, bottom &+ offset, Memory.page, Memory::NX | 2_u64, false)
      offset = offset &+ Memory::PAGE
    end
    root = Memory.create_space
    entry = ELF.load(root, Pointer(UInt8).new(file[1]), file[2])
    Display.grant(root) if devices & 1 != 0
    top = bottom &+ 16384
    frame = Pointer(UInt64).new(top &- (Frame::WORDS.to_u64! &* 8))
    frame[Frame::RIP] = entry
    frame[Frame::CS] = 0x23_u64
    frame[Frame::FLAGS] = 0x202_u64
    frame[Frame::RSP] = ELF::STACK
    frame[Frame::SS] = 0x1b_u64
    task.value.devices = devices
    task.value.root = root
    task.value.stack = top
    task.value.frame = frame
    task.value.pid = @@count &+ 1
    task.value.parent = @@count == 0 ? 0_u64 : 1_u64
    task.value.state = READY
    @@count = @@count &+ 1
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
    @@cursor = task.value.pid
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
    while scanned < @@count
      index = 0_u64 if index == @@count
      task = @@table + index.to_i64!
      return task if task.value.state == READY
      index = index &+ 1
      scanned = scanned &+ 1
    end
    Pointer(Kernel::Process).new(0_u64)
  end

  def self.current : Kernel::Process*
    @@current
  end

  def self.task(pid : UInt64) : Kernel::Process*
    panic("invalid process id") if pid == 0 || pid > @@count
    @@table + (pid &- 1).to_i64!
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
    if ticks > 6000
      frame[Frame::RAX] = 0_u64 &- 22
      return frame
    end
    frame[Frame::RAX] = 0_u64
    @@current.value.wake_tick = Timer.ticks &+ ticks
    block(frame, ticks == 0 ? READY : SLEEPING)
  end

  def self.wait(frame : UInt64*, pid : UInt64, address : UInt64) : UInt64*
    if pid == 0 || pid > @@count
      frame[Frame::RAX] = 0_u64 &- 10
      return frame
    end
    child = task(pid)
    if child.value.parent != @@current.value.pid || child.value.collected != 0
      frame[Frame::RAX] = 0_u64 &- 10
      return frame
    end
    unless Memory.access(root, address, 8_u64, true)
      frame[Frame::RAX] = 0_u64 &- 14
      return frame
    end
    if child.value.state == ZOMBIE || child.value.state == DEAD
      status = child.value.exit_status
      Memory.copy_user(root, address, pointerof(status).as(UInt8*), 8_u64, true)
      child.value.collected = 1_u64
      frame[Frame::RAX] = pid
      return frame
    end
    @@current.value.wait_pid = pid
    @@current.value.wait_buffer = address
    block(frame, WAITING)
  end

  def self.wake_sleepers
    i = 0_u64
    while i < @@count
      process = @@table + i.to_i64!
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
    while i < @@count
      task = @@table + i.to_i64!
      if task.value.state == ZOMBIE && task.address != @@current.address
        before = Memory.used
        Memory.destroy_space(task.value.root)
        address = task.value.stack &- 16384
        while address < task.value.stack
          Memory.unmap_stack(address)
          address = address &+ Memory::PAGE
        end
        task.value.state = DEAD
        task.value.root = 0_u64
        task.value.stack = 0_u64
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

  def self.exit(status : UInt64) : UInt64*
    Console.write("[Kristal] Exit pid=")
    Console.hex(@@current.value.pid)
    Console.write(" status=")
    Console.hex(status)
    Console.write(" ticks=")
    Console.hex(Timer.ticks)
    Console.write(" quanta=")
    Console.hex(@@current.value.quanta)
    Console.write("\n")
    @@current.value.exit_status = status
    parent_id = @@current.value.parent
    if parent_id != 0
      parent = task(parent_id)
      if parent.value.state == WAITING && parent.value.wait_pid == @@current.value.pid
        Memory.copy_user(parent.value.root, parent.value.wait_buffer, pointerof(status).as(UInt8*), 8_u64, true)
        parent.value.frame[Frame::RAX] = @@current.value.pid
        parent.value.wait_pid = 0_u64
        parent.value.wait_buffer = 0_u64
        parent.value.state = READY
        @@current.value.collected = 1_u64
      end
    end
    shutdown(status) if @@current.value.pid == 1
    i = 0_u64
    while i < @@count
      child = @@table + i.to_i64!
      child.value.parent = 1_u64 if child.value.parent == @@current.value.pid
      i = i &+ 1
    end
    IPC.detach(@@current.value.pid)
    @@current.value.state = ZOMBIE
    schedule
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
