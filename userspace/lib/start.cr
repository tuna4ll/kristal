module Start
  @@environ = Pointer(UInt8*).new(0_u64)

  def self.environ=(value : UInt8**)
    @@environ = value
  end

  def self.environ : UInt8**
    @@environ
  end
end

fun user_entry_code
  asm("
    .pushsection .text
    .globl _user_start
    _user_start:
      xor %ebp, %ebp
      mov %rsp, %rdi
      call user_start
      ud2
    .popsection
  " :::: "volatile")
end

fun user_start(stack : UInt64*) : NoReturn
  argc = stack[0]
  argv = Pointer(UInt8*).new((stack + 1_i64).address)
  envp = stack + (argc &+ 2).to_i64!
  aux = envp
  while aux.value != 0
    aux += 1_i64
  end
  aux += 1_i64
  data = 0_u64
  size = 0_u64
  while aux[0] != 0
    data = aux[1] if aux[0] == Aux::DATA
    size = aux[1] if aux[0] == Aux::SIZE
    aux += 2_i64
  end
  Start.environ = Pointer(UInt8*).new(envp.address)
  Posix.init(Pointer(UInt8).new(data), size)
  Posix.exit(main(argc, argv).to_u64! & 255)
end
