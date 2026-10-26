module ELF
  MAX_ARGS    =   1024_u64
  MAX_STRINGS = 131072_u64
  MAX_DATA    =  65536_u64
  @@entry = 0_u64
  @@phdr = 0_u64
  @@phnum = 0_u64

  def self.number(data : UInt8*, offset : UInt64, width : Int32) : UInt64
    value = 0_u64
    i = 0
    while i < width
      value = value | (data[offset &+ i.to_u64!].to_u64! << (i &* 8))
      i = i &+ 1
    end
    value
  end

  # a zero source root means the image lives in kernel memory
  def self.read(source : UInt64, data : UInt64, offset : UInt64, buffer : UInt8*, count : UInt64) : Bool
    if source == 0
      memcpy(buffer, Pointer(UInt8).new(data &+ offset), count)
      return true
    end
    Memory.copy_user(source, data &+ offset, buffer, count, false)
  end

  def self.fail(error : Int64) : Int64
    0_i64 &- error
  end

  def self.load(root : UInt64, source : UInt64, data : UInt64, size : UInt64) : Int64
    raw = uninitialized UInt8[64]
    header = pointerof(raw).as(UInt8*)
    return fail(Errno::ENOEXEC) if size < 64
    return fail(Errno::EFAULT) unless read(source, data, 0_u64, header, 64_u64)
    return fail(Errno::ENOEXEC) if number(header, 0_u64, 4) != 0x464c457f
    return fail(Errno::ENOEXEC) if header[4] != 2 || header[5] != 1 || header[6] != 1
    return fail(Errno::ENOEXEC) if number(header, 16_u64, 2) != 2 || number(header, 18_u64, 2) != 62 || number(header, 20_u64, 4) != 1
    return fail(Errno::ENOEXEC) if number(header, 52_u64, 2) != 64 || number(header, 54_u64, 2) != 56
    entry = number(header, 24_u64, 8)
    phoff = number(header, 32_u64, 8)
    count = number(header, 56_u64, 2)
    return fail(Errno::ENOEXEC) if count == 0 || count > 64 || phoff > size || (count &* 56) > size &- phoff
    shoff = number(header, 40_u64, 8)
    shnum = number(header, 60_u64, 2)
    if shoff != 0
      return fail(Errno::ENOEXEC) if shnum == 0 || number(header, 58_u64, 2) != 64 || shoff > size || (shnum &* 64) > size &- shoff
      i = 0_u64
      while i < shnum
        return fail(Errno::EFAULT) unless read(source, data, shoff &+ (i &* 64), header, 8_u64)
        kind = number(header, 4_u64, 4)
        return fail(Errno::ENOEXEC) if kind == 4 || kind == 9 || kind == 19
        i = i &+ 1
      end
    elsif shnum != 0
      return fail(Errno::ENOEXEC)
    end
    pages = 0_u64
    executable = false
    @@phdr = 0_u64
    i = 0_u64
    while i < count
      return fail(Errno::EFAULT) unless read(source, data, phoff &+ (i &* 56), header, 56_u64)
      kind = number(header, 0_u64, 4)
      return fail(Errno::ENOEXEC) if kind == 2 || kind == 3
      flags = number(header, 4_u64, 4)
      offset = number(header, 8_u64, 8)
      address = number(header, 16_u64, 8)
      filesz = number(header, 32_u64, 8)
      memsz = number(header, 40_u64, 8)
      align = number(header, 48_u64, 8)
      @@phdr = address if kind == 6
      if kind == 1
        return fail(Errno::ENOEXEC) if filesz > memsz || offset > size || filesz > size &- offset
        return fail(Errno::ENOEXEC) if address < Layout::IMAGE || address >= Layout::IMAGE_END || memsz > Layout::IMAGE_END &- address
        return fail(Errno::ENOEXEC) if flags & ~7_u64 != 0 || flags & 4 == 0 || flags & 3 == 3
        return fail(Errno::ENOEXEC) if address & 4095 != offset & 4095
        if align > 1
          return fail(Errno::ENOEXEC) if align & (align &- 1) != 0 || address & (align &- 1) != offset & (align &- 1)
        end
        @@phdr = address &+ (phoff &- offset) if @@phdr == 0 && phoff >= offset && phoff < offset &+ filesz
        executable = true if flags & 1 != 0 && entry >= address && entry < address &+ memsz
        pages = pages &+ ((((address &+ memsz &+ 4095) & ~4095_u64) &- (address & ~4095_u64)) >> 12)
      end
      i = i &+ 1
    end
    return fail(Errno::ENOEXEC) unless executable
    return fail(Errno::ENOMEM) unless Memory.reserve(pages &+ (pages >> 9) &+ 16)
    i = 0_u64
    while i < count
      read(source, data, phoff &+ (i &* 56), header, 56_u64)
      if number(header, 0_u64, 4) == 1
        segment(root, source, data, header)
      end
      i = i &+ 1
    end
    @@entry = entry
    @@phnum = count
    entry.to_i64!
  end

  # segments may start mid page and share a page with their neighbour
  def self.segment(root : UInt64, source : UInt64, data : UInt64, header : UInt8*)
    flags = number(header, 4_u64, 4)
    offset = number(header, 8_u64, 8)
    address = number(header, 16_u64, 8)
    filesz = number(header, 32_u64, 8)
    memsz = number(header, 40_u64, 8)
    page = address & ~4095_u64
    finish = address &+ memsz
    while page < finish
      entry = Memory.walk(root, page, true)
      if entry.value & 1 == 0
        entry.value = Memory.page | Memory::NX | 5_u64
      end
      entry.value = entry.value | Memory::WRITE if flags & 2 != 0
      entry.value = entry.value & ~Memory::NX if flags & 1 != 0
      low = page < address ? address : page
      high = page &+ 4096
      high = address &+ filesz if high > address &+ filesz
      if low < high
        target = Memory.ptr(entry.value & Memory::MASK).as(UInt8*) + (low &- page).to_i64!
        read(source, data, offset &+ (low &- address), target, high &- low)
      end
      page = page &+ 4096
    end
  end

  def self.fetch(root : UInt64, address : UInt64, value : UInt64*) : Bool
    if root == 0
      value.value = Pointer(UInt64).new(address).value
      return true
    end
    Memory.copy_user(root, address, value.as(UInt8*), 8_u64, false)
  end

  def self.measure(source : UInt64, list : UInt64, count : UInt64*, bytes : UInt64*) : Bool
    return true if list == 0
    while true
      pointer = 0_u64
      return false unless fetch(source, list &+ (count.value << 3), pointerof(pointer))
      return true if pointer == 0
      length = Memory.string_length(source, pointer, MAX_STRINGS)
      return false if length < 0
      count.value = count.value &+ 1
      bytes.value = bytes.value &+ length.to_u64! &+ 1
      return false if count.value > MAX_ARGS || bytes.value > MAX_STRINGS
    end
  end

  def self.store(root : UInt64, address : UInt64, value : UInt64)
    Memory.copy_user(root, address, pointerof(value).as(UInt8*), 8_u64, true)
  end

  def self.strings(root : UInt64, source : UInt64, list : UInt64, count : UInt64, slots : UInt64, cursor : UInt64) : UInt64
    i = 0_u64
    while i < count
      pointer = 0_u64
      fetch(source, list &+ (i << 3), pointerof(pointer))
      length = Memory.string_length(source, pointer, MAX_STRINGS).to_u64! &+ 1
      Memory.copy_between(source, pointer, root, cursor, length)
      store(root, slots &+ (i << 3), cursor)
      cursor = cursor &+ length
      i = i &+ 1
    end
    store(root, slots &+ (count << 3), 0_u64)
    cursor
  end

  # builds the initial stack the sysv abi describes: argc, argv, envp, auxv
  def self.stack(root : UInt64, source : UInt64, argv : UInt64, envp : UInt64, data : UInt64, length : UInt64) : Int64
    argc = 0_u64
    envc = 0_u64
    bytes = 0_u64
    return fail(Errno::E2BIG) unless measure(source, argv, pointerof(argc), pointerof(bytes))
    return fail(Errno::E2BIG) unless measure(source, envp, pointerof(envc), pointerof(bytes))
    return fail(Errno::E2BIG) if length > MAX_DATA
    return fail(Errno::EFAULT) unless source == 0 || length == 0 || Memory.access(source, data, length, false)
    info = (Layout::STACK &- (bytes &+ length &+ 16)) & ~15_u64
    words = 3_u64 &+ argc &+ envc &+ 18
    sp = (info &- (words << 3)) & ~15_u64
    bottom = (sp & ~4095_u64) &- 16384
    return fail(Errno::ENOMEM) unless Memory.reserve((Layout::STACK &- bottom) >> 12)
    page = bottom
    while page < Layout::STACK
      entry = Memory.walk(root, page, true)
      entry.value = Memory.page | Memory::NX | Memory::WRITE | 5_u64 if entry.value & 1 == 0
      page = page &+ 4096
    end
    store(root, sp, argc)
    cursor = strings(root, source, argv, argc, sp &+ 8, info)
    cursor = strings(root, source, envp, envc, sp &+ 16 &+ (argc << 3), cursor)
    random = cursor
    store(root, random, Timer.ticks &* 0x9e3779b97f4a7c15_u64)
    store(root, random &+ 8, (random ^ @@entry) &* 0xbf58476d1ce4e5b9_u64)
    blob = random &+ 16
    Memory.copy_between(source, data, root, blob, length) if length != 0
    aux = sp &+ 24 &+ ((argc &+ envc) << 3)
    aux = auxiliary(root, aux, Aux::PHDR, @@phdr)
    aux = auxiliary(root, aux, Aux::PHENT, 56_u64)
    aux = auxiliary(root, aux, Aux::PHNUM, @@phnum)
    aux = auxiliary(root, aux, Aux::PAGESZ, 4096_u64)
    aux = auxiliary(root, aux, Aux::ENTRY, @@entry)
    aux = auxiliary(root, aux, Aux::RANDOM, random)
    aux = auxiliary(root, aux, Aux::DATA, length == 0 ? 0_u64 : blob)
    aux = auxiliary(root, aux, Aux::SIZE, length)
    auxiliary(root, aux, 0_u64, 0_u64)
    sp.to_i64!
  end

  def self.auxiliary(root : UInt64, address : UInt64, key : UInt64, value : UInt64) : UInt64
    store(root, address, key)
    store(root, address &+ 8, value)
    address &+ 16
  end
end
