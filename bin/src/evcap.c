// evcap - tiny evdev capture tool for Yandex Station Street (mango)
// Build: zig cc -target arm-linux-musleabihf -static -O2 -o evcap evcap.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <linux/input.h>

#define MAXDEV 8

struct dev {
    int fd;
    char path[64];
    char name[128];
};

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
    struct dev devs[MAXDEV];
    int n = 0;
    if (argc < 2) {
        fprintf(stderr, "usage: %s /dev/input/eventN ...\n", argv[0]);
        return 2;
    }
    for (int i = 1; i < argc && n < MAXDEV; i++) {
        int fd = open(argv[i], O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            fprintf(stderr, "open %s: %s\n", argv[i], strerror(errno));
            continue;
        }
        devs[n].fd = fd;
        snprintf(devs[n].path, sizeof(devs[n].path), "%s", argv[i]);
        if (ioctl(fd, EVIOCGNAME(sizeof(devs[n].name)), devs[n].name) < 0)
            snprintf(devs[n].name, sizeof(devs[n].name), "?");
        fprintf(stderr, "listening %s (%s)\n", devs[n].path, devs[n].name);
        n++;
    }
    if (!n) return 1;
    long long start = now_ms();
    for (;;) {
        struct pollfd pfd[MAXDEV];
        for (int i = 0; i < n; i++) {
            pfd[i].fd = devs[i].fd;
            pfd[i].events = POLLIN;
            pfd[i].revents = 0;
        }
        int r = poll(pfd, n, 1000);
        if (r < 0) {
            if (errno == EINTR) continue;
            perror("poll");
            return 1;
        }
        for (int i = 0; i < n; i++) {
            if (!(pfd[i].revents & POLLIN)) continue;
            struct input_event ev;
            while (read(devs[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
                if (ev.type == EV_SYN) continue;
                printf("%lld %s %-16s type=%u code=%u value=%d\n",
                       now_ms() - start, devs[i].path, devs[i].name,
                       ev.type, ev.code, ev.value);
                fflush(stdout);
            }
        }
    }
}
