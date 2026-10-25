lib ABI
  # IPC copies exactly 64 bytes; the last 48 bytes are protocol payload.
  struct Message
    kind : UInt64
    size : UInt64
    a : UInt64
    b : UInt64
    c : UInt64
    d : UInt64
    e : UInt64
    f : UInt64
  end

  struct Display
    address : UInt64
    width : UInt64
    height : UInt64
    pitch : UInt64
    red : UInt64
    green : UInt64
    blue : UInt64
    length : UInt64
  end
end

module Wait
  ANY = 0xffffffffffffffff_u64
end

module Sys
  EXIT    = 1_u64
  SLEEP   = 2_u64
  WAIT    = 3_u64
  CALL    = 4_u64
  RECEIVE = 5_u64
  REPLY   = 6_u64
  DISPLAY = 7_u64
end

# linux numbering, so a future libc can pass these through unchanged
module Errno
  EPERM   =  1_i64
  ESRCH   =  3_i64
  ECHILD  = 10_i64
  ENOMEM  = 12_i64
  EFAULT  = 14_i64
  EBUSY   = 16_i64
  ENODEV  = 19_i64
  EINVAL  = 22_i64
  EPIPE   = 32_i64
  EDEADLK = 35_i64
  ENOSYS  = 38_i64
end

module Layout
  IMAGE     =          0x10000_u64
  IMAGE_END =       0x40000000_u64
  MAP       =     0x1000000000_u64
  DEVICE    =   0x700000000000_u64
  INITRD    =   0x710000000000_u64
  STACK     =   0x7fffffff0000_u64
  STACK_MAX =        0x800000_u64
  END       =   0x800000000000_u64
end
