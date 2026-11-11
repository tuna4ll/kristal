require "../lib/prelude"

def main(argc : UInt64, argv : UInt8**) : Int32
  fd = 0_u64
  if argc > 2 || (argc == 2 && argv[1][0] != 45)
    opened = Posix.open(argv[argc &- 1], 0_u64)
    if opened < 0
      Out.print("wc: cannot open\n", 2_u64)
      return 1
    end
    fd = opened.to_u64!
  end
  option = argc > 1 && argv[1][0] == 45 ? argv[1][1] : 0_u8
  lines = 0_u64
  words = 0_u64
  bytes = 0_u64
  inside = false
  buffer = uninitialized UInt8[4096]
  while true
    count = Posix.read(fd, pointerof(buffer).as(UInt8*), 4096_u64)
    break if count <= 0
    i = 0_i64
    while i < count
      value = pointerof(buffer).as(UInt8*)[i]
      lines = lines &+ 1 if value == 10
      space = value == 32 || value == 10 || value == 9
      words = words &+ 1 if !space && !inside
      inside = !space
      i = i &+ 1
    end
    bytes = bytes &+ count.to_u64!
  end
  if option == 99
    Out.number(bytes)
  elsif option == 108
    Out.number(lines)
  elsif option == 119
    Out.number(words)
  else
    Out.number(lines)
    Out.print(" ")
    Out.number(words)
    Out.print(" ")
    Out.number(bytes)
  end
  Out.print("\n")
  0
end
