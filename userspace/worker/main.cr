require "../syscall"

def deep(depth : UInt64) : UInt64
  pad = uninitialized UInt8[4096]
  bytes = pointerof(pad).as(UInt8*)
  bytes[0] = depth.to_u8!
  return bytes[0].to_u64! if depth == 0
  deep(depth &- 1) &+ bytes[0].to_u64!
end

fun user_main : NoReturn
  User.write("worker: connected through IPC\n")
  child = User.invoke(Sys::FORK)
  User.exit(1_u64) if child < 0
  if child == 0
    User.write("worker: child running\n")
    User.exit(3_u64)
  end
  status = 0_u64
  User.exit(1_u64) if User.wait(child.to_u64!, pointerof(status)) != child || status != 3_u64 << 8
  User.write("worker: child exited with 3\n")
  User.exit(1_u64) if User.invoke(Sys::MAP, Layout::MAP, 8192_u64, 1_u64) != 0
  Pointer(UInt64).new(Layout::MAP &+ 4096).value = 42_u64
  User.exit(1_u64) if User.invoke(Sys::UNMAP, Layout::MAP, 8192_u64) != 0
  User.write("worker: mapped memory\n")
  User.exit(1_u64) if deep(200_u64) == 0
  User.write("worker: stack grew\n")
  round = 0_u64
  while round < 2
    User.sleep(20_u64)
    User.write("worker: work completed\n")
    round = round &+ 1
  end
  User.write("worker: exiting\n")
  User.exit(0_u64)
end
