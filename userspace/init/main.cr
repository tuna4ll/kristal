require "../../runtime/base"

lib Syscall
  fun invoke(number : UInt64, arg1 : UInt64, arg2 : UInt64) : Int64
end

fun user_main : NoReturn
  message = "Hello World from Userspace\n"
  result = Syscall.invoke(1_u64, message.to_unsafe.address, 27_u64)
  status = result == 27 ? 0_u64 : 1_u64
  Syscall.invoke(2_u64, status, 0_u64)
  while true
    asm("ud2" ::: "memory" : "volatile")
  end
end
