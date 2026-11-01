require "../lib/prelude"
require "../lib/tar"

module Init
  ALL = Device::DISPLAY | Device::SERIAL | Device::KEYBOARD | Device::INITRD
  @@initrd = Pointer(UInt8).new(0_u64)
  @@length = 0_u64

  def self.load : Bool
    region = uninitialized ABI::Region
    return false if System.device(Device::INITRD, pointerof(region).as(UInt8*)) != 0
    @@initrd = Pointer(UInt8).new(region.address)
    @@length = region.length
    true
  end

  # the child keeps only the devices it is given and runs the image straight from the initrd
  def self.spawn(path : String, service : UInt64, devices : UInt64) : Int64
    pid = System.fork
    return pid if pid != 0
    System.drop(ALL & ~devices)
    size = 0_u64
    image = Tar.find(@@initrd, @@length, path.to_unsafe, pointerof(size))
    System.exit(127_u64) if image.address == 0
    args = uninitialized UInt8*[2]
    argv = pointerof(args).as(UInt8**)
    argv[0] = path.to_unsafe
    argv[1] = Pointer(UInt8).new(0_u64)
    blob = uninitialized UInt8[2048]
    data = pointerof(blob).as(UInt8*)
    length = Posix.startup(data, service)
    System.exec(image, size, argv, argv + 1_i64, data, length)
    System.exit(126_u64)
  end
end

def main(argc : UInt64, argv : UInt8**) : Int32
  return 1 unless Init.load
  console = System.endpoint
  return 1 if console < 0
  return 1 if Init.spawn("sbin/console", console.to_u64!, Device::DISPLAY | Device::SERIAL | Device::KEYBOARD) < 0
  client = System.copy(console.to_u64!, Right::CALL | Right::GRANT)
  return 1 if client < 0
  System.close(console.to_u64!)
  fd = 0_u64
  while fd < 3
    Posix.install(fd, client.to_u64!, 0_u64)
    fd = fd &+ 1
  end
  Out.print("Kristal: userspace console online\n")
  Out.print("Hello World from Userspace\n")
  worker = Init.spawn("bin/worker", 0_u64, 0_u64)
  return 1 if worker < 0
  Out.print("init: waiting for worker\n")
  status = 0_u64
  while true
    pid = System.wait(Wait::ANY, pointerof(status))
    return 1 if pid < 0
    break if pid == worker
  end
  if status == 0
    Out.print("init: worker exited normally\n")
  else
    Out.print("init: worker failed; kernel is still running\n")
  end
  status == 0 ? 0 : 1
end
