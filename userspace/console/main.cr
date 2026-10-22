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
  while true
    sender = User.receive(1_u64, pointerof(message))
    User.exit(1_u64) if sender < 0
    close = false
    if message.kind == 1 && message.size <= 48
      bytes = pointerof(message).as(UInt8*) + 16_i64
      i = 0_u64
      while i < message.size
        put(bytes[i])
        i = i &+ 1
      end
      message.kind = 0_u64
    elsif message.kind == 2 && sender == 1
      close = true
      message.kind = 0_u64
    else
      message.kind = 22_u64
      message.size = 0_u64
    end
    User.exit(1_u64) if User.reply(1_u64, pointerof(message)) != 0
    User.exit(0_u64) if close
  end
end
