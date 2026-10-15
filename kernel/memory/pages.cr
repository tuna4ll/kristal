module Memory
  PAGE = 4096_u64
  MASK = 0x000ffffffffff000_u64
  NX   = 0x8000000000000000_u64
  @@offset = 0_u64
  @@map = Pointer(UInt64).new(0_u64)
  @@index = 0_u64
  @@next = 0_u64
  @@root = 0_u64

  def self.init(offset : UInt64, map : UInt64*)
    @@offset = offset
    @@map = map
  end

  def self.ptr(physical : UInt64)
    Pointer(UInt64).new(physical &+ @@offset)
  end

  def self.page : UInt64
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
          p = ptr(result)
          i = 0
          while i < 512
            p[i] = 0_u64
            i = i &+ 1
          end
          return result
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

  def self.address_space
    @@root = page
    old = ptr(Arch.read_cr3 & MASK)
    new = ptr(@@root)
    i = 256
    while i < 512
      new[i] = old[i] & ~4_u64
      i = i &+ 1
    end
    Arch.write_cr3(@@root)
  end

  def self.map(address : UInt64, physical : UInt64, flags : UInt64)
    table = ptr(@@root)
    shift = 39
    while shift > 12
      index = (address >> shift) & 511
      value = table[index]
      if value & 1 == 0
        value = page | 7_u64
        table[index] = value
      end
      panic("huge page in user table") if value & 128 != 0
      table = ptr(value & MASK)
      shift = shift &- 9
    end
    index = (address >> 12) & 511
    panic("overlapping user mapping") if table[index] & 1 != 0
    table[index] = physical | flags | 5_u64
  end

  def self.lookup(address : UInt64) : UInt64
    return 0_u64 if address < 0x10000 || address >= 0x80000000
    table = ptr(@@root)
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
end
