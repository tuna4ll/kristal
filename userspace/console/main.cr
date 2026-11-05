require "../lib/prelude"
require "../../runtime/screen"
require "./keyboard"
require "./terminal"

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

def serial(value : UInt8)
  while Arch.port_in(0x3fd_u16) & 0x20 == 0
  end
  Arch.port_out(0x3f8_u16, value)
end

def put(value : UInt8)
  serial(13_u8) if value == 10
  serial(value)
  Screen.byte(value)
end

def input
  while Arch.port_in(0x3fd_u16) & 1 != 0
    Terminal.key(Arch.port_in(0x3f8_u16))
  end
  while Arch.port_in(0x64_u16) & 1 != 0
    status = Arch.port_in(0x64_u16)
    code = Arch.port_in(0x60_u16)
    next if status & 0x20 != 0
    value = Keyboard.translate(code)
    Terminal.key(value) if value != 0
  end
end

def respond(sender : UInt64, message : ABI::Message*, data : UInt8*) : Bool
  op = message.value.tag
  length = message.value.length
  message.value.length = 0_u64
  message.value.cap = 0_u64
  if op == Op::WRITE
    i = 0_u64
    while i < length
      put(data[i])
      i = i &+ 1
    end
    message.value.tag = length
  elsif op == Op::READ
    unless Terminal.available?
      return false if Terminal.wait(sender, message.value.b)
      message.value.tag = (0_i64 &- Errno::EAGAIN).to_u64!
      return true
    end
    count = Terminal.take(data, message.value.b)
    message.value.tag = count
    message.value.length = count
  elsif op == Op::IOCTL
    result = Terminal.control(message.value.b, data, length)
    message.value.tag = result.to_u64!
    message.value.length = result > 0 ? result.to_u64! : 0_u64
    message.value.tag = 0_u64 if result > 0
  elsif op == Op::FSTAT
    memset(data, 0, sizeof(ABI::Stat).to_u64!)
    info = data.as(ABI::Stat*)
    info.value.mode = Mode::CHARACTER | 0o620_u32
    info.value.rdev = 0x0501_u64
    info.value.nlink = 1_u64
    message.value.length = sizeof(ABI::Stat).to_u64!
    message.value.tag = 0_u64
  elsif op == Op::CLOSE || op == Op::DUP
    message.value.tag = 0_u64
  elsif op == Op::SEEK
    message.value.tag = (0_i64 &- Errno::ESPIPE).to_u64!
  else
    message.value.tag = (0_i64 &- Errno::EINVAL).to_u64!
  end
  true
end

def main(argc : UInt64, argv : UInt8**) : Int32
  service = Posix.service
  return 1 if service == 0
  display = uninitialized ABI::Display
  result = System.device(Device::DISPLAY, pointerof(display).as(UInt8*))
  if result == 0
    return 1 unless Screen.init(display.address, display.width, display.height, display.pitch, display.red, display.green, display.blue)
  elsif result != 0_i64 &- Errno::ENODEV
    return 1
  end
  Terminal.init
  return 1 if System.invoke(Sys::IRQ, service, Device::SERIAL) != 0
  return 1 if System.invoke(Sys::IRQ, service, Device::KEYBOARD) != 0
  Arch.port_out(0x3f9_u16, 1_u8)
  message = uninitialized ABI::Message
  buffer = uninitialized UInt8[4096]
  data = pointerof(buffer).as(UInt8*)
  while true
    sender = System.receive(service, pointerof(message), data, 4096_u64)
    return 1 if sender < 0
    if sender == 0
      input
    elsif respond(sender.to_u64!, pointerof(message), data)
      System.reply(service, sender.to_u64!, pointerof(message), data)
    end
    Terminal.serve(service, pointerof(message), data)
  end
end
