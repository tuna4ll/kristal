module Memory
  PAGE =               4096_u64
  MASK = 0x000ffffffffff000_u64
  NX   = 0x8000000000000000_u64
  @@offset = 0_u64
  @@map = Pointer(UInt64).new(0_u64)
  @@index = 0_u64
  @@next = 0_u64
  @@kernel_root = 0_u64
  @@free = 0_u64
  @@used = 0_u64

  def self.init(offset : UInt64, map : UInt64*)
    @@offset = offset
    @@map = map
    @@kernel_root = Arch.read_cr3 & MASK
  end

  def self.ptr(physical : UInt64)
    Pointer(UInt64).new(physical &+ @@offset)
  end

  def self.clear_page(physical : UInt64) : UInt64
    p = ptr(physical)
    i = 0
    while i < 512
      p[i] = 0_u64
      i = i &+ 1
    end
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

  def self.kernel_root : UInt64
    @@kernel_root
  end

  def self.page : UInt64
    if @@free != 0
      result = @@free
      @@free = ptr(result).value
      return clear_page(result)
    end
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

  def self.alloc : UInt64*
    ptr(page)
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

  def self.map(root : UInt64, address : UInt64, physical : UInt64, flags : UInt64, user : Bool = true)
    table = ptr(root)
    shift = 39
    while shift > 12
      index = (address >> shift) & 511
      value = table[index]
      if value & 1 == 0
        value = page | 3_u64 | (user ? 4_u64 : 0_u64)
        table[index] = value
      end
      panic("huge page in user table") if value & 128 != 0
      table = ptr(value & MASK)
      shift = shift &- 9
    end
    index = (address >> 12) & 511
    panic("overlapping mapping") if table[index] & 1 != 0
    table[index] = physical | flags | 1_u64 | (user ? 4_u64 : 0_u64)
  end

  def self.lookup(root : UInt64, address : UInt64) : UInt64
    return 0_u64 if address < 0x10000 || address >= 0x80000000
    table = ptr(root)
    shift = 39
    while shift >= 12
      value = table[(address >> shift) & 511]
      return 0_u64 if value & 5 != 5 || value & 128 != 0
      return value if shift == 12
      table = ptr(value & MASK)
      shift = shift &- 9
    end
    0_u64
  end

  def self.unmap_stack(address : UInt64)
    table = ptr(@@kernel_root)
    shift = 39
    while shift > 12
      table = ptr(table[(address >> shift) & 511] & MASK)
      shift = shift &- 9
    end
    index = (address >> 12) & 511
    physical = table[index] & MASK
    table[index] = 0_u64
    Arch.invalidate(address)
    free(physical)
  end

  def self.free_table(physical : UInt64, level : Int32)
    table = ptr(physical)
    i = 0
    while i < 512
      entry = table[i]
      if entry & 1 != 0
        panic("huge page in process") if entry & 128 != 0
        if level == 1
          free(entry & MASK)
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
