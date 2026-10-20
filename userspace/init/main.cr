require "../syscall"

fun user_main : NoReturn
  User.write("Kristal: userspace console online\n")
  User.write("Hello World from Userspace\n")
  User.write("init: waiting for worker\n")
  status = 0_u64
  User.exit(1_u64) if User.wait(3_u64, pointerof(status)) != 3
  if status == 0
    User.write("init: worker exited normally\n")
  else
    User.write("init: worker failed; kernel is still running\n")
  end
  User.write("init: stopping console service\n")
  message = uninitialized ABI::Message
  User.clear(pointerof(message))
  message.kind = 2_u64
  User.exit(1_u64) if User.call(1_u64, pointerof(message)) != 0 || message.kind != 0
  User.exit(1_u64) if User.wait(2_u64, pointerof(status)) != 2
  User.exit(status)
end
