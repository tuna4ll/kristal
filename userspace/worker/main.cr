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
    Out.print("worker: found /bin/")
    Out.print(record + 19_i64)
    Out.print("\n")
    offset = offset &+ (record + 16_i64).as(UInt16*).value.to_i64!
  end
  Out.print("worker: exiting\n")
  0
end
