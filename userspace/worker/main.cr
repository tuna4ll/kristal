require "../syscall"

fun user_main : NoReturn
  message = uninitialized ABI::Message
  while true
    sender = User.receive(1_u64, pointerof(message))
    User.exit(1_u64) if sender < 0
    if message.kind == 2
      User.reply(1_u64, pointerof(message))
      User.exit(0_u64)
    end
    message.a = message.a &+ 1
    User.write("worker: replying to request\n")
    User.exit(1_u64) if User.reply(1_u64, pointerof(message)) != 0
  end
end
