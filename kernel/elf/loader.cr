module ELF
  MIN   = Layout::IMAGE
  MAX   = Layout::IMAGE_END
  STACK = Layout::STACK

  def self.number(data : UInt8*, offset : UInt64, width : Int32) : UInt64
    value = 0_u64
    i = 0
    while i < width
      value = value | (data[offset &+ i.to_u64!].to_u64! << (i &* 8))
      i = i &+ 1
    end
    value
  end

  def self.load(root : UInt64, data : UInt8*, size : UInt64) : UInt64
    panic("ELF header") if size < 64
    panic("ELF magic") if number(data, 0_u64, 4) != 0x464c457f
    panic("ELF format") if data[4] != 2 || data[5] != 1 || data[6] != 1
    panic("ELF type") if number(data, 16_u64, 2) != 2 || number(data, 18_u64, 2) != 62 || number(data, 20_u64, 4) != 1
    panic("ELF header size") if number(data, 52_u64, 2) != 64 || number(data, 54_u64, 2) != 56
    entry = number(data, 24_u64, 8)
    phoff = number(data, 32_u64, 8)
    count = number(data, 56_u64, 2)
    panic("ELF program headers") if count == 0 || count > 64 || phoff > size || (count &* 56) > size &- phoff
    shoff = number(data, 40_u64, 8)
    shnum = number(data, 60_u64, 2)
    if shoff != 0
      panic("ELF sections") if shnum == 0 || number(data, 58_u64, 2) != 64 || shoff > size || (shnum &* 64) > size &- shoff
      i = 0_u64
      while i < shnum
        kind = number(data, shoff &+ (i &* 64) &+ 4, 4)
        panic("ELF relocations") if kind == 4 || kind == 9 || kind == 19
        i = i &+ 1
      end
    elsif shnum != 0
      panic("ELF sections")
    end
    executable = false
    total = 0_u64
    i = 0_u64
    while i < count
      ph = phoff &+ (i &* 56)
      kind = number(data, ph, 4)
      panic("ELF dynamic or TLS") if kind == 2 || kind == 3 || kind == 7
      if kind == 1
        flags = number(data, ph &+ 4, 4)
        offset = number(data, ph &+ 8, 8)
        address = number(data, ph &+ 16, 8)
        filesz = number(data, ph &+ 32, 8)
        memsz = number(data, ph &+ 40, 8)
        align = number(data, ph &+ 48, 8)
        panic("ELF file bounds") if filesz > memsz || offset > size || filesz > size &- offset
        panic("ELF address") if address < MIN || address >= MAX || memsz > MAX &- address
        panic("ELF permissions") if flags & ~7_u64 != 0 || flags & 4 == 0 || flags & 3 == 3
        if align > 1
          panic("ELF alignment") if align & (align &- 1) != 0 || address & (align &- 1) != offset & (align &- 1)
        end
        panic("ELF page alignment") if address & 4095 != 0
        total = total &+ memsz
        panic("ELF too large") if total > 16_u64 << 20
        if memsz != 0
          executable = true if flags & 1 != 0 && entry >= address && entry < address &+ filesz
          pos = 0_u64
          while pos < memsz
            physical = Memory.page
            dest = Memory.ptr(physical).as(UInt8*)
            j = 0_u64
            while j < 4096 && pos &+ j < filesz
              dest[j] = data[offset &+ pos &+ j]
              j = j &+ 1
            end
            permission = flags & 2 != 0 ? 2_u64 : 0_u64
            permission = permission | Memory::NX if flags & 1 == 0
            Memory.map(root, address &+ pos, physical, permission)
            pos = pos &+ 4096
          end
        end
      end
      i = i &+ 1
    end
    panic("ELF entry") unless executable
    pos = STACK &- 16384
    while pos < STACK
      Memory.map(root, pos, Memory.page, Memory::NX | 2_u64)
      pos = pos &+ 4096
    end
    entry
  end
end
