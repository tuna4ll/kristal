require "../lib/prelude"

# a small shell until bash runs: quoting, $? and $NAME, pipes, < and > and a PATH search
module Shell
  STAGES = 8_u64
  @@line = uninitialized UInt8[1024]
  @@words = uninitialized UInt8[2048]
  @@args = uninitialized UInt8*[72]
  @@starts = uninitialized UInt64[8]
  @@counts = uninitialized UInt64[8]
  @@inputs = uninitialized UInt8*[8]
  @@outputs = uninitialized UInt8*[8]
  @@status = 0_u64

  def self.line : UInt8*
    pointerof(@@line).as(UInt8*)
  end

  def self.args : UInt8**
    pointerof(@@args).as(UInt8**)
  end

  def self.starts : UInt64*
    pointerof(@@starts).as(UInt64*)
  end

  def self.counts : UInt64*
    pointerof(@@counts).as(UInt64*)
  end

  def self.inputs : UInt8**
    pointerof(@@inputs).as(UInt8**)
  end

  def self.outputs : UInt8**
    pointerof(@@outputs).as(UInt8**)
  end

  def self.status : UInt64
    @@status
  end

  def self.prompt
    Out.print("kristal:")
    Out.print(Posix.cwd)
    Out.print("$ ")
  end

  def self.read_line : Bool
    length = 0_u64
    while length < 1023
      count = Posix.read(0_u64, line + length.to_i64!, 1023_u64 &- length)
      return false if count <= 0 && length == 0
      break if count <= 0
      length = length &+ count.to_u64!
      break if line[length &- 1] == 10
    end
    line[length] = 0_u8
    true
  end

  def self.variable(name : UInt8*, size : UInt64) : UInt8*
    environ = Start.environ
    i = 0_i64
    while environ[i].address != 0
      entry = environ[i]
      if memcmp(entry, name, size) == 0 && entry[size] == 61
        return entry + (size &+ 1).to_i64!
      end
      i = i &+ 1
    end
    "".to_unsafe
  end

  # splits the line into pipeline stages of words, expanding variables as it goes
  def self.parse : UInt64
    target = pointerof(@@words).as(UInt8*)
    finish = target + 2040_i64
    count = 0_u64
    stage = 0_u64
    starts[0] = 0_u64
    inputs[0] = Pointer(UInt8).new(0_u64)
    outputs[0] = Pointer(UInt8).new(0_u64)
    i = 0_u64
    while true
      while line[i] == 32 || line[i] == 9 || line[i] == 10
        i = i &+ 1
      end
      break if line[i] == 0 || line[i] == 35
      if line[i] == 124
        i = i &+ 1
        next if stage == STAGES &- 1
        args[count] = Pointer(UInt8).new(0_u64)
        counts[stage] = count &- starts[stage]
        count = count &+ 1
        stage = stage &+ 1
        starts[stage] = count
        inputs[stage] = Pointer(UInt8).new(0_u64)
        outputs[stage] = Pointer(UInt8).new(0_u64)
        next
      end
      redirect = 0
      if line[i] == 60 || line[i] == 62
        redirect = line[i] == 60 ? 1 : 2
        i = i &+ 1
        while line[i] == 32
          i = i &+ 1
        end
      end
      start = target
      quote = 0_u8
      while line[i] != 0 && target.address < finish.address
        value = line[i]
        if quote == 0 && (value == 32 || value == 9 || value == 10 || value == 124)
          break
        elsif quote == 0 && (value == 34 || value == 39)
          quote = value
        elsif quote != 0 && value == quote
          quote = 0_u8
        elsif value == 36 && quote != 39 && line[i &+ 1] == 63
          target += Text.decimal(@@status, target).to_i64!
          i = i &+ 1
        elsif value == 36 && quote != 39 && name?(line[i &+ 1])
          j = i &+ 1
          while name?(line[j])
            j = j &+ 1
          end
          value = variable(line + (i &+ 1).to_i64!, j &- i &- 1)
          while value.value != 0 && target.address < finish.address
            target.value = value.value
            target += 1_i64
            value += 1_i64
          end
          i = j &- 1
        else
          target.value = value
          target += 1_i64
        end
        i = i &+ 1
      end
      target.value = 0_u8
      target += 1_i64
      if redirect == 1
        inputs[stage] = start
      elsif redirect == 2
        outputs[stage] = start
      elsif count < 70
        args[count] = start
        count = count &+ 1
      end
    end
    args[count] = Pointer(UInt8).new(0_u64)
    counts[stage] = count &- starts[stage]
    return 0_u64 if stage == 0 && counts[0] == 0
    stage &+ 1
  end

  def self.name?(value : UInt8) : Bool
    (value >= 97 && value <= 122) || (value >= 65 && value <= 90) || (value >= 48 && value <= 57) || value == 95
  end

  def self.builtin(args : UInt8**, count : UInt64) : Bool
    name = args[0]
    if Text.equal?(name, "cd")
      target = count > 1 ? args[1] : variable("HOME".to_unsafe, 4_u64)
      target = "/".to_unsafe if target.value == 0
      result = Posix.chdir(target)
      fail(target, result) if result < 0
      @@status = result < 0 ? 1_u64 : 0_u64
    elsif Text.equal?(name, "pwd")
      Out.print(Posix.cwd)
      Out.print("\n")
      @@status = 0_u64
    elsif Text.equal?(name, "exit")
      code = 0_u64
      if count > 1
        digits = args[1]
        while digits.value >= 48 && digits.value <= 57
          code = code &* 10 &+ (digits.value &- 48).to_u64!
          digits += 1_i64
        end
      else
        code = @@status
      end
      Posix.exit(code)
    elsif Text.equal?(name, "help")
      Out.print("builtins: cd pwd exit help\nprograms live in /bin\n")
      @@status = 0_u64
    else
      return false
    end
    true
  end

  def self.fail(name : UInt8*, error : Int64)
    Out.print("sh: ", 2_u64)
    Out.print(name, 2_u64)
    if error == 0_i64 &- Errno::ENOENT
      Out.print(": not found\n", 2_u64)
    elsif error == 0_i64 &- Errno::ENOTDIR
      Out.print(": not a directory\n", 2_u64)
    elsif error == 0_i64 &- Errno::EACCES
      Out.print(": permission denied\n", 2_u64)
    else
      Out.print(": error ", 2_u64)
      Out.number((0_i64 &- error).to_u64!, 2_u64)
      Out.print("\n", 2_u64)
    end
  end

  def self.search(name : UInt8*, target : UInt8*) : Bool
    i = 0_u64
    while name[i] != 0
      if name[i] == 47
        Text.copy(target, name)
        return true
      end
      i = i &+ 1
    end
    path = variable("PATH".to_unsafe, 4_u64)
    path = "/bin".to_unsafe if path.value == 0
    info = uninitialized ABI::Stat
    while path.value != 0
      cursor = target
      while path.value != 0 && path.value != 58
        cursor.value = path.value
        cursor += 1_i64
        path += 1_i64
      end
      path += 1_i64 if path.value == 58
      cursor.value = 47_u8
      Text.copy(cursor + 1_i64, name)
      return true if Posix.stat(target, pointerof(info).as(UInt8*)) == 0
    end
    false
  end

  def self.redirect(path : UInt8*, fd : UInt64, mode : UInt64) : Bool
    opened = Posix.open(path, mode)
    if opened < 0
      fail(path, opened)
      return false
    end
    Posix.dup2(opened.to_u64!, fd)
    Posix.close(opened.to_u64!)
    true
  end

  def self.exec(stage : UInt64) : NoReturn
    words = args + starts[stage].to_i64!
    Posix.exit(1_u64) if inputs[stage].address != 0 && !redirect(inputs[stage], 0_u64, 0_u64)
    Posix.exit(1_u64) if outputs[stage].address != 0 && !redirect(outputs[stage], 1_u64, Flag::WRITE | Flag::CREATE | Flag::TRUNCATE)
    Posix.exit(@@status) if builtin(words, counts[stage])
    scratch = uninitialized UInt8[256]
    path = pointerof(scratch).as(UInt8*)
    unless search(words[0], path)
      fail(words[0], 0_i64 &- Errno::ENOENT)
      Posix.exit(127_u64)
    end
    result = Posix.execve(path, words, Start.environ)
    fail(words[0], result)
    Posix.exit(126_u64)
  end

  def self.run(stages : UInt64)
    return if stages == 0 || counts[stages &- 1] == 0
    return if stages == 1 && builtin(args, counts[0])
    ends = uninitialized Int32[16]
    pipes = pointerof(ends).as(Int32*)
    made = 0_u64
    while made &+ 1 < stages
      break if Posix.pipe(pipes + (made << 1).to_i64!, 0_u64) < 0
      made = made &+ 1
    end
    pids = uninitialized Int64[8]
    children = pointerof(pids).as(Int64*)
    stage = 0_u64
    while stage < stages
      children[stage] = 0_i64
      if stage == 0 || stage <= made
        pid = Posix.fork
        if pid == 0
          Posix.dup2(pipes[(stage &- 1) << 1].to_u64!, 0_u64) if stage > 0
          Posix.dup2(pipes[(stage << 1) &+ 1].to_u64!, 1_u64) if stage < made
          i = 0_u64
          while i < made << 1
            Posix.close(pipes[i].to_u64!)
            i = i &+ 1
          end
          exec(stage)
        end
        fail(args[starts[stage]], pid) if pid < 0
        children[stage] = pid
      end
      stage = stage &+ 1
    end
    i = 0_u64
    while i < made << 1
      Posix.close(pipes[i].to_u64!)
      i = i &+ 1
    end
    @@status = 1_u64
    stage = 0_u64
    while stage < stages
      if children[stage] > 0
        code = 0_i32
        Posix.waitpid(children[stage], pointerof(code), 0_u64)
        @@status = code & 0x7f != 0 ? 128_u64 &+ (code & 0x7f).to_u64! : ((code >> 8) & 255).to_u64!
      end
      stage = stage &+ 1
    end
  end
end

def main(argc : UInt64, argv : UInt8**) : Int32
  while true
    Shell.prompt
    break unless Shell.read_line
    Shell.run(Shell.parse)
  end
  Shell.status.to_i32!
end
