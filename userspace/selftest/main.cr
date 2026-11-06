require "../lib/prelude"

def deep(depth : UInt64) : UInt64
  pad = uninitialized UInt8[4096]
  bytes = pointerof(pad).as(UInt8*)
  bytes[0] = depth.to_u8!
  return bytes[0].to_u64! if depth == 0
  deep(depth &- 1) &+ bytes[0].to_u64!
end

def main(argc : UInt64, argv : UInt8**) : Int32
  if argc > 1 && Text.equal?(argv[1], "exec")
    Out.print("selftest: running after execve\n")
    return 5
  end
  Out.print("selftest: connected through IPC\n")
  child = System.fork
  return 1 if child < 0
  if child == 0
    Out.print("selftest: child running\n")
    return 3
  end
  status = 0_u64
  return 1 if System.wait(child.to_u64!, pointerof(status)) != child || status != 3_u64 << 8
  Out.print("selftest: child exited with 3\n")
  return 1 if System.map(Layout::MAP, 8192_u64, 1_u64) != 0
  Pointer(UInt64).new(Layout::MAP &+ 4096).value = 42_u64
  return 1 if System.unmap(Layout::MAP, 8192_u64) != 0
  Out.print("selftest: mapped memory\n")
  return 1 if deep(200_u64) == 0
  Out.print("selftest: stack grew\n")
  round = 0_u64
  while round < 2
    System.sleep(20_u64)
    Out.print("selftest: work completed\n")
    round = round &+ 1
  end
  fd = Posix.open("/etc/../etc/motd".to_unsafe, 0_u64)
  return 1 if fd < 0
  text = uninitialized UInt8[128]
  count = Posix.read(fd.to_u64!, pointerof(text).as(UInt8*), 128_u64)
  return 1 if count <= 0
  Out.write(1_u64, pointerof(text).as(UInt8*), count.to_u64!)
  Posix.close(fd.to_u64!)
  directory = Posix.open("/bin".to_unsafe, Flag::DIRECTORY)
  return 1 if directory < 0
  entries = uninitialized UInt8[512]
  size = Posix.getdents(directory.to_u64!, pointerof(entries).as(UInt8*), 512_u64)
  return 1 if size <= 0
  offset = 0_i64
  while offset < size
    record = pointerof(entries).as(UInt8*) + offset
    Out.print("selftest: found /bin/")
    Out.print(record + 19_i64)
    Out.print("\n")
    offset = offset &+ (record + 16_i64).as(UInt16*).value.to_i64!
  end
  child = Posix.fork
  if child == 0
    args = uninitialized UInt8*[3]
    list = pointerof(args).as(UInt8**)
    list[0] = "selftest".to_unsafe
    list[1] = "exec".to_unsafe
    list[2] = Pointer(UInt8).new(0_u64)
    Posix.execve("/bin/selftest".to_unsafe, list, list + 2_i64)
    return 9
  end
  code = 0_i32
  return 1 if Posix.waitpid(child, pointerof(code), 0_u64) != child || code != 5 << 8
  Out.print("selftest: execve child exited with 5\n")
  base = Posix.brk(0_u64)
  return 1 if base <= 0 || Posix.brk(base.to_u64! &+ 10000) != base &+ 10000
  Pointer(UInt8).new(base.to_u64! &+ 9999).value = 1_u8
  Out.print("selftest: brk grew\n")
  Out.print("selftest: exiting\n")
  0
end
