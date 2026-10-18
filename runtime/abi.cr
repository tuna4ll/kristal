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
end
