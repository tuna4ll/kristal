module Memory
  PAGE     =               4096_u64
  MASK     = 0x000ffffffffff000_u64
  NX       = 0x8000000000000000_u64
  WRITE    =                  2_u64
  BORROWED =              0x200_u64
  SPARE    =                 64_u64
  @@offset = 0_u64
  @@map = Pointer(UInt64).new(0_u64)
  @@index = 0_u64
  @@next = 0_u64
  @@kernel_root = 0_u64
  @@free = 0_u64
  @@used = 0_u64
  @@total = 0_u64

  def self.init(offset : UInt64, map : UInt64*)
    @@offset = offset
    @@map = map
    @@kernel_root = Arch.read_cr3 & MASK
    entries = Pointer(UInt64).new(map[2])
    i = 0_u64
    while i < map[1]
      entry = Pointer(UInt64).new(entries[i])
      if entry[2] == 0
        start = (entry[0] &+ 4095) & ~4095_u64
        finish = (entry[0] &+ entry[1]) & ~4095_u64
        @@total = @@total &+ ((finish &- start) >> 12) if finish > start
      end
      i = i &+ 1
    end
  end

  def self.ptr(physical : UInt64)
    Pointer(UInt64).new(physical &+ @@offset)
  end

  def self.clear_page(physical : UInt64) : UInt64
    memset(ptr(physical).as(UInt8*), 0, PAGE)
    @@used = @@used &+ 1
    physical
  end

  def self.free(physical : UInt64)
    ptr(physical).value = @@free
    @@free = physical
    @@used = @@used &- 1
  end

  def self.used : UInt64
    @@used
  end

  # user facing paths check this first so only the kernel itself can run out
  def self.reserve(count : UInt64) : Bool
    @@total > @@used &+ count &+ SPARE
  end

  def self.kernel_root : UInt64
    @@kernel_root
  end

  def self.bump : UInt64
    entries = Pointer(UInt64).new(@@map[2])
    while @@index < @@map[1]
      entry = Pointer(UInt64).new(entries[@@index])
      if entry[2] == 0
        start = (entry[0] &+ 4095) & ~4095_u64
        finish = (entry[0] &+ entry[1]) & ~4095_u64
        start = PAGE if start == 0
        @@next = start if @@next < start
        if @@next < finish
          result = @@next
          @@next = @@next &+ PAGE
          return clear_page(result)
        end
      end
      @@index = @@index &+ 1
      @@next = 0_u64
    end
    panic("out of physical memory")
  end

  def self.page : UInt64
    if @@free != 0
      result = @@free
      @@free = ptr(result).value
      return clear_page(result)
    end
    bump
  end

  def self.alloc : UInt64*
    ptr(page)
  end

  def self.alloc_pages(count : UInt64) : UInt64*
    first = bump
    found = 1_u64
    while found < count
      physical = bump
      if physical == first &+ (found << 12)
        found = found &+ 1
      else
        first = physical
        found = 1_u64
      end
    end
    ptr(first)
  end

  def self.create_space : UInt64
    root = page
    old = ptr(@@kernel_root)
    new = ptr(root)
    i = 256
    while i < 512
      new[i] = old[i] & ~4_u64
      i = i &+ 1
    end
    root
  end

  def self.init_space
    @@kernel_root = create_space
    Arch.write_cr3(@@kernel_root)
  end

  def self.walk(root : UInt64, address : UInt64, create : Bool, user : Bool = true) : UInt64*
    table = ptr(root)
    shift = 39
    while shift > 12
      index = (address >> shift) & 511
      value = table[index]
      if value & 1 == 0
        return Pointer(UInt64).new(0_u64) unless create
        value = page | 3_u64 | (user ? 4_u64 : 0_u64)
        table[index] = value
      end
      panic("huge page in user table") if value & 128 != 0
      table = ptr(value & MASK)
      shift = shift &- 9
    end
    table + ((address >> 12) & 511).to_i64!
  end

  def self.map(root : UInt64, address : UInt64, physical : UInt64, flags : UInt64, user : Bool = true)
    entry = walk(root, address, true, user)
    panic("overlapping mapping") if entry.value & 1 != 0
    entry.value = physical | flags | 1_u64 | (user ? 4_u64 : 0_u64)
  end

  def self.unmap(root : UInt64, address : UInt64) : Bool
    entry = walk(root, address, false)
    return false if entry.address == 0 || entry.value & 1 == 0
    value = entry.value
    entry.value = 0_u64
    Arch.invalidate(address) if root == Arch.read_cr3 & MASK
    free(value & MASK) if value & BORROWED == 0
    true
  end

  def self.lookup(root : UInt64, address : UInt64) : UInt64
    return 0_u64 if address < Layout::IMAGE || address >= Layout::END
    table = ptr(root)
    shift = 39
    while shift >= 12
      value = table[(address >> shift) & 511]
      return 0_u64 if value & 5 != 5 || (shift > 12 && value & 128 != 0)
      return value if shift == 12
      table = ptr(value & MASK)
      shift = shift &- 9
    end
    0_u64
  end

  def self.access(root : UInt64, address : UInt64, length : UInt64, write : Bool) : Bool
    return false if address < Layout::IMAGE || address >= Layout::END || length > Layout::END &- address
    return true if length == 0
    page = address & ~4095_u64
    last = (address &+ length &- 1) & ~4095_u64
    while page <= last
      entry = lookup(root, page)
      return false if entry == 0 || (write && entry & WRITE == 0)
      page = page &+ PAGE
    end
    true
  end

  def self.user_pointer(root : UInt64, address : UInt64) : UInt8*
    Pointer(UInt8).new((lookup(root, address) & MASK) &+ @@offset &+ (address & 4095))
  end

  def self.copy_user(root : UInt64, address : UInt64, buffer : UInt8*, length : UInt64, to_user : Bool) : Bool
    return false unless access(root, address, length, to_user)
    done = 0_u64
    while done < length
      current = address &+ done
      count = PAGE &- (current & 4095)
      count = length &- done if count > length &- done
      if to_user
        memcpy(user_pointer(root, current), buffer + done.to_i64!, count)
      else
        memcpy(buffer + done.to_i64!, user_pointer(root, current), count)
      end
      done = done &+ count
    end
    true
  end

  # a zero source root means the source is kernel memory
  def self.copy_between(source_root : UInt64, source : UInt64, root : UInt64, address : UInt64, length : UInt64) : Bool
    return copy_user(root, address, Pointer(UInt8).new(source), length, true) if source_root == 0
    return false unless access(source_root, source, length, false) && access(root, address, length, true)
    done = 0_u64
    while done < length
      count = PAGE &- ((source &+ done) & 4095)
      other = PAGE &- ((address &+ done) & 4095)
      count = other if other < count
      count = length &- done if count > length &- done
      memcpy(user_pointer(root, address &+ done), user_pointer(source_root, source &+ done), count)
      done = done &+ count
    end
    true
  end

  def self.string_length(root : UInt64, address : UInt64, limit : UInt64) : Int64
    length = 0_u64
    while length < limit
      if root == 0
        return length.to_i64! if Pointer(UInt8).new(address &+ length).value == 0
      else
        return -1_i64 unless access(root, address &+ length, 1_u64, false)
        return length.to_i64! if user_pointer(root, address &+ length).value == 0
      end
      length = length &+ 1
    end
    -1_i64
  end

  def self.physical(address : UInt64) : UInt64
    address &- @@offset
  end

  def self.cache_flags(address : UInt64) : UInt64
    table = ptr(@@kernel_root)
    shift = 39
    while shift >= 12
      entry = table[(address >> shift) & 511]
      panic("unmapped device") if entry & 1 == 0
      return entry & 0x98_u64 if shift == 12
      if entry & 128 != 0
        return (entry & 0x18_u64) | ((entry >> 5) & 0x80_u64)
      end
      table = ptr(entry & MASK)
      shift = shift &- 9
    end
    0_u64
  end

  def self.unmap_stack(address : UInt64)
    entry = walk(@@kernel_root, address, false, false)
    physical = entry.value & MASK
    entry.value = 0_u64
    Arch.invalidate(address)
    free(physical)
  end

  def self.count_table(physical : UInt64, level : Int32) : UInt64
    table = ptr(physical)
    total = 1_u64
    i = 0
    while i < 512
      entry = table[i]
      if entry & 1 != 0
        if level == 1
          total = total &+ 1 if entry & BORROWED == 0
        else
          total = total &+ count_table(entry & MASK, level &- 1)
        end
      end
      i = i &+ 1
    end
    total
  end

  def self.count(root : UInt64) : UInt64
    table = ptr(root)
    total = 1_u64
    i = 0
    while i < 256
      total = total &+ count_table(table[i] & MASK, 3) if table[i] & 1 != 0
      i = i &+ 1
    end
    total
  end

  def self.clone_table(physical : UInt64, level : Int32, base : UInt64, root : UInt64)
    table = ptr(physical)
    i = 0_u64
    while i < 512
      entry = table[i]
      address = base | (i << (12 &+ (level &- 1) &* 9))
      if entry & 1 != 0
        if level > 1
          clone_table(entry & MASK, level &- 1, address, root)
        elsif entry & BORROWED != 0
          walk(root, address, true).value = entry
        else
          copy = page
          memcpy(ptr(copy).as(UInt8*), ptr(entry & MASK).as(UInt8*), PAGE)
          walk(root, address, true).value = copy | (entry & ~MASK)
        end
      end
      i = i &+ 1
    end
  end

  def self.clone_space(source : UInt64) : UInt64
    root = create_space
    table = ptr(source)
    i = 0_u64
    while i < 256
      clone_table(table[i] & MASK, 3, i << 39, root) if table[i] & 1 != 0
      i = i &+ 1
    end
    root
  end

  def self.free_table(physical : UInt64, level : Int32)
    table = ptr(physical)
    i = 0
    while i < 512
      entry = table[i]
      if entry & 1 != 0
        panic("huge page in process") if level > 1 && entry & 128 != 0
        if level == 1
          free(entry & MASK) if entry & BORROWED == 0
        else
          free_table(entry & MASK, level &- 1)
        end
      end
      i = i &+ 1
    end
    free(physical)
  end

  def self.destroy_space(root : UInt64)
    panic("freeing active address space") if root == (Arch.read_cr3 & MASK) || root == @@kernel_root
    table = ptr(root)
    i = 0
    while i < 256
      entry = table[i]
      free_table(entry & MASK, 3) if entry & 1 != 0
      i = i &+ 1
    end
    free(root)
  end
end
