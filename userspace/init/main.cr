require "../../runtime/base"

fun user_main : NoReturn
  while true
    asm("pause" ::: "memory" : "volatile")
  end
end
