#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile int caught, children;

static void on_user(int signal, siginfo_t *info, void *context)
{
	caught = info->si_signo;
}

static void on_child(int signal)
{
	children++;
}

int main(void)
{
	struct sigaction action;
	memset(&action, 0, sizeof action);
	action.sa_sigaction = on_user;
	action.sa_flags = SA_SIGINFO;
	sigaction(SIGUSR1, &action, 0);

	volatile double value = 1.5;
	raise(SIGUSR1);
	value *= 2.0;
	printf("caught %d with %.1f\n", caught, value);

	sigset_t set, old;
	sigemptyset(&set);
	sigaddset(&set, SIGUSR1);
	sigprocmask(SIG_BLOCK, &set, &old);
	caught = 0;
	kill(getpid(), SIGUSR1);
	printf("blocked %d\n", caught);
	sigprocmask(SIG_SETMASK, &old, 0);
	printf("unblocked %d\n", caught);

	signal(SIGCHLD, on_child);
	pid_t pid = fork();
	if (pid == 0) {
		pause();
		_exit(1);
	}
	kill(pid, SIGTERM);
	int status;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
		;
	printf("child killed by %d, sigchld %d\n", WIFSIGNALED(status) ? WTERMSIG(status) : -1, children);

	signal(SIGPIPE, SIG_IGN);
	int fds[2];
	pipe(fds);
	close(fds[0]);
	ssize_t written = write(fds[1], "x", 1);
	printf("closed pipe gave %zd, %s\n", written, strerror(errno));

	pid = fork();
	if (pid == 0) {
		*(volatile int *)0 = 1;
		_exit(0);
	}
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
		;
	printf("fault killed by %d\n", WTERMSIG(status));
	return 0;
}
