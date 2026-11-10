require "../lib/prelude"
require "../lib/tar"
require "./pipe"

lib FS
  struct Node
    name : UInt8*
    parent : UInt64
    mode : UInt32
    size : UInt64
    data : UInt8*
  end

  struct File
    node : UInt64
    offset : UInt64
    refs : UInt64
    pipe : UInt64
    side : UInt64
  end
end

# read only view of the initrd, plus /dev/console which is handed off to the console service
module Tree
  NODES = 512_u64
  FILES = 128_u64
  @@nodes = uninitialized FS::Node[512]
  @@files = uninitialized FS::File[128]
  @@names = uninitialized UInt8[65536]
  @@used = 0_u64
  @@count = 0_u64
  @@console = 0_u64

  def self.nodes : FS::Node*
    pointerof(@@nodes).as(FS::Node*)
  end

  def self.files : FS::File*
    pointerof(@@files).as(FS::File*)
  end

  def self.console : UInt64
    @@console
  end

  def self.add(name : UInt8*, mode : UInt32, size : UInt64, data : UInt8*) : UInt64
    return 0_u64 if @@count == NODES || @@used &+ Text.length(name) &+ 1 > 65536
    node = nodes + @@count.to_i64!
    node.value.name = pointerof(@@names).as(UInt8*) + @@used.to_i64!
    @@used = (Text.copy(node.value.name, name).address &- node.value.name.address) &+ 1 &+ @@used
    node.value.mode = mode
    node.value.size = size
    node.value.data = data
    @@count = @@count &+ 1
    @@count &- 1
  end

  def self.load(base : UInt8*, length : UInt64)
    scratch = uninitialized UInt8[260]
    name = pointerof(scratch).as(UInt8*)
    name[0] = 0_u8
    add(name, Mode::DIRECTORY | 0o755_u32, 0_u64, Pointer(UInt8).new(0_u64))
    Tar.each(base, length) do |header, size, data|
      Tar.name(header, name)
      next if name[0] == 0
      permission = Text.octal(header + 100_i64, 8_u64).to_u32! & 0o7777_u32
      if header[156] == 53
        add(name, Mode::DIRECTORY | permission, 0_u64, data) if lookup(name) == NODES
      elsif header[156] == 48 || header[156] == 0
        add(name, Mode::REGULAR | permission, size, data)
      end
    end
    add("dev".to_unsafe, Mode::DIRECTORY | 0o755_u32, 0_u64, data_none) if lookup("dev".to_unsafe) == NODES
    @@console = add("dev/console".to_unsafe, Mode::CHARACTER | 0o620_u32, 0_u64, data_none)
    i = 1_u64
    while i < @@count
      node = nodes + i.to_i64!
      node.value.parent = parent(node.value.name)
      i = i &+ 1
    end
  end

  def self.data_none : UInt8*
    Pointer(UInt8).new(0_u64)
  end

  def self.parent(name : UInt8*) : UInt64
    scratch = uninitialized UInt8[260]
    path = pointerof(scratch).as(UInt8*)
    Text.copy(path, name)
    cut = 0_u64
    i = 0_u64
    while path[i] != 0
      cut = i if path[i] == 47
      i = i &+ 1
    end
    path[cut] = 0_u8
    found = lookup(path)
    found == NODES ? 0_u64 : found
  end

  def self.lookup(path : UInt8*) : UInt64
    path += 1_i64 if path[0] == 47
    i = 0_u64
    while i < @@count
      return i if Text.equal?(nodes[i].name, path)
      i = i &+ 1
    end
    NODES
  end

  def self.directory?(index : UInt64) : Bool
    nodes[index].mode & Mode::TYPE == Mode::DIRECTORY
  end

  def self.open(node : UInt64) : UInt64
    i = 1_u64
    while i < FILES
      file = files + i.to_i64!
      if file.value.refs == 0
        file.value.node = node
        file.value.offset = 0_u64
        file.value.refs = 1_u64
        file.value.pipe = 0_u64
        file.value.side = 0_u64
        return i
      end
      i = i &+ 1
    end
    0_u64
  end

  def self.file(id : UInt64) : FS::File*
    return Pointer(FS::File).new(0_u64) if id == 0 || id >= FILES || files[id].refs == 0
    files + id.to_i64!
  end

  def self.stat(index : UInt64, target : UInt8*)
    memset(target, 0, sizeof(ABI::Stat).to_u64!)
    info = target.as(ABI::Stat*)
    node = nodes + index.to_i64!
    info.value.ino = index &+ 1
    info.value.nlink = 1_u64
    info.value.mode = node.value.mode
    info.value.size = node.value.size.to_i64!
    info.value.blksize = 512_i64
    info.value.blocks = ((node.value.size &+ 511) >> 9).to_i64!
    info.value.rdev = index == @@console ? 0x0501_u64 : 0_u64
  end

  # fills linux_dirent64 records, the file offset counts directory entries
  def self.entries(file : FS::File*, target : UInt8*, capacity : UInt64) : UInt64
    used = 0_u64
    position = 0_u64
    i = 1_u64
    while i < @@count
      node = nodes + i.to_i64!
      if node.value.parent == file.value.node
        if position >= file.value.offset
          base = node.value.name
          j = 0_u64
          while node.value.name[j] != 0
            base = node.value.name + (j &+ 1).to_i64! if node.value.name[j] == 47
            j = j &+ 1
          end
          length = Text.length(base)
          size = (19_u64 &+ length &+ 1 &+ 7) & ~7_u64
          break if used &+ size > capacity
          record = target + used.to_i64!
          memset(record, 0, size)
          record.as(UInt64*).value = i &+ 1
          (record + 8_i64).as(UInt64*).value = position &+ 1
          (record + 16_i64).as(UInt16*).value = size.to_u16!
          kind = node.value.mode & Mode::TYPE
          record[18] = kind == Mode::DIRECTORY ? 4_u8 : (kind == Mode::CHARACTER ? 2_u8 : 8_u8)
          memcpy(record + 19_i64, base, length)
          used = used &+ size
          file.value.offset = position &+ 1
        end
        position = position &+ 1
      end
      i = i &+ 1
    end
    used
  end
end

def fail(message : ABI::Message*, error : Int64)
  message.value.tag = (0_i64 &- error).to_u64!
end

# returns false when the answer has to wait for a pipe
def serve(sender : UInt64, message : ABI::Message*, data : UInt8*, capacity : UInt64) : Bool
  op = message.value.tag
  request = message.value.length
  message.value.length = 0_u64
  message.value.cap = 0_u64
  message.value.tag = 0_u64
  if op == Op::PIPE
    Pipes.create(message)
    return true
  end
  if op == Op::OPEN || op == Op::STAT
    return Pipes.fail_now(message, Errno::ENAMETOOLONG) if request == 0 || request >= capacity
    data[request] = 0_u8
    index = Tree.lookup(data)
    return Pipes.fail_now(message, Errno::ENOENT) if index == Tree::NODES
    if op == Op::STAT
      Tree.stat(index, data)
      message.value.length = sizeof(ABI::Stat).to_u64!
      return true
    end
    flags = message.value.a
    return Pipes.fail_now(message, Errno::ENOTDIR) if flags & Flag::DIRECTORY != 0 && !Tree.directory?(index)
    if index == Tree.console
      # the caller talks to the console service directly from now on
      message.value.cap = Posix.handles[1]
      message.value.b = 1_u64
      return true
    end
    return Pipes.fail_now(message, Errno::EISDIR) if flags & Flag::ACCESS != 0 && Tree.directory?(index)
    return Pipes.fail_now(message, Errno::EROFS) if flags & (Flag::ACCESS | Flag::CREATE | Flag::TRUNCATE) != 0
    id = Tree.open(index)
    return Pipes.fail_now(message, Errno::EMFILE) if id == 0
    message.value.tag = id
    return true
  end
  id = message.value.a
  file = Tree.file(id)
  return Pipes.fail_now(message, Errno::EBADF) if file.address == 0
  node = Tree.nodes + file.value.node.to_i64!
  if file.value.pipe != 0
    if op == Op::READ
      return Pipes.read(sender, file, id, message, data, capacity)
    elsif op == Op::WRITE
      return Pipes.write(sender, file, id, message, data, request)
    elsif op == Op::CLOSE
      file.value.refs = file.value.refs &- 1
      Pipes.release(file)
    elsif op == Op::DUP
      file.value.refs = file.value.refs &+ 1
    elsif op == Op::FSTAT
      memset(data, 0, sizeof(ABI::Stat).to_u64!)
      data.as(ABI::Stat*).value.mode = Mode::FIFO | 0o600_u32
      data.as(ABI::Stat*).value.nlink = 1_u64
      message.value.length = sizeof(ABI::Stat).to_u64!
    elsif op == Op::SEEK
      fail(message, Errno::ESPIPE)
    else
      fail(message, Errno::ENOTTY)
    end
    return true
  end
  if op == Op::READ
    return Pipes.fail_now(message, Errno::EISDIR) if Tree.directory?(file.value.node)
    count = message.value.b
    count = capacity if count > capacity
    left = node.value.size > file.value.offset ? node.value.size &- file.value.offset : 0_u64
    count = left if count > left
    memcpy(data, node.value.data + file.value.offset.to_i64!, count)
    file.value.offset = file.value.offset &+ count
    message.value.length = count
    message.value.tag = count
  elsif op == Op::WRITE
    fail(message, Errno::EROFS)
  elsif op == Op::CLOSE
    file.value.refs = file.value.refs &- 1
  elsif op == Op::DUP
    file.value.refs = file.value.refs &+ 1
  elsif op == Op::FSTAT
    Tree.stat(file.value.node, data)
    message.value.length = sizeof(ABI::Stat).to_u64!
  elsif op == Op::GETDENTS
    return Pipes.fail_now(message, Errno::ENOTDIR) unless Tree.directory?(file.value.node)
    count = message.value.b
    count = capacity if count > capacity
    message.value.length = Tree.entries(file, data, count)
    message.value.tag = message.value.length
  elsif op == Op::SEEK
    return Pipes.fail_now(message, Errno::ESPIPE) if Tree.directory?(file.value.node) && message.value.b != 0
    base = message.value.c == 0 ? 0_i64 : (message.value.c == 1 ? file.value.offset.to_i64! : node.value.size.to_i64!)
    return Pipes.fail_now(message, Errno::EINVAL) if message.value.c > 2
    position = base &+ message.value.b.to_i64!
    return Pipes.fail_now(message, Errno::EINVAL) if position < 0
    file.value.offset = position.to_u64!
    message.value.tag = file.value.offset
  else
    fail(message, Errno::ENOTTY)
  end
  true
end

def main(argc : UInt64, argv : UInt8**) : Int32
  service = Posix.service
  return 1 if service == 0
  region = uninitialized ABI::Region
  return 1 if System.device(Device::INITRD, pointerof(region).as(UInt8*)) != 0
  System.drop(Device::INITRD)
  Tree.load(Pointer(UInt8).new(region.address), region.length)
  message = uninitialized ABI::Message
  buffer = uninitialized UInt8[4096]
  data = pointerof(buffer).as(UInt8*)
  while true
    sender = System.receive(service, pointerof(message), data, 4096_u64)
    next if sender <= 0
    if serve(sender.to_u64!, pointerof(message), data, 4096_u64)
      System.reply(service, sender.to_u64!, pointerof(message), data)
    end
    Pipes.flush(service, pointerof(message), data)
  end
end
