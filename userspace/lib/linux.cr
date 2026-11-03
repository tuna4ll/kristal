# linux x86_64 syscall numbers on top of the posix layer. a ported libc points
# its syscall stubs here instead of at the syscall instruction
module Linux
  def self.path(address : UInt64) : UInt8*
    Pointer(UInt8).new(address)
  end

  def self.dispatch(number : UInt64, a : UInt64, b : UInt64, c : UInt64, d : UInt64, e : UInt64, f : UInt64) : Int64
    if number == 0
      Posix.read(a, path(b), c)
    elsif number == 1
      Posix.write(a, path(b), c)
    elsif number == 2
      Posix.open(path(a), b)
    elsif number == 3
      Posix.close(a)
    elsif number == 4 || number == 6
      Posix.stat(path(a), path(b))
    elsif number == 5
      Posix.fstat(a, path(b))
    elsif number == 8
      Posix.lseek(a, b.to_i64!, c)
    elsif number == 9
      Posix.mmap(a, b, c, d, e.to_i64!)
    elsif number == 11
      Posix.munmap(a, b)
    elsif number == 12
      Posix.brk(a)
    elsif number == 16
      Posix.ioctl(a, b, path(c))
    elsif number == 32
      Posix.dup(a)
    elsif number == 33
      Posix.dup2(a, b)
    elsif number == 35
      Posix.nanosleep(Pointer(Int64).new(a))
    elsif number == 39
      System.pid
    elsif number == 57
      Posix.fork
    elsif number == 59
      Posix.execve(path(a), Pointer(UInt8*).new(b), Pointer(UInt8*).new(c))
    elsif number == 60 || number == 231
      Posix.exit(a & 255)
    elsif number == 61
      Posix.waitpid(a.to_i64!, Pointer(Int32).new(b), c)
    elsif number == 63
      Posix.uname(path(a))
    elsif number == 72
      fcntl(a, b, c)
    elsif number == 79
      Posix.getcwd(path(a), b)
    elsif number == 80
      Posix.chdir(path(a))
    elsif number == 110
      System.pid(true)
    elsif number == 158 && a == 0x1002
      System.invoke(Sys::THREAD, b)
    elsif number == 217
      Posix.getdents(a, path(b), c)
    elsif number == 257 && a.to_i64! == -100
      Posix.open(path(b), c)
    else
      Posix.error(Errno::ENOSYS)
    end
  end

  def self.fcntl(fd : UInt64, command : UInt64, argument : UInt64) : Int64
    return Posix.error(Errno::EBADF) unless Posix.valid?(fd)
    if command == 0 || command == 1030
      result = Posix.dup(fd, argument)
      Posix.flags[result] = Posix.flags[result] | Posix::CLOEXEC if result >= 0 && command == 1030
      result
    elsif command == 1
      Posix.flags[fd] & Posix::CLOEXEC != 0 ? 1_i64 : 0_i64
    elsif command == 2
      Posix.flags[fd] = argument & 1 != 0 ? Posix.flags[fd] | Posix::CLOEXEC : Posix.flags[fd] & ~Posix::CLOEXEC
      0_i64
    elsif command == 3 || command == 4
      0_i64
    else
      Posix.error(Errno::EINVAL)
    end
  end
end

fun kristal_syscall(number : UInt64, a : UInt64, b : UInt64, c : UInt64, d : UInt64, e : UInt64, f : UInt64) : Int64
  Linux.dispatch(number, a, b, c, d, e, f)
end
