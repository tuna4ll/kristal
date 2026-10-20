require "../syscall"

fun user_main : NoReturn
  User.write("worker: connected through IPC\n")
  round = 0_u64
  while round < 4
    User.sleep(20_u64)
    User.write("worker: work completed\n")
    round = round &+ 1
  end
  User.write("worker: exiting\n")
  User.exit(0_u64)
end
