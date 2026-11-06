require "../lib/prelude"

def main(argc : UInt64, argv : UInt8**) : Int32
  info = uninitialized UInt8[390]
  fields = pointerof(info).as(UInt8*)
  Posix.uname(fields)
  if argc > 1 && Text.equal?(argv[1], "-a")
    i = 0
    while i < 5
      Out.print(" ") if i > 0
      Out.print(fields + (i &* 65).to_i64!)
      i = i &+ 1
    end
  else
    Out.print(fields)
  end
  Out.print("\n")
  0
end
