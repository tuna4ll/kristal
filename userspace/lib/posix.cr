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
  @@break = 0_u64
  @@mapped = Layout::MAP

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

  # the break starts right after the highest loaded segment
  def self.image(phdr : UInt64, count : UInt64)
    top = 0x10000000_u64
    count = 0_u64 if phdr == 0
    i = 0_u64
    while i < count
      header = Pointer(UInt8).new(phdr &+ i &* 56)
      if header.as(UInt32*).value == 1
        finish = (header + 16_i64).as(UInt64*).value &+ (header + 40_i64).as(UInt64*).value
        top = finish if finish > top || top == 0x10000000
      end
      i = i &+ 1
    end
    @@break = (top &+ 4095) & ~4095_u64
  end

  def self.brk(address : UInt64) : Int64
    return @@break.to_i64! if address == 0 || @@break == 0
    current = (@@break &+ 4095) & ~4095_u64
    wanted = (address &+ 4095) & ~4095_u64
    if wanted > current
      return @@break.to_i64! if wanted >= Layout::IMAGE_END || System.map(current, wanted &- current, 1_u64) < 0
    elsif wanted < current
      System.unmap(wanted, current &- wanted)
    end
    @@break = address
    address.to_i64!
  end

  def self.mmap(address : UInt64, length : UInt64, protection : UInt64, options : UInt64, fd : Int64) : Int64
    return error(Errno::EINVAL) if length == 0
    return error(Errno::ENODEV) if options & 0x20 == 0
    length = (length &+ 4095) & ~4095_u64
    flags = protection & 2 != 0 ? 1_u64 : 0_u64
    flags = flags | 2_u64 if protection & 4 != 0
    flags = 1_u64 if flags == 3
    if options & 0x10 != 0
      return error(Errno::EINVAL) if address & 4095 != 0
      System.unmap(address, length)
    else
      address = @@mapped
      @@mapped = @@mapped &+ length &+ 4096
    end
    result = System.map(address, length, flags)
    return result if result < 0
    address.to_i64!
  end

  def self.munmap(address : UInt64, length : UInt64) : Int64
    System.unmap(address, (length &+ 4095) & ~4095_u64)
  end

  # every descriptor gains a reference first so the child owns its copies
  def self.fork : Int64
    fd = 0_u64
    while fd < FDS
      simple(fd, Op::DUP) if valid?(fd)
      fd = fd &+ 1
    end
    pid = System.fork
    if pid < 0
      fd = 0_u64
      while fd < FDS
        simple(fd, Op::CLOSE) if valid?(fd)
        fd = fd &+ 1
      end
    end
    pid
  end

  def self.execve(path : UInt8*, argv : UInt8**, envp : UInt8**) : Int64
    fd = open(path, Flag::CLOEXEC)
    return fd if fd < 0
    info = uninitialized ABI::Stat
    result = fstat(fd.to_u64!, pointerof(info).as(UInt8*))
    if result == 0 && (info.mode & Mode::TYPE != Mode::REGULAR || info.mode & 0o111_u32 == 0)
      result = error(Errno::EACCES)
    end
    if result < 0
      close(fd.to_u64!)
      return result
    end
    size = info.size.to_u64!
    image = mmap(0_u64, size, 3_u64, 0x22_u64, -1_i64)
    if image < 0
      close(fd.to_u64!)
      return image
    end
    done = 0_u64
    while done < size
      count = read(fd.to_u64!, Pointer(UInt8).new(image.to_u64! &+ done), size &- done)
      break if count <= 0
      done = done &+ count.to_u64!
    end
    close(fd.to_u64!)
    blob = uninitialized UInt8[4096]
    length = startup(pointerof(blob).as(UInt8*), 0_u64)
    result = done == size ? System.exec(Pointer(UInt8).new(image.to_u64!), size, argv, envp, pointerof(blob).as(UInt8*), length) : error(Errno::EIO)
    munmap(image.to_u64!, size)
    result
  end

  def self.waitpid(pid : Int64, status : Int32*, options : UInt64) : Int64
    target = pid == -1 ? Wait::ANY : pid.to_u64!
    return error(Errno::EINVAL) if pid == 0 || pid < -1
    code = 0_u64
    result = System.wait(target, pointerof(code), options & Wait::NOHANG)
    status.value = code.to_i32! if result > 0 && status.address != 0
    result
  end

  def self.ioctl(fd : UInt64, request : UInt64, argument : UInt8*) : Int64
    size = 0_u64
    size = 60_u64 if request >= 0x5401 && request <= 0x5404
    size = 8_u64 if request == 0x5413 || request == 0x5414
    size = 4_u64 if request == 0x540f || request == 0x5410
    message = uninitialized ABI::Message
    clear(pointerof(message), Op::IOCTL)
    message.b = request
    message.length = size
    request(fd, pointerof(message), argument, size)
  end

  def self.nanosleep(time : Int64*) : Int64
    ticks = time[0].to_u64! &* 100 &+ (time[1].to_u64! &+ 9999999).unsafe_div(10000000_u64)
    while ticks > 0
      step = ticks > 6000 ? 6000_u64 : ticks
      System.sleep(step)
      ticks = ticks &- step
    end
    0_i64
  end

  def self.uname(target : UInt8*) : Int64
    memset(target, 0, 390_u64)
    Text.copy(target, "Kristal".to_unsafe)
    Text.copy(target + 65_i64, "kristal".to_unsafe)
    Text.copy(target + 130_i64, "0.1".to_unsafe)
    Text.copy(target + 195_i64, "microkernel".to_unsafe)
    Text.copy(target + 260_i64, "x86_64".to_unsafe)
    0_i64
  end

  def self.exit(status : UInt64) : NoReturn
    System.exit(status)
  end
end
