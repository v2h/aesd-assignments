#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <syslog.h>
#include <errno.h>
#include <signal.h>
#include <stdbool.h>

#define PORT        9000
#define BUF_SIZE    2000
#define DATA_FILE   "/var/tmp/aesdsocketdata"

#define LOG_DBG(fmt, ...) printf(fmt "\n", ##__VA_ARGS__)

/* Set from the signal handler; read from the accept/recv loops. */
static volatile sig_atomic_t exit_requested = 0;

static void signal_handler(int signo)
{
    (void)signo;
    exit_requested = 1;
}

/* Install SIGINT/SIGTERM handlers without SA_RESTART so blocking syscalls
 * (accept/recv) are interrupted with EINTR and we can react to the signal. */
static int setup_signals(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    if (sigaction(SIGINT, &sa, NULL) == -1)
        return -1;
    if (sigaction(SIGTERM, &sa, NULL) == -1)
        return -1;
    return 0;
}

static int open_log_for_read(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        perror("open log (read)");
        return -1;
    }
    return fd;
}

static ssize_t read_all(int fd, char **out_buf) {
    off_t size = lseek(fd, 0, SEEK_END);
    if (size < 0) {
        perror("lseek");
        return -1;
    }
    if (lseek(fd, 0, SEEK_SET) < 0) {
        perror("lseek");
        return -1;
    }

    char *buf = malloc(size + 1);
    if (!buf) {
        perror("malloc");
        return -1;
    }

    ssize_t total = 0;
    while (total < size) {
        ssize_t n = read(fd, buf + total, size - total);
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("read");
            free(buf);
            return -1;
        }
        if (n == 0) break; // EOF
        total += n;
    }

    buf[total] = '\0';
    *out_buf = buf;
    return total;
}

/* Fork into the background. Called only after a successful bind so that a bind
 * failure is reported by the foreground process (return -1). */
static int daemonize(void)
{
    const pid_t pid = fork();
    if (pid < 0) {
        syslog(LOG_ERR, "fork: %m");
        return -1;
    }
    if (pid > 0)
        exit(EXIT_SUCCESS); // parent exits, shell continues

    if (setsid() == -1) {
        syslog(LOG_ERR, "setsid: %m");
        return -1;
    }
    if (chdir("/") == -1) {
        syslog(LOG_ERR, "chdir: %m");
        return -1;
    }

    int devnull = open("/dev/null", O_RDWR);
    if (devnull != -1) {
        dup2(devnull, STDIN_FILENO);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > STDERR_FILENO)
            close(devnull);
    }
    return 0;
}

int main(int argc, char *argv[]) {
    int daemon_mode = 0;
    int opt;

    while ((opt = getopt(argc, argv, "d")) != -1) {
        switch (opt) {
        case 'd':
            daemon_mode = 1;
            break;
        default:
            fprintf(stderr, "Usage: %s [-d]\n", argv[0]);
            return -1;
        }
    }

    openlog("aesdsocket tcp server", LOG_PID, LOG_USER);

    if (setup_signals() == -1) {
        syslog(LOG_ERR, "Failed to set up signal handlers");
        closelog();
        return -1;
    }

    int listen_fd, conn_fd;
    int ret = 0;
    struct sockaddr_in serv_addr, cli_addr;
    socklen_t cli_len;

    /* Create TCP socket */
    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        closelog();
        exit(EXIT_FAILURE);
    }

    // Optional: allow quick restart (avoid "Address already in use")
    // TODO gracefully exit ?
    int sockopt = 1;
    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &sockopt, sizeof(sockopt)) < 0) {
        perror("setsockopt");
    }

    /* Bind to 0.0.0.0:PORT */
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family      = AF_INET;
    serv_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    serv_addr.sin_port        = htons(PORT);

    if (bind(listen_fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("bind");
        close(listen_fd);
        closelog();
        exit(EXIT_FAILURE);
    }

    if (listen(listen_fd, 5) < 0) {
        perror("listen");
        close(listen_fd);
        closelog();
        exit(EXIT_FAILURE);
    }
    printf("TCP echo server listening on 0.0.0.0:%d\n", PORT);

    if (daemon_mode && daemonize() == -1) {
        close(listen_fd);
        closelog();
        return -1;
    }

    char buf[BUF_SIZE];
    ssize_t n;
    while (!exit_requested) {
        cli_len = sizeof(cli_addr);
        conn_fd = accept(listen_fd, (struct sockaddr *)&cli_addr, &cli_len);
        if (conn_fd < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            continue;
        }

        char ip[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &cli_addr.sin_addr, ip, sizeof(ip)) == NULL) {
            perror("inet_ntop");
            snprintf(ip, sizeof(ip), "unknown");
            break;
        }
        syslog(LOG_INFO, "Accepted connection from %s", ip);

        const int data_fd = open(DATA_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (data_fd < 0) {
            syslog(LOG_ERR, "Failed to open %s: %m", DATA_FILE);
            close(conn_fd);
            continue;
        } else {
            LOG_DBG("opened file for appending at %s", DATA_FILE);
        }

        for (;;) {
            n = recv(conn_fd, buf, sizeof(buf) - 1, 0); // -1 because sparing the last char for '\0'
            if (n == 0) {
                printf("Client %s:%d disconnected\n", ip, ntohs(cli_addr.sin_port));
                break;
            }
            if (n < 0) {
                if (errno == EINTR) {
                    break; // interrupted by signal
                }
                perror("recv");
                break;
            }

            buf[n] = '\0';
            LOG_DBG("received %ld bytes: %s", n, buf);

            bool everything_is_received = false;

            if (memchr(buf, '\n', n) == NULL) {
                LOG_DBG("NO newline");
            } else {
                LOG_DBG("newline found");
                everything_is_received = true;
            }

            const int write_err = write(data_fd, buf, n);
            if (write_err != n) { // TODO handle partial write
                if (write_err == -1) {
                    if (errno == EINTR) {
                        continue;
                    }
                }
                syslog(LOG_ERR, "write error to %s: %m", DATA_FILE);
                break;
            }

            if (everything_is_received == false) {
                LOG_DBG("client hasn't finished sending yet");
                continue;
            }

            const int read_fd = open_log_for_read(DATA_FILE);
            if (read_fd < 0) {
                perror("cannot open file for reading");
                continue;
            }
            char *file_content = NULL;
            ssize_t file_size = read_all(read_fd, &file_content);
            if (file_size > 0 && file_content) {
                ssize_t total_sent_bytes = 0;
                while (total_sent_bytes < file_size) {
                    const int bytes_sent = send(conn_fd, 
                                                file_content + total_sent_bytes, 
                                                file_size - total_sent_bytes,
                                                0);
                    if (bytes_sent < 0) {
                        if (errno == EINTR) {
                            if (exit_requested) {
                                ret = -1;
                                goto out;
                            }
                        }
                        perror("send");
                        break;
                    } else {
                        LOG_DBG("Sent %d bytes", bytes_sent);
                    }
                    if (bytes_sent == 0) {
                        LOG_DBG("Sent ZERO bytes");
                        break;
                    }
                    total_sent_bytes += bytes_sent;
                }
            } else {
                LOG_DBG("file size: %ld", file_size);
            }
            free(file_content);
            close(read_fd);
        }

        LOG_DBG("Closing connection and file");
        close(conn_fd);
        close(data_fd);
    }

out:
    syslog(LOG_INFO, "Caught signal, exiting");
    LOG_DBG("out");
    close(listen_fd);
    // Ignore ENOENT in case it was never created
    if (unlink(DATA_FILE) == -1 && errno != ENOENT)
        syslog(LOG_ERR, "unlink %s: %m", DATA_FILE);
    return ret;
}