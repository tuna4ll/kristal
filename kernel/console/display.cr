module Display
  BASE = 0x60000000_u64
  @@address = 0_u64
  @@width = 0_u64
  @@height = 0_u64
  @@pitch = 0_u64
  @@red = 0_u64
  @@green = 0_u64
  @@blue = 0_u64

  def self.init(response : UInt64*)
    return if response.address == 0 || response[1] == 0
    fb = Pointer(UInt64).new(Pointer(UInt64).new(response[2])[0])
    info = fb.as(UInt8*)
    return if info[32] != 32 || info[33] != 0 || info[34] != 1
    return if info[35] != 8 || info[37] != 8 || info[39] != 8
    return unless Screen.init(fb[0], fb[1], fb[2], fb[3], info[36].to_u64!, info[38].to_u64!, info[40].to_u64!)
    @@address = fb[0]
    @@width = fb[1]
    @@height = fb[2]
    @@pitch = fb[3]
    @@red = info[36].to_u64!
    @@green = info[38].to_u64!
    @@blue = info[40].to_u64!
  end

  def self.grant(root : UInt64)
    return if @@address == 0
    start = @@address & ~4095_u64
    length = ((@@address & 4095) &+ (@@pitch &* @@height) &+ 4095) & ~4095_u64
    offset = 0_u64
    while offset < length
      flags = Memory::NX | Memory::BORROWED | 2_u64 | Memory.cache_flags(start &+ offset)
      Memory.map(root, BASE &+ offset, Memory.physical(start &+ offset), flags)
      offset = offset &+ Memory::PAGE
    end
  end

  def self.info(address : UInt64) : Int64
    return 0_i64 &- Errno::EPERM if Processes.current.value.devices & 1 == 0
    return 0_i64 &- Errno::ENODEV if @@address == 0
    info = uninitialized ABI::Display
    info.address = BASE &+ (@@address & 4095)
    info.width = @@width
    info.height = @@height
    info.pitch = @@pitch
    info.red = @@red
    info.green = @@green
    info.blue = @@blue
    info.length = @@pitch &* @@height
    return 0_i64 &- Errno::EFAULT unless Memory.copy_user(Processes.root, address, pointerof(info).as(UInt8*), 64_u64, true)
    0_i64
  end
end
