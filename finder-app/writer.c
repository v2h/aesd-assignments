/*
 * writer.c - AESD Assignment 2
 *
 * A C replacement for assignment 1's writer.sh. Writes a string to a file
 * using low-level File IO (open/write/close) as described in LSP chapter 2.
 *
 * Usage: writer <writefile> <writestr>
 *   writefile: full path to the file to create. Unlike writer.sh, this utility
 *              does NOT create the directory path -- the caller must ensure the
 *              containing directory already exists.
 *   writestr:  the string to write into that file (overwrites existing content).
 *
 * Logging uses syslog with the LOG_USER facility:
 *   - a LOG_DEBUG message "Writing <string> to <file>" describing the write
 *   - LOG_ERR messages for any unexpected errors
 *
 * Returns 0 on success, 1 on any error.
 *
 * Author: v2h
 */

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <syslog.h>
#include <sys/stat.h>

int main(int argc, char *argv[])
{
    /* Set up syslog logging with the LOG_USER facility. */
    openlog("writer", LOG_PID | LOG_CONS, LOG_USER);

    /* Require exactly two arguments: writefile and writestr. */
    if (argc != 3) {
        syslog(LOG_ERR, "Invalid number of arguments: %d (expected 2)", argc - 1);
        fprintf(stderr, "Error: two arguments required.\n");
        fprintf(stderr, "Usage: %s <writefile> <writestr>\n", argv[0]);
        closelog();
        return 1;
    }

    const char *writefile = argv[1];
    const char *writestr  = argv[2];

    /* Required log message, at LOG_DEBUG level. */
    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    /* Create (or truncate) the file for writing, mode 0644. */
    int fd = open(writefile, O_WRONLY | O_CREAT | O_TRUNC,
                  S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (fd == -1) {
        syslog(LOG_ERR, "Could not open file %s for writing: %s",
               writefile, strerror(errno));
        fprintf(stderr, "Error: could not create file '%s': %s\n",
                writefile, strerror(errno));
        closelog();
        return 1;
    }

    /* Write the full string, handling partial writes and interruptions. */
    size_t remaining = strlen(writestr);
    const char *ptr = writestr;
    while (remaining > 0) {
        ssize_t nr = write(fd, ptr, remaining);
        if (nr == -1) {
            if (errno == EINTR)
                continue;   /* interrupted by a signal before writing; retry */
            syslog(LOG_ERR, "Error writing to file %s: %s",
                   writefile, strerror(errno));
            fprintf(stderr, "Error: could not write to file '%s': %s\n",
                    writefile, strerror(errno));
            close(fd);
            closelog();
            return 1;
        }
        remaining -= (size_t)nr;
        ptr += nr;
    }

    if (close(fd) == -1) {
        syslog(LOG_ERR, "Error closing file %s: %s", writefile, strerror(errno));
        fprintf(stderr, "Error: could not close file '%s': %s\n",
                writefile, strerror(errno));
        closelog();
        return 1;
    }

    closelog();
    return 0;
}
