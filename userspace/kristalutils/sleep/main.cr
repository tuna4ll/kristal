require "../../lib/prelude"

def main(argc : UInt64, argv : UInt8**) : Int32
  if argc < 2
    Out.print("usage: sleep seconds\n", 2_u64)
    return 1
  end
  seconds = 0_i64
  digits = argv[1]
  while digits.value >= 48 && digits.value <= 57
    seconds = seconds &* 10 &+ (digits.value &- 48).to_i64!
    digits += 1_i64
  end
  time = uninitialized Int64[2]
  pointerof(time).as(Int64*)[0] = seconds
  pointerof(time).as(Int64*)[1] = 0_i64
  Posix.nanosleep(pointerof(time).as(Int64*)) < 0 ? 1 : 0
end
