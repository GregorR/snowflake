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

#define _XOPEN_SOURCE 500 /* for strtok_r, readdir_r */

#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "buffer.h"

#define PKGENV      "PKGS"
#define PKGBASE     "/pkg"
#define OKFILE      "/.usr_ok"
#define DEPSFILE    "/deps"

#define WHITESPACE " \t\r\n"
const char *whitespace = WHITESPACE;

#define COMPARATORS "=><"
const char *comparators = COMPARATORS;

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
    char *name, *version;
    struct VersionRequest verreqs[3]; /* =, >, < */
    int resolving;

    /* packages are in a hashmap, and a global list for ordering */
    struct PackageRequest *hmn, *prev, *next;
};


/* store packages we're thinking about in a hashmap */
static struct PackageRequest *packageHM[HM_SIZE];

/* as well as a list for a global order */
static struct PackageRequest *packageHead, *packageTail;

/* read in a list of package requests */
void readPackages(const char *packages, void (*foreach)(struct PackageRequest *));

/* convert a string comparator into an int comparator */
int comparatorToInt(const char *cmp, int cmplen);

/* create a request for a package version */
struct PackageRequest *newRequest(const char *name, int namelen, int cmp, const char *version, int versionlen);

/* get a package by name */
struct PackageRequest *getPackage(const char *name);

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

int main(int argc, char **argv)
{
    struct Buffer_char packages, path;
    struct Buffer_charp usrviewArgs;
    char *arg, *wpath = NULL;
    int argi, i;
    int execing = 1, listing = 0, nocommand = 0;
    struct PackageRequest *pkg;
    struct VersionRequest *ver;

    INIT_BUFFER(packages);

    /* read in all the various things that can request packages */

    /* first, environment variable */
    arg = getenv(PKGENV);
    if (arg) {
        WRITE_BUFFER(packages, arg, strlen(arg));
    } else {
        WRITE_STR_BUFFER(packages, "default");
    }
    WRITE_STR_BUFFER(packages, " ");

#define ARG(s) if (!strcmp(arg, #s))
    /* then, arguments */
    for (argi = 1; argi < argc; argi++) {
        arg = argv[argi];
        if (arg[0] == '-') {
            ARG(-r) {
                /* reset! */
                packages.bufused = 0;

            } else ARG(-m) {
                execing = 1;
                nocommand = 1;

            } else ARG(-s) {
                execing = 0;
                listing = 1;

            } else ARG(-w) {
                if (argi < argc - 1) {
                    argi++;
                    wpath = argv[argi];
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

            }

        } else {
            WRITE_BUFFER(packages, arg, strlen(arg));
            WRITE_STR_BUFFER(packages, " ");

        }
    }
    WRITE_STR_BUFFER(packages, "\0");

    /* store it back in the environment */
    setenv(PKGENV, packages.buf, 1);

    /* now, feed it into our packages list */
    readPackages(packages.buf, NULL);

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
                WRITE_STR_BUFFER(path, PKGBASE);
                WRITE_STR_BUFFER(path, "/");
            }
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

/* read in a list of package requests; note: destroys the string */
void readPackages(const char *packages, void (*foreach)(struct PackageRequest *))
{
    struct PackageRequest *pkg;
    const char *name, *nameend;
    const char *cmp, *cmpend;
    const char *version, *versionend;

    while (packages && packages[0]) {
        name = nameend =
            cmp = cmpend =
            version = versionend =
            NULL;

        /* cut off any leading spaces */
        while (*packages && strchr(whitespace, *packages)) packages++;
        if (!*packages) break;

        /* got the name part */
        name = packages;
        nameend = strpbrk(packages, WHITESPACE COMPARATORS);
        if (nameend == NULL) nameend = name + strlen(name);

        /* find the beginning of the comparator */
        cmp = nameend;
        while (*cmp && strchr(whitespace, *cmp)) cmp++;
        if (!*cmp || !strchr(comparators, *cmp)) cmp = NULL;

        /* if we have a comparator, get that info out */
        if (cmp) {
            /* we have a comparator, find the end of it */
            cmpend = cmp;
            while (*cmpend && strchr(comparators, *cmpend)) cmpend++;

            /* find the beginning of the version string */
            version = cmpend;
            while (*version && strchr(whitespace, *version)) version++;

            /* and the end of the version string */
            versionend = version;
            while (*versionend && !strchr(whitespace, *versionend)) versionend++;

            packages = versionend;

        } else {
            packages = nameend;

        }

        /* now create the package/version request */
        pkg = newRequest(name, nameend - name, comparatorToInt(cmp, cmpend - cmp), version, versionend - version);
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
struct PackageRequest *newRequest(const char *nameo, int namelen, int cmp, const char *versiono, int versionlen)
{
    char *name, *version;
    struct PackageRequest *pkg;
    struct VersionRequest *ver;
    unsigned long hash;
    int verslot;

    /* allocate name and version locally */
    SF(name, malloc, NULL, (namelen + 1));
    strncpy(name, nameo, namelen);
    name[namelen] = '\0';
    version = NULL;
    if (versiono) {
        SF(version, malloc, NULL, (versionlen + 1));
        strncpy(version, versiono, versionlen);
        version[versionlen] = '\0';
    }

    /* check if it's already there */
    pkg = getPackage(name);
    if (pkg) {
        free(name);
    } else {
        /* create it */
        SF(pkg, calloc, NULL, (1, sizeof(struct PackageRequest)));
        pkg->name = name;

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
struct PackageRequest *getPackage(const char *name)
{
    unsigned long hash = strhash((const unsigned char *) name);

    struct PackageRequest *pkg = packageHM[hash % HM_SIZE];

    while (pkg) {
        if (!strcmp(pkg->name, name)) return pkg;
        pkg = pkg->hmn;
    }

    return NULL;
}

/* comparator for versions */
int versionCmp(int cmp, const char *vera, const char *verb)
{
    while (*vera && *verb) {
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

    /* if the string is over, it's 0 */
    if (!*vers) return 0;

    /* skip dots */
    while (*vers == '.') vers++;

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

    /* otherwise, accept the string component as an odd encoding */
    vernum = 0;
    while (isalpha(*vers)) {
        unsigned char verc = *vers++;
        vernum *= 27;
        if (verc >= 'A' && verc <= 'Z') verc += 'a' - 'A';
        verc -= 'a' - 1;
        vernum += verc;
    }
    *endptr = (char *) vers;
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
    WRITE_STR_BUFFER(path, PKGBASE);
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
                WRITE_STR_BUFFER(path, "/usr");
                WRITE_STR_BUFFER(path, OKFILE);
                WRITE_STR_BUFFER(path, "\0");
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
    WRITE_STR_BUFFER(path, DEPSFILE);
    WRITE_STR_BUFFER(path, "\0");
    if ((depsfile = fopen(path.buf, "r"))) {
        /* OK, snag the deps */
        INIT_BUFFER(deps);
        READ_FILE_BUFFER(deps, depsfile);
        fclose(depsfile);
        WRITE_STR_BUFFER(deps, "\0");
        readPackages(deps.buf, resolve);
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
