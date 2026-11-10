lib FS
  struct Pipe
    head : UInt64
    count : UInt64
    reader : UInt64
    writer : UInt64
  end

  struct Waiter
    pid : UInt64
    file : UInt64
    wanted : UInt64
    done : UInt64
  end
end

# readers wait for data and writers for room, both are answered later from flush
module Pipes
  COUNT   =   16_u64
  SIZE    = 4096_u64
  WAITERS =   16_u64
  @@pipes = uninitialized FS::Pipe[16]
  @@buffers = uninitialized UInt8[65536]
  @@readers = uninitialized FS::Waiter[16]
  @@writers = uninitialized FS::Waiter[16]
  @@pending = uninitialized UInt8[65536]

  def self.pipe(index : UInt64) : FS::Pipe*
    pointerof(@@pipes).as(FS::Pipe*) + index.to_i64!
  end

  def self.buffer(index : UInt64) : UInt8*
    pointerof(@@buffers).as(UInt8*) + (index &* SIZE).to_i64!
  end

  def self.reader(index : UInt64) : FS::Waiter*
    pointerof(@@readers).as(FS::Waiter*) + index.to_i64!
  end

  def self.writer(index : UInt64) : FS::Waiter*
    pointerof(@@writers).as(FS::Waiter*) + index.to_i64!
  end

  def self.pending(index : UInt64) : UInt8*
    pointerof(@@pending).as(UInt8*) + (index &* SIZE).to_i64!
  end

  def self.create(message : ABI::Message*)
    index = 0_u64
    while index < COUNT && pipe(index).value.reader != 0
      index = index &+ 1
    end
    return fail(message, Errno::ENFILE) if index == COUNT
    reader = Tree.open(0_u64)
    writer = Tree.open(0_u64)
    if reader == 0 || writer == 0
      (Tree.files + reader.to_i64!).value.refs = 0_u64 if reader != 0
      return fail(message, Errno::ENFILE)
    end
    (Tree.files + reader.to_i64!).value.pipe = index &+ 1
    (Tree.files + writer.to_i64!).value.pipe = index &+ 1
    (Tree.files + writer.to_i64!).value.side = 1_u64
    entry = pipe(index)
    entry.value.head = 0_u64
    entry.value.count = 0_u64
    entry.value.reader = reader
    entry.value.writer = writer
    message.value.a = reader
    message.value.b = writer
  end

  def self.readers?(entry : FS::Pipe*) : Bool
    Tree.files[entry.value.reader].refs != 0
  end

  def self.writers?(entry : FS::Pipe*) : Bool
    Tree.files[entry.value.writer].refs != 0
  end

  def self.take(entry : FS::Pipe*, index : UInt64, target : UInt8*, count : UInt64) : UInt64
    count = entry.value.count if count > entry.value.count
    i = 0_u64
    while i < count
      target[i] = buffer(index)[(entry.value.head &+ i) & (SIZE &- 1)]
      i = i &+ 1
    end
    entry.value.head = (entry.value.head &+ count) & (SIZE &- 1)
    entry.value.count = entry.value.count &- count
    count
  end

  # puts bytes back in front when the reader they were meant for is gone
  def self.untake(entry : FS::Pipe*, count : UInt64)
    entry.value.head = (entry.value.head &- count) & (SIZE &- 1)
    entry.value.count = entry.value.count &+ count
  end

  def self.put(entry : FS::Pipe*, index : UInt64, source : UInt8*, count : UInt64) : UInt64
    room = SIZE &- entry.value.count
    count = room if count > room
    i = 0_u64
    while i < count
      buffer(index)[(entry.value.head &+ entry.value.count &+ i) & (SIZE &- 1)] = source[i]
      i = i &+ 1
    end
    entry.value.count = entry.value.count &+ count
    count
  end

  def self.read(sender : UInt64, file : FS::File*, id : UInt64, message : ABI::Message*, data : UInt8*, capacity : UInt64) : Bool
    return fail_now(message, Errno::EBADF) if file.value.side != 0
    index = file.value.pipe &- 1
    entry = pipe(index)
    count = message.value.b
    count = capacity if count > capacity
    if entry.value.count == 0 && writers?(entry) && count != 0
      slot = 0_u64
      while slot < WAITERS && reader(slot).value.pid != 0
        slot = slot &+ 1
      end
      return fail_now(message, Errno::EAGAIN) if slot == WAITERS
      reader(slot).value.pid = sender
      reader(slot).value.file = id
      reader(slot).value.wanted = count
      return false
    end
    count = take(entry, index, data, count)
    message.value.tag = count
    message.value.length = count
    true
  end

  def self.write(sender : UInt64, file : FS::File*, id : UInt64, message : ABI::Message*, data : UInt8*, length : UInt64) : Bool
    return fail_now(message, Errno::EBADF) if file.value.side != 1
    index = file.value.pipe &- 1
    entry = pipe(index)
    return fail_now(message, Errno::EPIPE) unless readers?(entry)
    written = put(entry, index, data, length)
    if written < length
      slot = 0_u64
      while slot < WAITERS && writer(slot).value.pid != 0
        slot = slot &+ 1
      end
      if slot < WAITERS
        waiter = writer(slot)
        waiter.value.pid = sender
        waiter.value.file = id
        waiter.value.wanted = length
        waiter.value.done = written
        memcpy(pending(slot), data + written.to_i64!, length &- written)
        return false
      end
      return fail_now(message, Errno::EAGAIN) if written == 0
    end
    message.value.tag = written
    true
  end

  def self.fail_now(message : ABI::Message*, error : Int64) : Bool
    fail(message, error)
    true
  end

  def self.release(file : FS::File*)
    return if file.value.refs != 0
    entry = pipe(file.value.pipe &- 1)
    if !readers?(entry) && !writers?(entry)
      entry.value.reader = 0_u64
      entry.value.writer = 0_u64
    end
  end

  def self.answer(service : UInt64, pid : UInt64, message : ABI::Message*, data : UInt8*, result : Int64, length : UInt64) : Bool
    memset(message.as(UInt8*), 0, 64_u64)
    message.value.tag = result.to_u64!
    message.value.length = length
    System.reply(service, pid, message, data) == 0
  end

  # answers whatever waiter can make progress after a request changed some pipe
  def self.flush(service : UInt64, message : ABI::Message*, data : UInt8*)
    progress = true
    while progress
      progress = false
      slot = 0_u64
      while slot < WAITERS
        waiter = writer(slot)
        if waiter.value.pid != 0
          file = Tree.file(waiter.value.file)
          entry = pipe(file.value.pipe &- 1)
          if file.address == 0 || !readers?(entry)
            answer(service, waiter.value.pid, message, data, 0_i64 &- Errno::EPIPE, 0_u64)
            waiter.value.pid = 0_u64
            progress = true
          else
            left = waiter.value.wanted &- waiter.value.done
            moved = put(entry, file.value.pipe &- 1, pending(slot), left)
            if moved != 0
              memmove(pending(slot), pending(slot) + moved.to_i64!, left &- moved)
              waiter.value.done = waiter.value.done &+ moved
              progress = true
            end
            if waiter.value.done == waiter.value.wanted
              answer(service, waiter.value.pid, message, data, waiter.value.wanted.to_i64!, 0_u64)
              waiter.value.pid = 0_u64
            end
          end
        end
        waiter = reader(slot)
        if waiter.value.pid != 0
          file = Tree.file(waiter.value.file)
          entry = pipe(file.value.pipe &- 1)
          if file.address == 0
            waiter.value.pid = 0_u64
          elsif entry.value.count != 0 || !writers?(entry)
            count = take(entry, file.value.pipe &- 1, data, waiter.value.wanted)
            untake(entry, count) unless answer(service, waiter.value.pid, message, data, count.to_i64!, count)
            waiter.value.pid = 0_u64
            progress = true
          end
        end
        slot = slot &+ 1
      end
    end
  end
end
