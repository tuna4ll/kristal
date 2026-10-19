require "../runtime/base"

require "../runtime/abi"
require "../runtime/screen"
require "./console/display"
require "./process"
require "./ipc"
require "./syscall/dispatch"
require "./elf/loader"
require "./memory/pages"
require "./arch/x86_64/entry"
require "./arch/x86_64/cpu"
require "./arch/x86_64/interrupts"

def store64(p : UInt8*, offset : Int32, value : UInt64)
  i = 0
  while i < 8
    p[offset &+ i] = (value >> (i &* 8)).to_u8!
    i = i &+ 1
  end
end

def panic(message : String) : NoReturn
  Console.emergency
  Console.write("[Kristal] Panic: ")
  Console.write(message)
  Console.write("\n")
  Arch.debug_exit(0x11_u32)
  Arch.stop
end

module Console
  @@screen = false

  def self.handoff
    @@screen = false
  end

  def self.emergency
    @@screen = true
  end

  def self.hex(value : UInt64)
    digits = "0123456789abcdef".to_unsafe
    shift = 60
    while shift >= 0
      byte(digits[(value >> shift) & 15])
      shift = shift &- 4
    end
  end

  def self.init
    @@screen = true
    Arch.port_out(0x3f9_u16, 0_u8)
    Arch.port_out(0x3fb_u16, 0x80_u8)
    Arch.port_out(0x3f8_u16, 1_u8)
    Arch.port_out(0x3f9_u16, 0_u8)
    Arch.port_out(0x3fb_u16, 3_u8)
    Arch.port_out(0x3fa_u16, 0xc7_u8)
    Arch.port_out(0x3fc_u16, 0x0b_u8)
  end

  def self.byte(value : UInt8)
    while Arch.port_in(0x3fd_u16) & 0x20 == 0
    end
    Arch.port_out(0x3f8_u16, value)
    Screen.byte(value) if @@screen
  end

  def self.write(text : String)
    p = text.to_unsafe
    i = 0
    while p[i] != 0
      byte(p[i])
      i = i &+ 1
    end
  end
end

fun kernel_main(hhdm : UInt64*, memmap : UInt64*, modules : UInt64*, framebuffer : UInt64*) : NoReturn
  Console.init
  Display.init(framebuffer)
  Console.write("[Kristal] Booting...\n")
  if hhdm.address == 0 || memmap.address == 0
    Console.write("[Kristal] Missing Limine response\n")
    Arch.stop
  end
  Memory.init(hhdm[1], memmap)
  CPU.init
  Memory.init_space
  Console.write("[Kristal] Kernel initialized\n")
  panic("expected init, console and worker modules") if modules.address == 0 || modules[1] != 3
  files = Pointer(UInt64).new(modules[2])
  Processes.init
  IPC.init
  i = 0_u64
  while i < modules[1]
    Console.write("[Kristal] Loading userspace ELF\n")
    Processes.create(Pointer(UInt64).new(files[i]), i == 1 ? 1_u64 : 0_u64)
    i = i &+ 1
  end
  endpoint = IPC.create(2_u64)
  IPC.grant(1_u64, 1_u64, endpoint, IPC::CALL)
  IPC.grant(2_u64, 1_u64, endpoint, IPC::RECEIVE | IPC::REPLY)
  IPC.grant(3_u64, 1_u64, endpoint, IPC::CALL)
  coordination = IPC.create(1_u64)
  IPC.grant(1_u64, 2_u64, coordination, IPC::RECEIVE | IPC::REPLY)
  IPC.grant(3_u64, 2_u64, coordination, IPC::CALL)
  Timer.init
  Console.write("[Kristal] PIT timer: 100 Hz\n")
  Console.write("[Kristal] Round-robin: 50 ms quantum\n")
  Console.write("[Kristal] Entering Ring 3\n")
  Console.handoff
  Processes.start
end
