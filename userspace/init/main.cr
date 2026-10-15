require "../../runtime/base"

fun user_main : NoReturn
  asm("int3" ::: "memory" : "volatile")
  while true
    asm("pause" ::: "memory" : "volatile")
  end
end
