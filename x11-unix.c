#include <config.h>
#include <sys/types.h>
#include <shell.h>
#include <builtins.h>
#include <common.h>

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int bxt_x11_connect_builtin(WORD_LIST *args)
{
    struct sockaddr_un address = {0};
    const char *path;
    socklen_t address_length;
    size_t path_length;
    int fd, saved_errno;
    char fd_string[32];
    SHELL_VAR *fd_variable;

    if (!args || args->next) {
        builtin_usage();
        return EX_USAGE;
    }
    path = args->word->word;
    path_length = strlen(path);
    if (!path_length || path_length >= sizeof(address.sun_path)) {
        builtin_error("invalid Unix socket path: %s", path);
        return EXECUTION_FAILURE;
    }

    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, path_length + 1);
    address_length = offsetof(struct sockaddr_un, sun_path) + path_length + 1;
#ifdef __linux__
    if (path[0] == '@') {
        address.sun_path[0] = '\0';
        address_length--;
    }
#endif

    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        builtin_error("socket: %s", strerror(errno));
        return EXECUTION_FAILURE;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
        connect(fd, (struct sockaddr *)&address, address_length) < 0) {
        saved_errno = errno;
        close(fd);
        builtin_error("%s: %s", path, strerror(saved_errno));
        return EXECUTION_FAILURE;
    }

    snprintf(fd_string, sizeof(fd_string), "%d", fd);
    fd_variable = builtin_bind_variable("x_fd", fd_string, 0);
    if (!fd_variable || readonly_p(fd_variable) || noassign_p(fd_variable)) {
        close(fd);
        return EXECUTION_FAILURE;
    }
    return EXECUTION_SUCCESS;
}

static char *bxt_x11_connect_doc[] = {
    "Connect to a Unix-domain socket and set x_fd to the file descriptor.",
    NULL
};

struct builtin bxt_x11_connect_struct = {
    "bxt_x11_connect",
    bxt_x11_connect_builtin,
    BUILTIN_ENABLED,
    bxt_x11_connect_doc,
    "bxt_x11_connect SOCKET",
    NULL
};
