require "../syscall"
require "../../runtime/screen"

module Arch
  def self.port_in(port : UInt16) : UInt8
    value = 0_u8
    asm("inb %dx, %al" : "={al}"(value) : "{dx}"(port) :: "volatile")
    value
  end

  def self.port_out(port : UInt16, value : UInt8)
    asm("outb %al, %dx" :: "{dx}"(port), "{al}"(value) :: "volatile")
  end
end

def put(value : UInt8)
  while Arch.port_in(0x3fd_u16) & 0x20 == 0
  end
  Arch.port_out(0x3f8_u16, value)
  Screen.byte(value)
end

fun user_main : NoReturn
  display = uninitialized ABI::Display
  result = User.invoke(Sys::DISPLAY, pointerof(display).address)
  if result == 0
    User.exit(1_u64) unless Screen.init(display.address, display.width, display.height, display.pitch, display.red, display.green, display.blue)
  elsif result != 0_i64 &- Errno::ENODEV
    User.exit(1_u64)
  end
  message = uninitialized ABI::Message
  buffer = uninitialized UInt8[4096]
  data = pointerof(buffer).as(UInt8*)
  while true
    sender = User.receive(1_u64, pointerof(message), data, 4096_u64)
    User.exit(1_u64) if sender < 0
    next if sender == 0
    if message.tag == Op::WRITE
      i = 0_u64
      while i < message.length
        put(data[i])
        i = i &+ 1
      end
      message.tag = message.length
    else
      message.tag = (0_i64 &- Errno::EINVAL).to_u64!
    end
    message.length = 0_u64
    message.cap = 0_u64
    User.exit(1_u64) if User.reply(1_u64, sender.to_u64!, pointerof(message), data) != 0
  end
end
