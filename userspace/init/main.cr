require "../syscall"

fun user_main : NoReturn
  User.write("Hello World from Userspace\n")
  round = 0_u64
  while round < 4
    work = 0_u64
    while work < 2000000
      asm("pause" ::: "memory" : "volatile")
      work = work &+ 1
    end
    User.write("init: working\n")
    round = round &+ 1
  end
  User.exit(0_u64)
end
