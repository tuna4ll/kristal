require "../syscall"

fun user_main : NoReturn
  User.write("worker: connected through IPC\n")
  round = 0_u64
  while round < 4
    User.sleep(20_u64)
    User.write("worker: work completed\n")
    round = round &+ 1
  end
  User.write("worker: notifying init\n")
  message = uninitialized ABI::Message
  User.clear(pointerof(message))
  message.kind = 1_u64
  User.exit(1_u64) if User.call(2_u64, pointerof(message)) != 0 || message.kind != 0
  User.exit(0_u64)
end
