#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	printf("hello from musl, argc=%d argv[0]=%s\n", argc, argv[0]);

	char *block = malloc(100000);
	memset(block, 'x', 100000);
	free(block);

	char line[64];
	FILE *file = fopen("/etc/motd", "r");
	if (!file || !fgets(line, sizeof line, file))
		return 1;
	fclose(file);
	printf("motd: %s", line);

	pid_t pid = fork();
	if (pid == 0) {
		execl("/bin/echo", "echo", "exec from c", (char *)0);
		_exit(9);
	}
	int status;
	waitpid(pid, &status, 0);
	printf("child exited with %d\n", WEXITSTATUS(status));

	int fds[2];
	char buffer[16];
	pipe(fds);
	write(fds[1], "piped\n", 6);
	close(fds[1]);
	printf("pipe gave %zd bytes\n", read(fds[0], buffer, sizeof buffer));

	chdir("/etc");
	printf("cwd is %s\n", getcwd(line, sizeof line));
	return 0;
}
