require "../lib/prelude"

def mode(value : UInt32)
  kind = value & Mode::TYPE
  text = uninitialized UInt8[11]
  bits = pointerof(text).as(UInt8*)
  bits[0] = kind == Mode::DIRECTORY ? 100_u8 : (kind == Mode::CHARACTER ? 99_u8 : 45_u8)
  letters = "rwxrwxrwx".to_unsafe
  i = 0
  while i < 9
    bits[i &+ 1] = value & (0o400_u32 >> i) != 0 ? letters[i] : 45_u8
    i = i &+ 1
  end
  bits[10] = 32_u8
  Out.write(1_u64, bits, 11_u64)
end

def show(directory : UInt8*, name : UInt8*, long : Bool)
  if long
    scratch = uninitialized UInt8[256]
    path = pointerof(scratch).as(UInt8*)
    cursor = Text.copy(path, directory)
    cursor.value = 47_u8
    Text.copy(cursor + 1_i64, name)
    info = uninitialized ABI::Stat
    if Posix.stat(path, pointerof(info).as(UInt8*)) == 0
      mode(info.mode)
      Out.number(info.size.to_u64!)
      Out.print(" ")
    end
  end
  Out.print(name)
  Out.print("\n")
end

def list(path : UInt8*, long : Bool) : Bool
  fd = Posix.open(path, Flag::DIRECTORY)
  if fd < 0
    Out.print("ls: ", 2_u64)
    Out.print(path, 2_u64)
    Out.print(": cannot open\n", 2_u64)
    return false
  end
  buffer = uninitialized UInt8[2048]
  entries = pointerof(buffer).as(UInt8*)
  while true
    size = Posix.getdents(fd.to_u64!, entries, 2048_u64)
    break if size <= 0
    offset = 0_i64
    while offset < size
      record = entries + offset
      show(path, record + 19_i64, long)
      offset = offset &+ (record + 16_i64).as(UInt16*).value.to_i64!
    end
  end
  Posix.close(fd.to_u64!)
  true
end

def main(argc : UInt64, argv : UInt8**) : Int32
  long = false
  first = 1_u64
  if argc > 1 && Text.equal?(argv[1], "-l")
    long = true
    first = 2_u64
  end
  return list(".".to_unsafe, long) ? 0 : 1 if first >= argc
  status = 0
  i = first
  while i < argc
    status = 1 unless list(argv[i], long)
    i = i &+ 1
  end
  status
end
