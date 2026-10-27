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
  User.exit(status)
end
