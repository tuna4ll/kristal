module Out
  def self.write(fd : UInt64, text : UInt8*, length : UInt64)
    done = 0_u64
    while done < length
      count = Posix.write(fd, text + done.to_i64!, length &- done)
      return if count <= 0
      done = done &+ count.to_u64!
    end
  end

  def self.print(text : String, fd : UInt64 = 1_u64)
    write(fd, text.to_unsafe, text.bytesize.to_u64!)
  end

  def self.print(text : UInt8*, fd : UInt64 = 1_u64)
    write(fd, text, Text.length(text))
  end

  def self.number(value : UInt64, fd : UInt64 = 1_u64)
    digits = uninitialized UInt8[24]
    buffer = pointerof(digits).as(UInt8*)
    write(fd, buffer, Text.decimal(value, buffer))
  end
end
