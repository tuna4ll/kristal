require "../lib/prelude"

def deep(depth : UInt64) : UInt64
  pad = uninitialized UInt8[4096]
  bytes = pointerof(pad).as(UInt8*)
  bytes[0] = depth.to_u8!
  return bytes[0].to_u64! if depth == 0
  deep(depth &- 1) &+ bytes[0].to_u64!
end

def main(argc : UInt64, argv : UInt8**) : Int32
  Out.print("worker: connected through IPC\n")
  child = System.fork
  return 1 if child < 0
  if child == 0
    Out.print("worker: child running\n")
    return 3
  end
  status = 0_u64
  return 1 if System.wait(child.to_u64!, pointerof(status)) != child || status != 3_u64 << 8
  Out.print("worker: child exited with 3\n")
  return 1 if System.map(Layout::MAP, 8192_u64, 1_u64) != 0
  Pointer(UInt64).new(Layout::MAP &+ 4096).value = 42_u64
  return 1 if System.unmap(Layout::MAP, 8192_u64) != 0
  Out.print("worker: mapped memory\n")
  return 1 if deep(200_u64) == 0
  Out.print("worker: stack grew\n")
  round = 0_u64
  while round < 2
    System.sleep(20_u64)
    Out.print("worker: work completed\n")
    round = round &+ 1
  end
  Out.print("worker: exiting\n")
  0
end
