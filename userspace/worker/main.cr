require "../syscall"

fun user_main : NoReturn
  User.write("worker: started\n")
  round = 0_u64
  while round < 8
    User.sleep(20_u64)
    User.write("worker: working\n")
    round = round &+ 1
  end
  User.exit(0_u64)
end
