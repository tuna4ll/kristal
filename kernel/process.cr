lib Kernel
  struct Process
    root : UInt64
    stack : UInt64
    frame : UInt64*
    pid : UInt64
    state : UInt64
    quanta : UInt64
  end
end

module Processes
  READY      =                  1_u64
  RUNNING    =                  2_u64
  ZOMBIE     =                  3_u64
  STACK_BASE = 0xfffffe0000000000_u64
  @@table = Pointer(Kernel::Process).new(0_u64)
  @@current = Pointer(Kernel::Process).new(0_u64)
  @@count = 0_u64
  @@slice = 0_u64

  def self.init
    @@table = Memory.alloc.as(Kernel::Process*)
  end

  def self.create(file : UInt64*)
    panic("process limit") if @@count == 2
    task = @@table + @@count.to_i64!
    bottom = STACK_BASE &+ (@@count << 16) &+ Memory::PAGE
    offset = 0_u64
    while offset < 16384
      Memory.map(Memory.kernel_root, bottom &+ offset, Memory.page, Memory::NX | 2_u64, false)
      offset = offset &+ Memory::PAGE
    end
    root = Memory.create_space
    entry = ELF.load(root, Pointer(UInt8).new(file[1]), file[2])
    top = bottom &+ 16384
    frame = Pointer(UInt64).new(top &- (Frame::WORDS.to_u64! &* 8))
    frame[Frame::RIP] = entry
    frame[Frame::CS] = 0x23_u64
    frame[Frame::FLAGS] = 0x202_u64
    frame[Frame::RSP] = ELF::STACK
    frame[Frame::SS] = 0x1b_u64
    task.value.root = root
    task.value.stack = top
    task.value.frame = frame
    task.value.pid = @@count &+ 1
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
    task.value.state = RUNNING
    @@slice = 0_u64
    CPU.set_stack(task.value.stack)
    Arch.write_cr3(task.value.root)
    task.value.frame
  end

  def self.next_ready : Kernel::Process*
    index = @@current.value.pid
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
        task.value.state = 0_u64
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
    @@current.value.state = ZOMBIE
    task = next_ready
    return activate(task) if task.address != 0
    @@current = Pointer(Kernel::Process).new(0_u64)
    Arch.write_cr3(Memory.kernel_root)
    # Reclaim the old kernel stack only after moving to the boot stack.
    Arch.idle
  end
end

fun idle_main : NoReturn
  Processes.reap
  CPU.set_stack(Arch.stack_address)
  Console.write("[Kristal] No runnable processes; idle\n")
  while true
    Arch.wait_interrupt
  end
end
