require "../syscall"

fun user_main : NoReturn
  User.write("Kristal: userspace console online\n")
  User.write("Hello World from Userspace\n")
  User.write("init: waiting for worker\n")
  message = uninitialized ABI::Message
  sender = User.receive(2_u64, pointerof(message))
  User.exit(1_u64) if sender != 3 || message.kind != 1
  message.kind = 0_u64
  User.exit(1_u64) if User.reply(2_u64, pointerof(message)) != 0
  User.write("init: worker finished; stopping console\n")
  User.clear(pointerof(message))
  message.kind = 2_u64
  User.exit(1_u64) if User.call(1_u64, pointerof(message)) != 0 || message.kind != 0
  User.exit(0_u64)
end
