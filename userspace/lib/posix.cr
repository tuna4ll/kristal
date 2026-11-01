# file descriptors and the rest of the process state a libc keeps in userspace.
# exec hands it over in the startup blob, the kernel never looks inside
module Posix
  FDS     = 64_u64
  OPEN    =  1_u64
  CLOEXEC =  2_u64
  MAGIC   = 0x314c41545349524b_u64
  @@handles = uninitialized UInt64[64]
  @@ids = uninitialized UInt64[64]
  @@flags = uninitialized UInt64[64]
  @@cwd = uninitialized UInt8[256]
  @@root = 0_u64
  @@service = 0_u64

  def self.handles : UInt64*
    pointerof(@@handles).as(UInt64*)
  end

  def self.ids : UInt64*
    pointerof(@@ids).as(UInt64*)
  end

  def self.flags : UInt64*
    pointerof(@@flags).as(UInt64*)
  end

  def self.cwd : UInt8*
    pointerof(@@cwd).as(UInt8*)
  end

  def self.root : UInt64
    @@root
  end

  def self.root=(handle : UInt64)
    @@root = handle
  end

  def self.service : UInt64
    @@service
  end

  def self.init(data : UInt8*, size : UInt64)
    cwd[0] = 47_u8
    cwd[1] = 0_u8
    return if data.address == 0 || size < sizeof(ABI::Startup)
    startup = data.as(ABI::Startup*)
    return if startup.value.magic != MAGIC
    @@root = startup.value.root
    @@service = startup.value.service
    entries = (data + sizeof(ABI::Startup)).as(ABI::Descriptor*)
    i = 0_u64
    while i < startup.value.count && i < FDS
      entry = entries + i.to_i64!
      install(entry.value.fd, entry.value.handle, entry.value.id) if entry.value.fd < FDS
      i = i &+ 1
    end
    path = (entries + startup.value.count.to_i64!).as(UInt8*)
    if startup.value.cwd > 0 && startup.value.cwd < 256
      memcpy(cwd, path, startup.value.cwd)
      cwd[startup.value.cwd] = 0_u8
    end
  end

  # serializes the state a new image inherits, close on exec descriptors stay behind
  def self.startup(buffer : UInt8*, service : UInt64) : UInt64
    startup = buffer.as(ABI::Startup*)
    startup.value.magic = MAGIC
    startup.value.root = @@root
    startup.value.service = service
    entries = (buffer + sizeof(ABI::Startup)).as(ABI::Descriptor*)
    count = 0_u64
    fd = 0_u64
    while fd < FDS
      if flags[fd] & OPEN != 0 && flags[fd] & CLOEXEC == 0
        entry = entries + count.to_i64!
        entry.value.fd = fd
        entry.value.handle = handles[fd]
        entry.value.id = ids[fd]
        entry.value.flags = 0_u64
        count = count &+ 1
      end
      fd = fd &+ 1
    end
    startup.value.count = count
    length = Text.length(cwd)
    startup.value.cwd = length
    path = (entries + count.to_i64!).as(UInt8*)
    memcpy(path, cwd, length)
    (path.address &+ length) &- buffer.address
  end

  def self.install(fd : UInt64, handle : UInt64, id : UInt64)
    handles[fd] = handle
    ids[fd] = id
    flags[fd] = OPEN
  end

  def self.request(fd : UInt64, message : ABI::Message*, buffer : UInt8*, capacity : UInt64) : Int64
    return 0_i64 &- Errno::EBADF if fd >= FDS || flags[fd] & OPEN == 0
    message.value.a = ids[fd]
    result = System.call(handles[fd], message, buffer, capacity)
    return result if result < 0
    message.value.tag.to_i64!
  end

  def self.write(fd : UInt64, buffer : UInt8*, count : UInt64) : Int64
    message = uninitialized ABI::Message
    memset(pointerof(message).as(UInt8*), 0, 64_u64)
    message.tag = Op::WRITE
    message.length = count
    request(fd, pointerof(message), buffer, 0_u64)
  end

  def self.exit(status : UInt64) : NoReturn
    System.exit(status)
  end
end
