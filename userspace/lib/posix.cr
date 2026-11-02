# file descriptors and the rest of the process state a libc keeps in userspace.
# exec hands it over in the startup blob, the kernel never looks inside
module Posix
  FDS     =                 64_u64
  OPEN    =                  1_u64
  CLOEXEC =                  2_u64
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

  def self.error(code : Int64) : Int64
    0_i64 &- code
  end

  def self.clear(message : ABI::Message*, op : UInt64)
    memset(message.as(UInt8*), 0, 64_u64)
    message.value.tag = op
  end

  # turns a path into an absolute one without . and .. parts
  def self.absolute(path : UInt8*, target : UInt8*) : Int64
    length = 0_u64
    if path[0] != 47
      length = Text.length(cwd)
      memcpy(target, cwd, length)
      length = 0_u64 if length == 1
    end
    i = 0_u64
    while path[i] != 0
      while path[i] == 47
        i = i &+ 1
      end
      start = i
      while path[i] != 0 && path[i] != 47
        i = i &+ 1
      end
      size = i &- start
      next if size == 0 || (size == 1 && path[start] == 46)
      if size == 2 && path[start] == 46 && path[start &+ 1] == 46
        while length > 0 && target[length &- 1] != 47
          length = length &- 1
        end
        length = length &- 1 if length > 0
        next
      end
      return error(Errno::ENAMETOOLONG) if length &+ size &+ 2 > 256
      target[length] = 47_u8
      memcpy(target + (length &+ 1).to_i64!, path + start.to_i64!, size)
      length = length &+ 1 &+ size
    end
    if length == 0
      target[0] = 47_u8
      length = 1_u64
    end
    target[length] = 0_u8
    length.to_i64!
  end

  def self.lowest(from : UInt64 = 0_u64) : Int64
    fd = from
    while fd < FDS
      return fd.to_i64! if flags[fd] & OPEN == 0
      fd = fd &+ 1
    end
    error(Errno::EMFILE)
  end

  def self.valid?(fd : UInt64) : Bool
    fd < FDS && flags[fd] & OPEN != 0
  end

  def self.path_request(op : UInt64, path : UInt8*, message : ABI::Message*, buffer : UInt8*, capacity : UInt64) : Int64
    scratch = uninitialized UInt8[256]
    full = pointerof(scratch).as(UInt8*)
    length = absolute(path, full)
    return length if length < 0
    return error(Errno::ENOENT) if @@root == 0
    message.value.tag = op
    message.value.length = length.to_u64!
    memcpy(buffer, full, length.to_u64!)
    result = System.call(@@root, message, buffer, capacity)
    return result if result < 0
    message.value.tag.to_i64!
  end

  def self.open(path : UInt8*, mode : UInt64) : Int64
    fd = lowest
    return fd if fd < 0
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::OPEN)
    message.a = mode
    buffer = uninitialized UInt8[256]
    result = path_request(Op::OPEN, path, pointerof(message), pointerof(buffer).as(UInt8*), 0_u64)
    return result if result < 0
    handle = message.cap != 0 ? message.cap : @@root
    install(fd.to_u64!, handle, result.to_u64!)
    flags[fd] = flags[fd] | CLOEXEC if mode & Flag::CLOEXEC != 0
    fd
  end

  def self.read(fd : UInt64, buffer : UInt8*, count : UInt64) : Int64
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::READ)
    message.b = count
    request(fd, pointerof(message), buffer, count)
  end

  def self.simple(fd : UInt64, op : UInt64, b : UInt64 = 0_u64, c : UInt64 = 0_u64) : Int64
    message = uninitialized ABI::Message
    clear(pointerof(message), op)
    message.b = b
    message.c = c
    request(fd, pointerof(message), Pointer(UInt8).new(0_u64), 0_u64)
  end

  def self.shared?(handle : UInt64, except : UInt64) : Bool
    return true if handle == @@root
    fd = 0_u64
    while fd < FDS
      return true if fd != except && flags[fd] & OPEN != 0 && handles[fd] == handle
      fd = fd &+ 1
    end
    false
  end

  def self.close(fd : UInt64) : Int64
    return error(Errno::EBADF) unless valid?(fd)
    simple(fd, Op::CLOSE)
    System.close(handles[fd]) unless shared?(handles[fd], fd)
    flags[fd] = 0_u64
    0_i64
  end

  def self.dup2(fd : UInt64, target : UInt64) : Int64
    return error(Errno::EBADF) unless valid?(fd) && target < FDS
    return target.to_i64! if fd == target
    result = simple(fd, Op::DUP)
    return result if result < 0
    close(target) if valid?(target)
    install(target, handles[fd], ids[fd])
    target.to_i64!
  end

  def self.dup(fd : UInt64, from : UInt64 = 0_u64) : Int64
    return error(Errno::EBADF) unless valid?(fd)
    target = lowest(from)
    return target if target < 0
    dup2(fd, target.to_u64!)
  end

  def self.lseek(fd : UInt64, offset : Int64, whence : UInt64) : Int64
    simple(fd, Op::SEEK, offset.to_u64!, whence)
  end

  def self.fstat(fd : UInt64, info : UInt8*) : Int64
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::FSTAT)
    result = request(fd, pointerof(message), info, sizeof(ABI::Stat).to_u64!)
    result < 0 ? result : 0_i64
  end

  def self.stat(path : UInt8*, info : UInt8*) : Int64
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::STAT)
    buffer = uninitialized UInt8[256]
    result = path_request(Op::STAT, path, pointerof(message), pointerof(buffer).as(UInt8*), 256_u64)
    return result if result < 0
    memcpy(info, pointerof(buffer).as(UInt8*), sizeof(ABI::Stat).to_u64!)
    0_i64
  end

  def self.getdents(fd : UInt64, buffer : UInt8*, count : UInt64) : Int64
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::GETDENTS)
    message.b = count
    request(fd, pointerof(message), buffer, count)
  end

  def self.chdir(path : UInt8*) : Int64
    info = uninitialized ABI::Stat
    result = stat(path, pointerof(info).as(UInt8*))
    return result if result < 0
    return error(Errno::ENOTDIR) if info.mode & Mode::TYPE != Mode::DIRECTORY
    scratch = uninitialized UInt8[256]
    full = pointerof(scratch).as(UInt8*)
    absolute(path, full)
    Text.copy(cwd, full)
    0_i64
  end

  def self.getcwd(buffer : UInt8*, size : UInt64) : Int64
    length = Text.length(cwd)
    return error(Errno::ERANGE) if length &+ 1 > size
    Text.copy(buffer, cwd)
    (length &+ 1).to_i64!
  end

  def self.exit(status : UInt64) : NoReturn
    System.exit(status)
  end
end
