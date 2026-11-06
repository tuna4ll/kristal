require "../lib/prelude"

def main(argc : UInt64, argv : UInt8**) : Int32
  first = 1_u64
  newline = true
  if argc > 1 && Text.equal?(argv[1], "-n")
    newline = false
    first = 2_u64
  end
  i = first
  while i < argc
    Out.print(" ") if i > first
    Out.print(argv[i])
    i = i &+ 1
  end
  Out.print("\n") if newline
  0
end
