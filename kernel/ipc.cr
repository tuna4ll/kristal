lib Kernel
  struct Endpoint
    owner : UInt64
    head : UInt64
    tail : UInt64
    receiver : UInt64
    caller : UInt64
    closed : UInt64
  end

  struct Capability
    endpoint : UInt64
    rights : UInt64
  end
end

module IPC
  CALL    = 1_u64
  RECEIVE = 2_u64
  REPLY   = 4_u64
  SLOTS   = 4_u64
  @@endpoints = Pointer(Kernel::Endpoint).new(0_u64)
  @@caps = Pointer(Kernel::Capability).new(0_u64)
  @@messages = Pointer(UInt8).new(0_u64)
  @@count = 0_u64

  def self.init
    @@endpoints = Memory.alloc.as(Kernel::Endpoint*)
    @@caps = Memory.alloc.as(Kernel::Capability*)
    @@messages = Memory.alloc.as(UInt8*)
  end

  def self.create(owner : UInt64) : UInt64
    panic("endpoint limit") if @@count == SLOTS
    entry = @@endpoints + @@count.to_i64!
    entry.value.owner = owner
    @@count = @@count &+ 1
    @@count
  end

  def self.endpoint(id : UInt64) : Kernel::Endpoint*
    @@endpoints + (id &- 1).to_i64!
  end

  def self.grant(pid : UInt64, handle : UInt64, id : UInt64, rights : UInt64)
    panic("invalid capability grant") if pid == 0 || pid > Processes::MAX || handle == 0 || handle > SLOTS || id == 0 || id > @@count
    cap = @@caps + (((pid &- 1) &* SLOTS) &+ handle &- 1).to_i64!
    cap.value.endpoint = id
    cap.value.rights = rights
  end

  def self.resolve(handle : UInt64, right : UInt64) : UInt64
    return 0_u64 if handle == 0 || handle > SLOTS
    index = ((Processes.current.value.pid &- 1) &* SLOTS) &+ handle &- 1
    cap = @@caps + index.to_i64!
    return 0_u64 if cap.value.rights & right == 0
    cap.value.endpoint
  end

  def self.message(pid : UInt64) : UInt8*
    @@messages + ((pid &- 1) &* 64).to_i64!
  end

  def self.wake(pid : UInt64, result : UInt64)
    task = Processes.task(pid)
    task.value.frame[Frame::RAX] = result
    task.value.ipc_endpoint = 0_u64
    task.value.ipc_buffer = 0_u64
    task.value.ipc_next = 0_u64
    task.value.state = Processes::READY
  end

  def self.call(frame : UInt64*, handle : UInt64, address : UInt64) : UInt64*
    id = resolve(handle, CALL)
    return Syscalls.fail(frame, Errno::EPERM) if id == 0
    ep = endpoint(id)
    return Syscalls.fail(frame, Errno::EPIPE) if ep.value.closed != 0
    task = Processes.current
    pid = task.value.pid
    owner = ep.value.owner
    steps = 0_u64
    while owner != 0 && steps < Processes::MAX
      return Syscalls.fail(frame, Errno::EDEADLK) if owner == pid
      server = Processes.task(owner)
      break unless server.value.state == Processes::CALLING
      owner = endpoint(server.value.ipc_endpoint).value.owner
      steps = steps &+ 1
    end
    return Syscalls.fail(frame, Errno::EDEADLK) if steps == Processes::MAX
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.access(task.value.root, address, 64_u64, true)
    Memory.copy_user(task.value.root, address, message(pid), 64_u64, false)
    task.value.ipc_endpoint = id
    task.value.ipc_buffer = address
    task.value.ipc_next = 0_u64
    if ep.value.receiver != 0
      server = Processes.task(ep.value.receiver)
      Memory.copy_user(server.value.root, server.value.ipc_buffer, message(pid), 64_u64, true)
      wake(ep.value.receiver, pid)
      ep.value.receiver = 0_u64
      ep.value.caller = pid
    else
      if ep.value.tail == 0
        ep.value.head = pid
      else
        Processes.task(ep.value.tail).value.ipc_next = pid
      end
      ep.value.tail = pid
    end
    Processes.block(frame, Processes::CALLING)
  end

  def self.receive(frame : UInt64*, handle : UInt64, address : UInt64) : UInt64*
    id = resolve(handle, RECEIVE)
    return Syscalls.fail(frame, Errno::EPERM) if id == 0
    ep = endpoint(id)
    task = Processes.current
    return Syscalls.fail(frame, Errno::EPERM) if ep.value.owner != task.value.pid
    return Syscalls.fail(frame, Errno::EPIPE) if ep.value.closed != 0
    return Syscalls.fail(frame, Errno::EBUSY) if ep.value.caller != 0
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.access(task.value.root, address, 64_u64, true)
    pid = ep.value.head
    if pid != 0
      sender = Processes.task(pid)
      Memory.copy_user(task.value.root, address, message(pid), 64_u64, true)
      ep.value.head = sender.value.ipc_next
      ep.value.tail = 0_u64 if ep.value.head == 0
      sender.value.ipc_next = 0_u64
      ep.value.caller = pid
      frame[Frame::RAX] = pid
      return frame
    end
    ep.value.receiver = task.value.pid
    task.value.ipc_endpoint = id
    task.value.ipc_buffer = address
    Processes.block(frame, Processes::RECEIVING)
  end

  def self.reply(frame : UInt64*, handle : UInt64, address : UInt64) : UInt64*
    id = resolve(handle, REPLY)
    return Syscalls.fail(frame, Errno::EPERM) if id == 0
    ep = endpoint(id)
    server = Processes.current
    return Syscalls.fail(frame, Errno::EPERM) if ep.value.owner != server.value.pid
    return Syscalls.fail(frame, Errno::EPIPE) if ep.value.closed != 0 || ep.value.caller == 0
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(server.value.root, address, message(server.value.pid), 64_u64, false)
    caller = Processes.task(ep.value.caller)
    Memory.copy_user(caller.value.root, caller.value.ipc_buffer, message(server.value.pid), 64_u64, true)
    wake(ep.value.caller, 0_u64)
    # Consuming the pending caller prevents unsolicited or duplicate replies.
    ep.value.caller = 0_u64
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.detach(pid : UInt64)
    id = 1_u64
    while id <= @@count
      ep = endpoint(id)
      if ep.value.owner == pid
        ep.value.closed = 1_u64
        current = ep.value.head
        while current != 0
          following = Processes.task(current).value.ipc_next
          wake(current, (0_i64 &- Errno::EPIPE).to_u64!)
          current = following
        end
        wake(ep.value.caller, (0_i64 &- Errno::EPIPE).to_u64!) if ep.value.caller != 0
        ep.value.head = 0_u64
        ep.value.tail = 0_u64
        ep.value.receiver = 0_u64
        ep.value.caller = 0_u64
      else
        previous = 0_u64
        current = ep.value.head
        while current != 0
          following = Processes.task(current).value.ipc_next
          if current == pid
            if previous == 0
              ep.value.head = following
            else
              Processes.task(previous).value.ipc_next = following
            end
            ep.value.tail = previous if ep.value.tail == pid
            break
          end
          previous = current
          current = following
        end
        ep.value.caller = 0_u64 if ep.value.caller == pid
      end
      id = id &+ 1
    end
    slot = 0_u64
    while slot < SLOTS
      cap = @@caps + (((pid &- 1) &* SLOTS) &+ slot).to_i64!
      cap.value.rights = 0_u64
      cap.value.endpoint = 0_u64
      slot = slot &+ 1
    end
  end
end
