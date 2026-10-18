require "../syscall"

fun user_main : NoReturn
  message = uninitialized ABI::Message
  User.clear(pointerof(message))
  round = 0_u64
  while round < 4
    message.kind = 1_u64
    message.a = round
    User.exit(1_u64) if User.call(1_u64, pointerof(message)) != 0 || message.a != round &+ 1
    User.write("init: received reply\n")
    User.sleep(20_u64)
    round = round &+ 1
  end
  message.kind = 2_u64
  User.exit(1_u64) if User.call(1_u64, pointerof(message)) != 0
  User.exit(0_u64)
end
