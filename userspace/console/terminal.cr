# line discipline and the termios state behind it, kept in the linux kernel layout
module Terminal
  ICRNL   = 0x100_u32
  ISIG    =   0x1_u32
  ICANON  =   0x2_u32
  ECHO    =   0x8_u32
  READERS =    16_u64
  @@termios = uninitialized UInt8[36]
  @@line = uninitialized UInt8[1024]
  @@ready = uninitialized UInt8[4096]
  @@readers = uninitialized UInt64[16]
  @@wanted = uninitialized UInt64[16]
  @@length = 0_u64
  @@count = 0_u64
  @@waiting = 0_u64
  @@eof = false
  @@group = 1_u32

  def self.termios : UInt8*
    pointerof(@@termios).as(UInt8*)
  end

  def self.ready : UInt8*
    pointerof(@@ready).as(UInt8*)
  end

  def self.init
    flags = termios.as(UInt32*)
    flags[0] = ICRNL
    flags[1] = 0x5_u32
    flags[2] = 0xbf_u32
    flags[3] = ISIG | ICANON | ECHO | 0x8030_u32
    control = termios + 17_i64
    control[0] = 3_u8
    control[1] = 28_u8
    control[2] = 127_u8
    control[3] = 21_u8
    control[4] = 4_u8
    control[6] = 1_u8
  end

  def self.local : UInt32
    termios.as(UInt32*)[3]
  end

  def self.queue(value : UInt8)
    return if @@count == 4096
    ready[@@count] = value
    @@count = @@count &+ 1
  end

  def self.commit
    i = 0_u64
    while i < @@length
      queue(pointerof(@@line).as(UInt8*)[i])
      i = i &+ 1
    end
    @@length = 0_u64
  end

  def self.echo(value : UInt8)
    put(value) if local & ECHO != 0
  end

  def self.key(value : UInt8)
    value = 10_u8 if value == 13 && termios.as(UInt32*)[0] & ICRNL != 0
    if local & ICANON == 0
      echo(value)
      queue(value)
      return
    end
    if value == 3 && local & ISIG != 0
      echo(94_u8)
      echo(67_u8)
      echo(10_u8)
      @@length = 0_u64
    elsif value == 4
      @@eof = true if @@length == 0
      commit
    elsif value == 8 || value == 127
      if @@length > 0
        @@length = @@length &- 1
        echo(8_u8)
        echo(32_u8)
        echo(8_u8)
      end
    elsif value == 10
      echo(10_u8)
      pointerof(@@line).as(UInt8*)[@@length] = 10_u8 if @@length < 1024
      @@length = @@length &+ 1 if @@length < 1024
      commit
    elsif @@length < 1023
      echo(value)
      pointerof(@@line).as(UInt8*)[@@length] = value
      @@length = @@length &+ 1
    end
  end

  def self.wait(pid : UInt64, count : UInt64) : Bool
    return false if @@waiting == READERS
    pointerof(@@readers).as(UInt64*)[@@waiting] = pid
    pointerof(@@wanted).as(UInt64*)[@@waiting] = count
    @@waiting = @@waiting &+ 1
    true
  end

  def self.available? : Bool
    @@count != 0 || @@eof
  end

  # moves up to count bytes of finished input into target
  def self.take(target : UInt8*, count : UInt64) : UInt64
    @@eof = false if @@count == 0
    count = @@count if count > @@count
    memcpy(target, ready, count)
    memmove(ready, ready + count.to_i64!, @@count &- count)
    @@count = @@count &- count
    count
  end

  def self.serve(service : UInt64, message : ABI::Message*, data : UInt8*)
    while @@waiting != 0 && available?
      pid = pointerof(@@readers).as(UInt64*)[0]
      count = take(data, pointerof(@@wanted).as(UInt64*)[0])
      @@waiting = @@waiting &- 1
      memmove(pointerof(@@readers).as(UInt8*), (pointerof(@@readers).as(UInt64*) + 1_i64).as(UInt8*), @@waiting << 3)
      memmove(pointerof(@@wanted).as(UInt8*), (pointerof(@@wanted).as(UInt64*) + 1_i64).as(UInt8*), @@waiting << 3)
      memset(message.as(UInt8*), 0, 64_u64)
      message.value.tag = count
      message.value.length = count
      System.reply(service, pid, message, data)
    end
  end

  def self.control(request : UInt64, data : UInt8*, length : UInt64) : Int64
    if request == 0x5401
      memcpy(data, termios, 36_u64)
      return 36_i64
    elsif request >= 0x5402 && request <= 0x5404
      return 0_i64 &- Errno::EINVAL if length < 36
      memcpy(termios, data, 36_u64)
      return 0_i64
    elsif request == 0x5413
      size = data.as(UInt16*)
      size[0] = Screen.rows == 0 ? 25_u16 : Screen.rows.to_u16!
      size[1] = Screen.columns == 0 ? 80_u16 : Screen.columns.to_u16!
      size[2] = 0_u16
      size[3] = 0_u16
      return 8_i64
    elsif request == 0x540f
      data.as(UInt32*).value = @@group
      return 4_i64
    elsif request == 0x5410
      @@group = data.as(UInt32*).value if length >= 4
      return 0_i64
    end
    0_i64 &- Errno::ENOTTY
  end
end
