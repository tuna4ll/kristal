lib Kernel
  struct Endpoint
    refs : UInt64
    receivers : UInt64
    head : UInt64
    tail : UInt64
    receiver : UInt64
    server : UInt64
    pending : UInt64
    reserved : UInt64
  end

  struct Capability
    endpoint : UInt64
    rights : UInt64
  end
end

# queue links and receivers store slot + 1 so zero can mean empty
module IPC
  CALL      =  1_u64
  RECEIVE   =  2_u64
  GRANT     =  4_u64
  ALL       =  7_u64
  SLOTS     = 32_u64
  ENDPOINTS = 64_u64
  @@endpoints = Pointer(Kernel::Endpoint).new(0_u64)
  @@caps = Pointer(Kernel::Capability).new(0_u64)
  @@messages = Pointer(ABI::Message).new(0_u64)

  def self.init
    @@endpoints = Memory.alloc_pages(ENDPOINTS &* sizeof(Kernel::Endpoint).to_u64! >> 12).as(Kernel::Endpoint*)
    @@caps = Memory.alloc_pages(Processes::MAX &* SLOTS &* 16 >> 12).as(Kernel::Capability*)
    @@messages = Memory.alloc_pages(Processes::MAX &* 64 >> 12).as(ABI::Message*)
  end

  def self.endpoint(id : UInt64) : Kernel::Endpoint*
    @@endpoints + (id &- 1).to_i64!
  end

  def self.cap(task : Kernel::Process*, handle : UInt64) : Kernel::Capability*
    @@caps + ((task.value.slot &* SLOTS) &+ handle &- 1).to_i64!
  end

  def self.message(task : Kernel::Process*) : ABI::Message*
    @@messages + task.value.slot.to_i64!
  end

  def self.install(task : Kernel::Process*, id : UInt64, rights : UInt64) : UInt64
    handle = 1_u64
    while handle <= SLOTS
      entry = cap(task, handle)
      if entry.value.endpoint == 0
        entry.value.endpoint = id
        entry.value.rights = rights
        endpoint(id).value.refs = endpoint(id).value.refs &+ 1
        endpoint(id).value.receivers = endpoint(id).value.receivers &+ 1 if rights & RECEIVE != 0
        return handle
      end
      handle = handle &+ 1
    end
    0_u64
  end

  def self.release(task : Kernel::Process*, handle : UInt64)
    entry = cap(task, handle)
    id = entry.value.endpoint
    return if id == 0
    ep = endpoint(id)
    if entry.value.rights & RECEIVE != 0
      ep.value.receivers = ep.value.receivers &- 1
      shut(id) if ep.value.receivers == 0
    end
    entry.value.endpoint = 0_u64
    entry.value.rights = 0_u64
    ep.value.refs = ep.value.refs &- 1
    if ep.value.refs == 0
      memset(ep.as(UInt8*), 0, sizeof(Kernel::Endpoint).to_u64!)
    end
  end

  # nobody can receive any more, so every caller still waiting gets EPIPE
  def self.shut(id : UInt64)
    i = 0_u64
    while i < Processes::MAX
      task = Processes.slot(i)
      if task.value.state == Processes::CALLING && task.value.ipc_endpoint == id
        finish(task, (0_i64 &- Errno::EPIPE).to_u64!)
      end
      i = i &+ 1
    end
    endpoint(id).value.head = 0_u64
    endpoint(id).value.tail = 0_u64
  end

  def self.resolve(task : Kernel::Process*, handle : UInt64, right : UInt64) : Int64
    return 0_i64 &- Errno::EBADF if handle == 0 || handle > SLOTS
    entry = cap(task, handle)
    return 0_i64 &- Errno::EBADF if entry.value.endpoint == 0
    return 0_i64 &- Errno::EPERM if entry.value.rights & right == 0
    entry.value.endpoint.to_i64!
  end

  def self.finish(task : Kernel::Process*, result : UInt64)
    task.value.frame[Frame::RAX] = result
    task.value.ipc_endpoint = 0_u64
    task.value.ipc_next = 0_u64
    task.value.ipc_served = 0_u64
    task.value.state = Processes::READY
  end

  def self.allocate : UInt64
    id = 1_u64
    while id <= ENDPOINTS
      return id if endpoint(id).value.refs == 0
      id = id &+ 1
    end
    0_u64
  end

  def self.create(frame : UInt64*) : UInt64*
    id = allocate
    return Syscalls.fail(frame, Errno::ENOSPC) if id == 0
    handle = install(Processes.current, id, ALL)
    return Syscalls.fail(frame, Errno::EMFILE) if handle == 0
    frame[Frame::RAX] = handle
    frame
  end

  def self.close(frame : UInt64*, handle : UInt64) : UInt64*
    result = resolve(Processes.current, handle, 0_u64)
    return Syscalls.fail(frame, 0_i64 &- result) if result < 0
    release(Processes.current, handle)
    frame[Frame::RAX] = 0_u64
    frame
  end

  def self.buffers(task : Kernel::Process*, message : UInt64, buffer : UInt64, length : UInt64, capacity : UInt64) : Bool
    return false unless Memory.access(task.value.root, message, 64_u64, true)
    return false unless Memory.access(task.value.root, buffer, length, false)
    Memory.access(task.value.root, buffer, capacity, true)
  end

  def self.deadlock?(task : Kernel::Process*, id : UInt64) : Bool
    pid = endpoint(id).value.server
    steps = 0_u64
    while pid != 0 && steps < Processes::MAX
      return true if pid == task.value.pid
      server = Processes.find(pid)
      return false if server.address == 0 || server.value.state != Processes::CALLING
      pid = endpoint(server.value.ipc_endpoint).value.server
      steps = steps &+ 1
    end
    steps == Processes::MAX
  end

  def self.call(frame : UInt64*, handle : UInt64, address : UInt64, buffer : UInt64, capacity : UInt64) : UInt64*
    task = Processes.current
    id = resolve(task, handle, CALL)
    return Syscalls.fail(frame, 0_i64 &- id) if id < 0
    ep = endpoint(id.to_u64!)
    return Syscalls.fail(frame, Errno::EPIPE) if ep.value.receivers == 0
    return Syscalls.fail(frame, Errno::EDEADLK) if deadlock?(task, id.to_u64!)
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, address, message(task).as(UInt8*), 64_u64, false)
    length = message(task).value.length
    return Syscalls.fail(frame, Errno::EFAULT) unless buffers(task, address, buffer, length, capacity)
    task.value.ipc_cap = 0_u64
    if message(task).value.cap != 0
      transfer = resolve(task, message(task).value.cap, GRANT)
      return Syscalls.fail(frame, 0_i64 &- transfer) if transfer < 0
      task.value.ipc_cap = transfer.to_u64!
      task.value.ipc_rights = cap(task, message(task).value.cap).value.rights
    end
    task.value.ipc_endpoint = id.to_u64!
    task.value.ipc_message = address
    task.value.ipc_buffer = buffer
    task.value.ipc_length = length
    task.value.ipc_capacity = capacity
    task.value.ipc_next = 0_u64
    task.value.ipc_served = 0_u64
    task.value.frame = frame
    task.value.state = Processes::CALLING
    if ep.value.receiver != 0
      server = Processes.slot(ep.value.receiver &- 1)
      ep.value.receiver = 0_u64
      deliver(id.to_u64!, server, task)
    else
      if ep.value.tail == 0
        ep.value.head = task.value.slot &+ 1
      else
        Processes.slot(ep.value.tail &- 1).value.ipc_next = task.value.slot &+ 1
      end
      ep.value.tail = task.value.slot &+ 1
    end
    Processes.schedule
  end

  def self.deliver(id : UInt64, server : Kernel::Process*, caller : Kernel::Process*)
    data = message(caller)
    count = caller.value.ipc_length
    count = server.value.ipc_capacity if count > server.value.ipc_capacity
    Memory.copy_between(caller.value.root, caller.value.ipc_buffer, server.value.root, server.value.ipc_buffer, count)
    data.value.length = count
    data.value.cap = 0_u64
    if caller.value.ipc_cap != 0
      data.value.cap = install(server, caller.value.ipc_cap, caller.value.ipc_rights)
      caller.value.ipc_cap = 0_u64
    end
    Memory.copy_user(server.value.root, server.value.ipc_message, data.as(UInt8*), 64_u64, true)
    caller.value.ipc_served = 1_u64
    endpoint(id).value.server = server.value.pid
    server.value.frame[Frame::RAX] = caller.value.pid
    server.value.ipc_endpoint = 0_u64
    server.value.state = Processes::READY if server.value.state == Processes::RECEIVING
  end

  def self.receive(frame : UInt64*, handle : UInt64, address : UInt64, buffer : UInt64, capacity : UInt64) : UInt64*
    task = Processes.current
    id = resolve(task, handle, RECEIVE)
    return Syscalls.fail(frame, 0_i64 &- id) if id < 0
    ep = endpoint(id.to_u64!)
    return Syscalls.fail(frame, Errno::EFAULT) unless buffers(task, address, buffer, 0_u64, capacity)
    task.value.ipc_message = address
    task.value.ipc_buffer = buffer
    task.value.ipc_capacity = capacity
    task.value.frame = frame
    if ep.value.pending != 0
      signal(task, ep.value.pending)
      ep.value.pending = 0_u64
      return frame
    end
    if ep.value.head != 0
      caller = Processes.slot(ep.value.head &- 1)
      ep.value.head = caller.value.ipc_next
      ep.value.tail = 0_u64 if ep.value.head == 0
      caller.value.ipc_next = 0_u64
      deliver(id.to_u64!, task, caller)
      return frame
    end
    return Syscalls.fail(frame, Errno::EBUSY) if ep.value.receiver != 0
    ep.value.receiver = task.value.slot &+ 1
    task.value.ipc_endpoint = id.to_u64!
    Processes.block(frame, Processes::RECEIVING)
  end

  def self.reply(frame : UInt64*, handle : UInt64, pid : UInt64, address : UInt64, buffer : UInt64) : UInt64*
    task = Processes.current
    id = resolve(task, handle, RECEIVE)
    return Syscalls.fail(frame, 0_i64 &- id) if id < 0
    caller = Processes.find(pid)
    return Syscalls.fail(frame, Errno::ESRCH) if caller.address == 0 || caller.value.state != Processes::CALLING
    return Syscalls.fail(frame, Errno::ESRCH) if caller.value.ipc_endpoint != id.to_u64! || caller.value.ipc_served == 0
    data = message(caller)
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.copy_user(task.value.root, address, data.as(UInt8*), 64_u64, false)
    count = data.value.length
    count = caller.value.ipc_capacity if count > caller.value.ipc_capacity
    return Syscalls.fail(frame, Errno::EFAULT) unless Memory.access(task.value.root, buffer, count, false)
    granted = 0_u64
    if data.value.cap != 0
      transfer = resolve(task, data.value.cap, GRANT)
      return Syscalls.fail(frame, 0_i64 &- transfer) if transfer < 0
      granted = install(caller, transfer.to_u64!, cap(task, data.value.cap).value.rights)
    end
    Memory.copy_between(task.value.root, buffer, caller.value.root, caller.value.ipc_buffer, count)
    data.value.length = count
    data.value.cap = granted
    Memory.copy_user(caller.value.root, caller.value.ipc_message, data.as(UInt8*), 64_u64, true)
    finish(caller, 0_u64)
    frame[Frame::RAX] = 0_u64
    frame
  end

  # a notification arrives as a message from pid 0 with the pending bits in a
  def self.signal(task : Kernel::Process*, bits : UInt64)
    data = message(task)
    memset(data.as(UInt8*), 0, 64_u64)
    data.value.a = bits
    Memory.copy_user(task.value.root, task.value.ipc_message, data.as(UInt8*), 64_u64, true)
    task.value.frame[Frame::RAX] = 0_u64
    task.value.ipc_endpoint = 0_u64
  end

  def self.notify(id : UInt64, bits : UInt64)
    ep = endpoint(id)
    ep.value.pending = ep.value.pending | bits
    return if ep.value.receiver == 0
    task = Processes.slot(ep.value.receiver &- 1)
    ep.value.receiver = 0_u64
    signal(task, ep.value.pending)
    ep.value.pending = 0_u64
    task.value.state = Processes::READY
  end

  def self.grant(task : Kernel::Process*, id : UInt64, rights : UInt64) : UInt64
    install(task, id, rights)
  end

  def self.fork(parent : Kernel::Process*, child : Kernel::Process*)
    handle = 1_u64
    while handle <= SLOTS
      entry = cap(parent, handle)
      if entry.value.endpoint != 0
        cap(child, handle).value = entry.value
        ep = endpoint(entry.value.endpoint)
        ep.value.refs = ep.value.refs &+ 1
        ep.value.receivers = ep.value.receivers &+ 1 if entry.value.rights & RECEIVE != 0
      end
      handle = handle &+ 1
    end
  end

  def self.detach(task : Kernel::Process*)
    handle = 1_u64
    while handle <= SLOTS
      release(task, handle)
      handle = handle &+ 1
    end
  end
end
