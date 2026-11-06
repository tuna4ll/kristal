require "../lib/prelude"

def copy(fd : UInt64) : Bool
  buffer = uninitialized UInt8[4096]
  while true
    count = Posix.read(fd, pointerof(buffer).as(UInt8*), 4096_u64)
    return count == 0 if count <= 0
    Out.write(1_u64, pointerof(buffer).as(UInt8*), count.to_u64!)
  end
end

def main(argc : UInt64, argv : UInt8**) : Int32
  return copy(0_u64) ? 0 : 1 if argc < 2
  status = 0
  i = 1_u64
  while i < argc
    fd = Posix.open(argv[i], 0_u64)
    if fd < 0
      Out.print("cat: ", 2_u64)
      Out.print(argv[i], 2_u64)
      Out.print(": cannot open\n", 2_u64)
      status = 1
    else
      status = 1 unless copy(fd.to_u64!)
      Posix.close(fd.to_u64!)
    end
    i = i &+ 1
  end
  status
end
