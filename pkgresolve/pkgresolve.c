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

#define _XOPEN_SOURCE 600 /* for strtok_r, readdir_r, setenv */

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "buffer.h"

#define PKGENV      "PKGS"
#define CONFIGENV   "PKGCONFIGURATION"
#define PKGBASE     "/pkg"
#define DEFAULTPATH "/default"
#define OKFILE      "/.usr_ok"
#define DEPSFILE    "/deps"

#define WHITESPACE " \t\r\n"
const char *whitespace = WHITESPACE;

#define COMPARATORS "=><"
const char *comparators = COMPARATORS;

#define CONFIGURATIONER ':'
#define CONFIGURATIONERS ":"
const char *configurationers = CONFIGURATIONERS;

/* bitflags for comparators */
#define EQ      1
#define GT      2
#define LT      4

#define HM_SIZE 1024

BUFFER(charp, char *);
#define WRITE_STR_BUFFER(buffer, str) WRITE_BUFFER(buffer, str, sizeof(str)-1)

/* a version request */
struct VersionRequest {
    int cmp;
    char *version;
};

/* a package request */
struct PackageRequest {
    char *name, *version, *configuration;
    struct VersionRequest verreqs[3]; /* =, >, < */
    int resolving;

    /* packages are in a hashmap, and a global list for ordering */
    struct PackageRequest *hmn, *prev, *next;
};


/* store packages we're thinking about in a hashmap */
static struct PackageRequest *packageHM[HM_SIZE];

/* as well as a list for a global order */
static struct PackageRequest *packageHead, *packageTail;

/* usage statement */
void usage(char *argvz);

/* read in a list of package requests */
void readPackages(const char *packages, const char *configuration, int configurationlen, void (*foreach)(struct PackageRequest *));

/* convert a string comparator into an int comparator */
int comparatorToInt(const char *cmp, int cmplen);

/* create a request for a package version */
struct PackageRequest *newRequest(const char *name, int namelen, int cmp, const char *version, int versionlen, const char *configuration, int configurationlen);

/* get a package by name */
struct PackageRequest *getPackage(const char *name, const char *configuration);

/* comparator for versions */
int versionCmp(int cmp, const char *vera, const char *verb);

/* get a semi-logical number out of a version string */
int versionNumeric(const char *vers, char **endptr);

/* resolve this package and all of its dependencies */
void resolve(struct PackageRequest *pkg);

/* make this package's version requests resolvable */
void makeResolvable(struct PackageRequest *pkg);

/* is this version OK for this package? */
int versionOK(struct PackageRequest *pkg, const char *version);

/* set up a quickpath for "quick" package installs */
char *setupQuickPath(const char *qpath);

#if !defined(TEST)
int main(int argc, char **argv)
{
    struct Buffer_char packages, path;
    struct Buffer_charp usrviewArgs;
    char *arg, *wpath = NULL, *qpath = NULL;
    char *defConfiguration;
    int argi, i;
    int execing = 1, nocommand = 0;
    struct PackageRequest *pkg;

    INIT_BUFFER(packages);

    /* find our configuration */
    defConfiguration = getenv(CONFIGENV);
    if (!defConfiguration) {
        defConfiguration = DEFAULT_CONFIGURATION;
    }

    /* read in all the various things that can request packages */

    /* first, environment variable */
    arg = getenv(PKGENV);
    if (arg) {
        WRITE_BUFFER(packages, arg, strlen(arg));
    } else {
        WRITE_STR_BUFFER(packages, "default");
    }
    WRITE_STR_BUFFER(packages, " ");

#define ARGL(l, s) if (!strcmp(arg, #l) || !strcmp(arg, #s))
#define ARG(s) if (!strcmp(arg, #s))
    /* then, arguments */
    for (argi = 1; argi < argc; argi++) {
        arg = argv[argi];
        if (arg[0] == '-') {
            ARGL(--reset, -r) {
                /* reset! */
                packages.bufused = 0;

            } else ARGL(--configuration, -c) {
                if (argi < argc - 1) {
                    argi++;
                    defConfiguration = argv[argi];
                }

            } else ARGL(--file, -f) {
                if (argi < argc - 1) {
                    FILE *pkgFile;
                    struct Buffer_char fbuf;
                    argi++;

                    /* read it in */
                    SF(pkgFile, fopen, NULL, (argv[argi], "r"));
                    INIT_BUFFER(fbuf);
                    READ_FILE_BUFFER(fbuf, pkgFile);
                    fclose(pkgFile);

                    /* skip the #! line */
                    if (fbuf.buf[0] == '#') {
                        size_t i;
                        for (i = 1; i < fbuf.bufused && fbuf.buf[i] && fbuf.buf[i] != '\n'; i++);
                        i++;
                        if (i < fbuf.bufused) {
                            memmove(fbuf.buf, fbuf.buf + i, fbuf.bufused - i);
                            fbuf.bufused -= i;
                        }
                    }

                    /* copy them in */
                    WRITE_BUFFER(packages, fbuf.buf, fbuf.bufused);
                    WRITE_STR_BUFFER(packages, " ");

                    /* if anything remains, it's the command */
                    argi++;
                    if (argi < argc) {
                        execing = 1;
                        nocommand = 0;
                        break;
                    }
                }

            } else ARGL(--remount, -m) {
                execing = 1;
                nocommand = 1;

            } else ARGL(--show, -s) {
                execing = 0;

            } else ARGL(--write-to, -w) {
                if (argi < argc - 1) {
                    argi++;
                    wpath = argv[argi];
                }

            } else ARGL(--quick-write-to, -q) {
                if (argi < argc - 1) {
                    argi++;
                    qpath = argv[argi];
                }

            } else ARG(-e) {
                WRITE_STR_BUFFER(packages, "=");

            } else ARG(-l) {
                WRITE_STR_BUFFER(packages, "<");

            } else ARG(-L) {
                WRITE_STR_BUFFER(packages, "<=");

            } else ARG(-g) {
                WRITE_STR_BUFFER(packages, ">");

            } else ARG(-G) {
                WRITE_STR_BUFFER(packages, ">=");

            } else ARG(--) {
                /* done, rest is the command */
                argi++;
                execing = 1;
                nocommand = 0;
                break;

            } else {
                usage(argv[0]);
                exit(1);

            }

        } else {
            WRITE_BUFFER(packages, arg, strlen(arg));
            WRITE_STR_BUFFER(packages, " ");

        }
    }
    WRITE_STR_BUFFER(packages, "\0");

    /* if we have a qpath, set it up */
    if (qpath) wpath = setupQuickPath(qpath);

    /* store it back in the environment */
    setenv(PKGENV, packages.buf, 1);
    setenv(CONFIGENV, defConfiguration, 1);

    /* now, feed it into our packages list */
    readPackages(packages.buf, defConfiguration, strlen(defConfiguration), NULL);

    /* reverse the list so that explicitly-stated dependencies are highest-prio
     * (last-listed) first */
    pkg = packageHead;
    packageHead = packageTail;
    packageTail = pkg;
    for (pkg = packageHead; pkg; pkg = pkg->next) {
        struct PackageRequest *tmp = pkg->prev;
        pkg->prev = pkg->next;
        pkg->next = tmp;
    }

    /* now go through resolving dependencies */
    for (pkg = packageHead; pkg; pkg = pkg->next) {
        resolve(pkg);
    }

    /* collect them all into args for usrview */
    INIT_BUFFER(usrviewArgs);
    if (execing) {
        WRITE_ONE_BUFFER(usrviewArgs, "usrview");
        WRITE_ONE_BUFFER(usrviewArgs, "-r");
        if (wpath) {
            WRITE_ONE_BUFFER(usrviewArgs, "-w");
            WRITE_ONE_BUFFER(usrviewArgs, wpath);
        }
    }
    for (pkg = packageHead; pkg; pkg = pkg->next) {
        if (pkg->version) {
            INIT_BUFFER(path);
            if (execing) {
                WRITE_STR_BUFFER(path, PKGBASE "/");
            }
            WRITE_BUFFER(path, pkg->configuration, strlen(pkg->configuration));
            WRITE_STR_BUFFER(path, "/");
            WRITE_BUFFER(path, pkg->name, strlen(pkg->name));
            WRITE_STR_BUFFER(path, "/");
            WRITE_BUFFER(path, pkg->version, strlen(pkg->version));
            if (execing)
                WRITE_STR_BUFFER(path, "/usr");
            WRITE_STR_BUFFER(path, "\0");
            WRITE_ONE_BUFFER(usrviewArgs, path.buf);
        }
    }

    /* as well as the command itself */
    if (execing && !nocommand) {
        WRITE_ONE_BUFFER(usrviewArgs, "--");
        if (argi < argc) {
            for (i = argi; i < argc; i++) {
                WRITE_ONE_BUFFER(usrviewArgs, argv[i]);
            }
        } else {
            /* use the shell */
            arg = getenv("SHELL");
            if (!arg) arg = "/bin/sh";
            WRITE_ONE_BUFFER(usrviewArgs, arg);
        }
    }

    /* and either exec or list what we got */
    if (execing) {
        WRITE_ONE_BUFFER(usrviewArgs, NULL);
        execvp(usrviewArgs.buf[0], usrviewArgs.buf);
        perror(usrviewArgs.buf[0]);
        return 1;

    } else {
        for (i = 0; i < usrviewArgs.bufused; i++) {
            printf("%s\n", usrviewArgs.buf[i]);
        }

    }

#if 0
    /* and print everything we got */
    for (pkg = packageHead; pkg; pkg = pkg->next) {
        printf("%s %s\n", pkg->name, pkg->version);
        for (i = 0; i < 3; i++) {
            ver = &pkg->verreqs[i];
            if (ver->cmp) {
                printf ("  ");
                if (ver->cmp & GT) printf(">");
                if (ver->cmp & LT) printf("<");
                if (ver->cmp & EQ) printf("=");
                printf(" %s\n", ver->version);
            }
        }
    }
#endif

    return 0;
}

void usage(char *argvz)
{
    fprintf(stderr, "Use: %s [options] [packages] [-- command]\n"
                    "Options:\n"
                    "\t--reset|-r:\n"
                    "\t\tReset to default package selection.\n"
                    "\t--configuration|-c <configuration>:\n"
                    "\t\tUse the specified package configuration (/pkg/<cfg>)\n"
                    "\t--file|-f <file>:\n"
                    "\t\tLoad package list from the specified file. Any further options are interpreted\n"
                    "\t\tas the command to execute. This option is intended to be used in #! lines of\n"
                    "\t\tscripts.\n"
                    "\t--remount|-m:\n"
                    "\t\tRemount the current package selection instead of making a new one. Only usable\n"
                    "\t\tby root, only intended for the boot sequence.\n"
                    "\t--show|-s:\n"
                    "\t\tInstead of executing anything, show the list of mounts.\n"
                    "\t--write-to|-w <dir>:\n"
                    "\t\tWrite to the given directory.\n"
                    "\t--quick-write-to|-q <dir>:\n"
                    "\t\tSet up the given directory as a package under /pkg, and write to its usr/.\n"
                    , argvz);
}

#elif defined(TEST_VERSION)
int main(int argc, char **argv)
{
    char *v;
    int pos = 0;

    if (argc == 2) {
        v = argv[1];
        while (*v)
            printf("%s%d", (pos++ == 0) ? "" : ".", versionNumeric(v, &v));
        printf("\n");
    } else if (argc == 4) {
        printf("%d\n", versionCmp(comparatorToInt(argv[2], strlen(argv[2])), argv[1], argv[3]));
    } else {
        return 1;
    }
    return 0;
}

#endif

/* read in a list of package requests; note: destroys the string */
void readPackages(const char *packages, const char *defConfiguration, int defConfigurationlen, void (*foreach)(struct PackageRequest *))
{
    struct PackageRequest *pkg;
    const char *name, *nameend;
    const char *cmp, *cmpend;
    const char *version, *versionend;
    const char *reqConfiguration, *reqConfigurationend;
    const char *configuration;
    int configurationlen;

    while (packages && packages[0]) {
        name = nameend =
            cmp = cmpend =
            version = versionend =
            reqConfiguration = reqConfigurationend =
            configuration =
            NULL;
        configurationlen = 0;

        /* cut off any leading spaces */
        while (*packages && strchr(whitespace, *packages)) packages++;
        if (!*packages) break;

        /* got the name part */
        name = packages;
        nameend = strpbrk(packages, WHITESPACE COMPARATORS CONFIGURATIONERS);
        if (nameend == NULL) nameend = name + strlen(name);

        /* find the beginning of the comparator */
        cmp = nameend;
        while (cmp) {
            while (*cmp && strchr(whitespace, *cmp)) cmp++;
            packages = cmp;

            /* if we're at the end of the string, we're done */
            if (!*cmp) {
                cmp = NULL;

            /* if we have a comparator, get that info out */
            } else if (strchr(comparators, *cmp)) {
                /* we have a comparator, find the end of it */
                cmpend = cmp;
                while (*cmpend && strchr(comparators, *cmpend)) cmpend++;
    
                /* find the beginning of the version string */
                version = cmpend;
                while (*version && strchr(whitespace, *version)) version++;
    
                /* and the end of the version string */
                versionend = strpbrk(version, WHITESPACE COMPARATORS CONFIGURATIONERS);
                cmp = versionend;

            /* if we have a configurationer, get that info out */
            } else if (*cmp == CONFIGURATIONER) {
                cmpend = cmp + 1;

                /* find the beginning of the configuration string */
                reqConfiguration = cmpend;
                while (*reqConfiguration && strchr(whitespace, *reqConfiguration)) reqConfiguration++;

                /* and the end of the configuration string */
                reqConfigurationend = strpbrk(reqConfiguration, WHITESPACE COMPARATORS CONFIGURATIONERS);
                cmp = reqConfigurationend;
    
            } else {
                cmp = NULL;
    
            }
        }

        /* figure out the configuration */
        if (reqConfiguration) {
            configuration = reqConfiguration;
            configurationlen = reqConfigurationend - reqConfiguration;
        } else {
            configuration = defConfiguration;
            configurationlen = defConfigurationlen;
        }

        /* now create the package/version request */
        pkg = newRequest(name, nameend - name, comparatorToInt(cmp, cmpend - cmp), version, versionend - version, configuration, configurationlen);
        if (foreach) foreach(pkg);
    }
}

/* convert a string comparator into an int comparator */
int comparatorToInt(const char *cmp, int cmplen)
{
    int cmpi = 0, i;
    if (cmp == NULL) return 0;
    for (i = 0; i < cmplen; i++) {
        switch (cmp[i]) {
            case '>':
                cmpi |= GT;
                break;

            case '<':
                cmpi |= LT;
                break;

            case '=':
                cmpi |= EQ;
                break;
        }
    }

    if ((cmpi & LT) && (cmpi & GT)) cmpi = EQ; /* change nonsense to some other nonsense */

    return cmpi;
}

/* string hashing function */
static unsigned long strhash(const unsigned char *str)
{
    unsigned long hash = 0;
    int c;

    while ((c = *str++))
        hash = c + (hash << 6) + (hash << 16) - hash;

    return hash;
}

/* create a request for a package version */
struct PackageRequest *newRequest(const char *nameo, int namelen, int cmp, const char *versiono, int versionlen, const char *configurationo, int configurationlen)
{
    char *name, *version, *configuration;
    struct PackageRequest *pkg;
    struct VersionRequest *ver;
    unsigned long hash;
    int verslot;

    /* allocate name, version and configuration locally */
    SF(name, malloc, NULL, (namelen + 1));
    strncpy(name, nameo, namelen);
    name[namelen] = '\0';

    version = NULL;
    if (versiono) {
        SF(version, malloc, NULL, (versionlen + 1));
        strncpy(version, versiono, versionlen);
        version[versionlen] = '\0';
    }

    SF(configuration, malloc, NULL, (configurationlen + 1));
    strncpy(configuration, configurationo, configurationlen);
    configuration[configurationlen] = '\0';

    /* check if it's already there */
    pkg = getPackage(name, configuration);
    if (pkg) {
        free(name);
        free(configuration);
    } else {
        /* create it */
        SF(pkg, calloc, NULL, (1, sizeof(struct PackageRequest)));
        pkg->name = name;
        pkg->configuration = configuration;

        /* add it to the hashmap */
        hash = strhash((const unsigned char *) name) % HM_SIZE;
        pkg->hmn = packageHM[hash];
        packageHM[hash] = pkg;

        /* and the ordered list */
        if (packageTail) {
            packageTail->next = pkg;
            pkg->prev = packageTail;
            packageTail = pkg;
        } else {
            packageHead = packageTail = pkg;
        }
    }

    if (!version) {
        /* no version request, we're done! */
        return pkg;
    }

    /* now make a compatible version request */
    if (cmp == EQ) {
        /* easy, just force equality */
        pkg->verreqs[0].cmp = EQ;
        free(pkg->verreqs[0].version); /* in case a request already existed */
        pkg->verreqs[0].version = version;

    } else {
        /* choose a slot to put this version request in */
        if (cmp & GT) verslot = 1;
        else verslot = 2;
        ver = &pkg->verreqs[verslot];

        /* if there's nothing already there, easy */
        if (ver->cmp == 0) {
            ver->cmp = cmp;
            ver->version = version;

        } else {
            /* we'll have to find a compatible versioning; if we're equal,
             * choose the more restrictive comparator, otherwise choose the
             * more restrictive version */
            if (versionCmp(EQ, version, ver->version)) {
                free(version);
                ver->cmp &= cmp;

            } else {
                int rescmp = cmp & ~(EQ);
                if (versionCmp(rescmp, version, ver->version)) {
                    /* we are more restrictive, so we win */
                    ver->cmp = cmp;
                    free(ver->version);
                    ver->version = version;

                } else {
                    free(version);

                }

            }

        }

    }

    return pkg;
}

/* get a package by name */
struct PackageRequest *getPackage(const char *name, const char *configuration)
{
    unsigned long hash = strhash((const unsigned char *) name);

    struct PackageRequest *pkg = packageHM[hash % HM_SIZE];

    while (pkg) {
        if (!strcmp(pkg->name, name) && !strcmp(pkg->configuration, configuration)) return pkg;
        pkg = pkg->hmn;
    }

    return NULL;
}

/* comparator for versions */
int versionCmp(int cmp, const char *vera, const char *verb)
{
    while (*vera || *verb) {
        int verca = versionNumeric(vera, (char **) &vera);
        int vercb = versionNumeric(verb, (char **) &verb);

        if (verca != vercb) {
            /* this is an ending point */
            if (cmp == EQ) return 0;
            else if (cmp & GT) return verca > vercb;
            else if (cmp & LT) return verca < vercb;
        }
    }

    /* we made it all the way through both strings, so they're equal */
    if (cmp & EQ) return 1;
    return 0;
}

/* get a semi-logical number out of a version string */
int versionNumeric(const char *vers, char **endptr)
{
    int vernum;

    /* skip separators */
    while (*vers && !isalnum(*vers)) vers++;

    /* if the string is over, it's 0 */
    if (!*vers) {
        *endptr = (char *) vers;
        return 0;
    }

    /* accept digits directly */
    if (isdigit(*vers))
        return (int) strtol(vers, endptr, 10);

    /* certain constants are also accepted directly */
    if (!strncmp(vers, "alpha", 5)) {
        *endptr = (char *) vers + 5;
        return -2;
    }
    if (!strncmp(vers, "beta", 4)) {
        *endptr = (char *) vers + 4;
        return -1;
    }
    if (*vers == 'a' && !isalpha(vers[1])) {
        *endptr = (char *) vers + 1;
        return -2;
    }
    if (*vers == 'b' && !isalpha(vers[1])) {
        *endptr = (char *) vers + 1;
        return -1;
    }

    /* otherwise, accept one character as number from 1-26 (1 for A, 2 for B,
     * as only a and b are considered alpha and beta) */
    *endptr = (char *) vers + 1;
    vernum = *vers;
    if (vernum >= 'A' && vernum <= 'Z') vernum += 'a' - 'A';
    vernum -= 'a' - 1;
    return vernum;
}

/* resolve this package and all of its dependencies */
void resolve(struct PackageRequest *pkg)
{
    struct Buffer_char path, deps;
    size_t dirlen;
    FILE *depsfile;
    path.buf = NULL;

    /* don't recurse infinitely */
    if (pkg->resolving) return;
    pkg->resolving = 1;

    makeResolvable(pkg);

    if (pkg->version) {
        /* it's already been resolved, is it still OK? */
        if (versionOK(pkg, pkg->version)) {
            /* already fully resolved, no need to recurse here */
            goto done;
        } else {
            /* nope, need to re-resolve! */
            free(pkg->version);
            pkg->version = NULL;
        }
    }

    /* package directory */
    INIT_BUFFER(path);
    WRITE_STR_BUFFER(path, PKGBASE "/");
    WRITE_BUFFER(path, pkg->configuration, strlen(pkg->configuration));
    WRITE_STR_BUFFER(path, "/");
    WRITE_BUFFER(path, pkg->name, strlen(pkg->name));
    dirlen = path.bufused;
    WRITE_STR_BUFFER(path, "\0");

    /* choose a version */
    if (!pkg->version) {
        DIR *dh;
        struct dirent de, *dep;
        dh = opendir(path.buf);
        if (!dh) {
            /* well, this was a dud! */
            goto done;
        }

        while (readdir_r(dh, &de, &dep) == 0 && dep) {
            if (de.d_name[0] != '.') {
                /* potentially a version, check for the necessary dotfile */
                path.bufused = dirlen;
                WRITE_STR_BUFFER(path, "/");
                WRITE_BUFFER(path, de.d_name, strlen(de.d_name));
                WRITE_STR_BUFFER(path, "/usr" OKFILE "\0");
                if (access(path.buf, F_OK) == 0) {
                    /* this is a valid version, does it match our requirements? */
                    if (versionOK(pkg, de.d_name)) {
                        /* is it greater than the current match? */
                        if (!pkg->version ||
                            versionCmp(LT, pkg->version, de.d_name)) {
                            /* choose it! */
                            free(pkg->version);
                            SF(pkg->version, strdup, NULL, (de.d_name));
                        }
                    }
                }
            }
        }
    }

    if (!pkg->version) {
        /* couldn't find one, bail */
        goto done;
    }

    /* if it has a deps file, use it */
    path.bufused = dirlen;
    WRITE_STR_BUFFER(path, "/");
    WRITE_BUFFER(path, pkg->version, strlen(pkg->version));
    WRITE_STR_BUFFER(path, DEPSFILE "\0");
    if ((depsfile = fopen(path.buf, "r"))) {
        /* OK, snag the deps */
        INIT_BUFFER(deps);
        READ_FILE_BUFFER(deps, depsfile);
        fclose(depsfile);
        WRITE_STR_BUFFER(deps, "\0");
        readPackages(deps.buf, pkg->configuration, strlen(pkg->configuration), resolve);
    }

done:
    if (path.buf) FREE_BUFFER(path);
    pkg->resolving = 0;
}

/* make this package request resolvable */
void makeResolvable(struct PackageRequest *pkg)
{
    struct VersionRequest *ver = &pkg->verreqs[0];
    if (ver->cmp) {
        /* easiest case, just ignore any other requests */
        ver = &pkg->verreqs[1];
        ver->cmp = 0;
        free(ver->version);
        ver = &pkg->verreqs[2];
        ver->cmp = 0;
        free(ver->version);

    } else if (pkg->verreqs[1].cmp && pkg->verreqs[2].cmp) {
        /* need to check whether the > and < are compatible */
        if (!versionCmp(LT, pkg->verreqs[1].version, pkg->verreqs[2].version)) {
            /* nope, get rid of the broken < upper bound */
            ver = &pkg->verreqs[2];
            ver->cmp = 0;
            free(ver->version);
        }
    }
}

/* is this version OK for this package? */
int versionOK(struct PackageRequest *pkg, const char *version)
{
    int i;
    for (i = 0; i < 3; i++) {
        struct VersionRequest *ver = &pkg->verreqs[i];
        if (ver->cmp) {
            if (!versionCmp(ver->cmp, version, ver->version)) return 0;
        }
    }
    return 1;
}

/* set up a quickpath for "quick" package installs */
char *setupQuickPath(const char *qpath)
{
    struct Buffer_char wpath;
    int i;
    const char *slash1 = NULL, *slash2 = NULL;
    size_t wpathlen;

    /* make sure it's in the right format */
    for(i = 0; qpath[i]; i++) {
        if (strchr(whitespace, qpath[i])) {
            fprintf(stderr, "-q path may not contain whitespace\n");
            exit(1);
        }
        if (qpath[i] == '/') {
            if (slash2) {
                fprintf(stderr, "-q path must contain exactly two slashes\n");
                exit(1);
            }
            if (slash1) {
                slash2 = qpath + i;
            } else {
                slash1 = qpath + i;
            }
        }
    }
    if (slash2 == NULL) {
        fprintf(stderr, "-q path must contain exactly two slashes\n");
        exit(1);
    }

#define TRYMKDIR() do {\
    if (mkdir(wpath.buf, 0755) == -1) { \
        if (errno != EEXIST) { \
            perror(wpath.buf); \
            exit(1); \
        } \
    } \
    } while (0)

    /* then set it up */
    INIT_BUFFER(wpath);
    WRITE_STR_BUFFER(wpath, PKGBASE "/");
    WRITE_BUFFER(wpath, qpath, slash1 - qpath);
    WRITE_STR_BUFFER(wpath, "\0");
    TRYMKDIR();
    wpath.bufused--;
    WRITE_BUFFER(wpath, slash1, slash2 - slash1);
    WRITE_STR_BUFFER(wpath, "\0");
    TRYMKDIR();
    wpath.bufused--;
    WRITE_BUFFER(wpath, slash2, strlen(slash2));
    WRITE_STR_BUFFER(wpath, "\0");
    TRYMKDIR();
    wpath.bufused--;
    WRITE_STR_BUFFER(wpath, "/usr\0");
    TRYMKDIR();
    wpath.bufused--;
    wpathlen = wpath.bufused;
    WRITE_STR_BUFFER(wpath, OKFILE "\0");
    if (creat(wpath.buf, 0644) == -1) {
        if (errno != EEXIST) {
            perror(wpath.buf);
            exit(1);
        }
    }

    /* send the wpath back */
    wpath.bufused = wpathlen;
    WRITE_STR_BUFFER(wpath, "\0");
    return wpath.buf;
}
