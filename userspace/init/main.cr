require "../syscall"

fun user_main : NoReturn
  User.write("Hello World from Userspace\n")
  round = 0_u64
  while round < 4
    User.sleep(20_u64)
    User.write("init: working\n")
    round = round &+ 1
  end
  User.exit(0_u64)
end
