/*
 * Copyright (C) 2012 Gregor Richards
 * 
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
 * OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#define _GNU_SOURCE /* we use Linux-specific things */

#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

#include "buffer.h"

#define BASE        "/usr"
#define PATHENV     "USR_DIRS"
#define WRITEENV    "USR_WRITE_DIR"
#define OKFILE      "/.usr_ok"
#define FORCEDIR    "/pkg/core/1.0/usr"
#define WRITE_STR_BUFFER(buf, str) \
    WRITE_BUFFER(buf, str, sizeof(str)-1)

/* FIXME: we shouldn't need this, once musl gets it */
static int unshare(int flags)
{
    int ret = syscall(SYS_unshare, flags);
    if (ret < 0) {
        errno = -ret;
        ret = -1;
    }
    return ret;
}

BUFFER(charp, char *);

void validatePath(char **path);

int main(int argc, char **argv)
{
    struct Buffer_charp rpaths;
    struct Buffer_char options;
    char *wpath = NULL, *arg;
    char *envpaths;
    int i, j, argi, tmpi;
    unsigned long mountflags = 0;
    int allowclear = 0, clear = 0;

    INIT_BUFFER(rpaths);
    WRITE_ONE_BUFFER(rpaths, NULL); /* filled in by forced dir later */

    /* get all the paths out of the environment */
    envpaths = getenv(PATHENV);
    if (envpaths && envpaths[0]) {
        char *saveptr;
        arg = strtok_r(envpaths, ":", &saveptr);
        while (arg) {
            WRITE_ONE_BUFFER(rpaths, arg);
            arg = strtok_r(NULL, ":", &saveptr);
        }
    }

    /* get all the paths out of the args */
    for (argi = 1; argi < argc; argi++) {
        arg = argv[argi];
        if (arg[0] == '-') {
            if (!strcmp(arg, "-w") && argi < argc - 1) {
                argi++;
                wpath = argv[argi];

            } else if (!strcmp(arg, "-r")) {
                /* reset current paths (ignore environment) */
                rpaths.bufused = 1;
                allowclear = 1;

            } else if (!strcmp(arg, "--") && argi < argc - 1) {
                argi++;
                break;

            } else {
                fprintf(stderr, "Unrecognized option %s\n", arg);
            }

        } else {
            WRITE_ONE_BUFFER(rpaths, arg);

        }
    }
    if (argi >= argc) {
        if (getuid() != geteuid()) {
            fprintf(stderr, "Only root may remount an existing view\n");
            return 1;
        }
        mountflags |= MS_REMOUNT;
    }

    /* validate all our paths */
    for (i = 1; i < rpaths.bufused; i++) {
        validatePath(&rpaths.buf[i]);
    }
    validatePath(&wpath);
    rpaths.buf[0] = FORCEDIR;

    /* make sure there are no duplicates */
    for (i = 1; i < rpaths.bufused; i++) {
        for (j = 0; j < i; j++) {
            if (rpaths.buf[i] && rpaths.buf[j] &&
                !strcmp(rpaths.buf[i], rpaths.buf[j])) {
                rpaths.buf[i] = NULL;
                break;
            }
        }
    }

    /* generate our options string */
    INIT_BUFFER(options);
    WRITE_STR_BUFFER(options, "br=");
    if (wpath) {
        WRITE_BUFFER(options, wpath, strlen(wpath));
        WRITE_STR_BUFFER(options, "=rw");
    } else {
        mountflags |= MS_RDONLY;
    }
    for (i = 0; i < rpaths.bufused; i++) {
        arg = rpaths.buf[i];
        if (arg) {
            if (options.bufused > 3) WRITE_STR_BUFFER(options, ":");
            WRITE_BUFFER(options, arg, strlen(arg));
            WRITE_STR_BUFFER(options, "=ro");
        }
    }
    WRITE_STR_BUFFER(options, "\0");
    if (!wpath && rpaths.bufused == 1) {
        /* no options = unmount all */
        if (!allowclear) {
            fprintf(stderr, "To explicitly clear all /usr mounts, -r must be specified\n");
            return 1;
        }
        clear = 1;
    }

    /* perform the mount */
    if (!(mountflags & MS_REMOUNT))
        SF(tmpi, unshare, -1, (CLONE_NEWNS));
    if (clear) {
        do {
            tmpi = umount("/usr");
        } while (tmpi == 0);
        if (errno != EINVAL)
            perror("/usr");
    } else {
        tmpi = mount("none", BASE, "aufs", mountflags, options.buf);
        if (mountflags & MS_REMOUNT) {
            /* OK, we tried to remount, maybe it just wasn't mounted though */
            mountflags &= ~(MS_REMOUNT);
            tmpi = mount("none", BASE, "aufs", mountflags, options.buf);
        }
        if (tmpi == -1) {
            perror("mount");
            return 1;
        }
    }
    FREE_BUFFER(options);

    /* drop privs */
    SF(tmpi, setuid, -1, (getuid()));
    SF(tmpi, setgid, -1, (getgid()));

    /* add it to the environment */
    INIT_BUFFER(options);
    for (i = 0; i < rpaths.bufused; i++) {
        arg = rpaths.buf[i];
        if (arg) {
            if (options.bufused) WRITE_STR_BUFFER(options, ":");
            WRITE_BUFFER(options, arg, strlen(arg));
        }
    }
    WRITE_STR_BUFFER(options, "\0");
    SF(tmpi, setenv, -1, (PATHENV, options.buf, 1));
    FREE_BUFFER(options);

    if (wpath) {
        SF(tmpi, setenv, -1, (WRITEENV, wpath, 1));
    } else {
        SF(tmpi, unsetenv, -1, (WRITEENV));
    }

    /* then run it */
    if (argi < argc) {
        execvp(argv[argi], argv + argi);
        fprintf(stderr, "[usrview] ");
        perror(argv[argi]);

        return 1;

    } else {
        return 0;

    }
}

/* validate a path as OK */
void validatePath(char **path)
{
    struct Buffer_char pathok;
    struct stat sbuf;
    char *rpath;

    if (!*path) return;

    /* first make sure it's absolute */
    if (**path != '/') {
        *path = NULL;
        return;
    }

    /* then get its real path (don't worry about deallocation, there aren't
     * many of these) */
    *path = realpath(*path, NULL);
    if (*path == NULL) return;

    /* then check the ok file */
    INIT_BUFFER(pathok);
    WRITE_BUFFER(pathok, *path, strlen(*path));
    WRITE_STR_BUFFER(pathok, OKFILE);
    WRITE_STR_BUFFER(pathok, "\0");
    if (stat(pathok.buf, &sbuf) < 0) {
        /* file not found or otherwise very bad, kill it */
        *path = NULL;
        FREE_BUFFER(pathok);
        return;
    }
    FREE_BUFFER(pathok);
    if (sbuf.st_uid != geteuid()) {
        /* wrong owner */
        *path = NULL;
        return;
    }

    /* it's valid */
}
