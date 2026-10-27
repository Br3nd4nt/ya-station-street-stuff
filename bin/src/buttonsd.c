// buttonsd - standalone evdev button daemon for Yandex Station Street (mango)
//
// Replaces the button-handling part of `maind --platformd` for "bunker" mode.
// Reads /dev/input/event* directly, debounces, detects short/long/repeat
// presses and runs configurable shell actions.
//
// Build (static, no external libs):
//   zig cc -target arm-linux-musleabihf -static -O2 -o buttonsd buttonsd.c
//
// Usage:
//   buttonsd [-f] [-c /data/opt/etc/buttonsd.conf]
//     -f  foreground (default if -d is not given)
//     -d  daemonize
//
// Config format: simple `key = value`, `#` comments.
//   devices=/dev/input/event0,/dev/input/event2,/dev/input/event3
//   grab=0
//   hook_dir=/data/opt/etc/buttons.d
//   log=/data/opt/var/log/buttonsd.log
//   volume_step=5
//   long_ms=900
//   repeat_delay_ms=500
//   repeat_ms=180
//   cmd_activate=/path/to/script
//   cmd_activate_long=...
//   cmd_volume_up=...
//   map_582=activate
//
// Hook files (executable) take priority over cmd_*:
//   $hook_dir/on_<name>.sh
//   $hook_dir/on_<name>_long.sh

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <poll.h>
#include <linux/input.h>

#define MAX_DEV 8
#define MAX_MAP 64
#define MAX_CMD 512
#define MAX_PATH 256

struct device {
    char path[MAX_PATH];
    int fd;
};

struct mapping {
    int code;
    char name[32];
};

struct key_state {
    int mapped;
    int active;
    int long_fired;
    int clicks;
    long long press_ms;
    long long last_repeat_ms;
    long long last_release_ms;
    char name[32];
};

static struct device g_devs[MAX_DEV];
static int g_ndev = 0;
static struct mapping g_map[MAX_MAP];
static int g_nmap = 0;
static struct key_state g_keys[KEY_MAX + 1];

static char g_devices_cfg[1024] = "/dev/input/event0,/dev/input/event2,/dev/input/event3";
static char g_hook_dir[MAX_PATH] = "/data/opt/etc/buttons.d";
static char g_log_path[MAX_PATH] = "/data/opt/var/log/buttonsd.log";
static char g_pid_path[MAX_PATH] = "/data/opt/var/run/buttonsd.pid";
static int g_grab = 0;
static int g_volume_step = 5;
static int g_long_ms = 900;
static int g_repeat_delay_ms = 500;
static int g_repeat_ms = 180;
static int g_multiclick_ms = 400;
static char g_multiclick[128] = "play_pause";
static int g_daemonize = 0;
static int g_running = 1;
static int g_suspend_with_maind = 1;
static int g_suspended = 0;
static int g_led_init = 1;
static int g_led_ready = 0;
static int g_log_fd = -1;
static char g_cmd[16][MAX_CMD];

static const struct {
    int code;
    const char *name;
} g_default_map[] = {
    { KEY_VOICECOMMAND, "activate" },
    { KEY_ASSISTANT,    "activate" },
    { KEY_MUTE,         "mute" },
    { KEY_VOLUMEUP,     "volume_up" },
    { KEY_VOLUMEDOWN,   "volume_down" },
    { KEY_POWER,        "power" },
    { KEY_PAUSE,        "play_pause" },
    { KEY_PLAYPAUSE,    "play_pause" },
    { KEY_BLUETOOTH,    "bluetooth" },
    { KEY_COFFEE,       "action" },
    { KEY_COPY,         "play_pause" },
    { KEY_NEXTSONG,     "next" },
    { KEY_PREVIOUSSONG, "previous" },
    { KEY_STOPCD,       "stop" },
};

static const char *g_cmd_names[] = {
    "activate", "activate_long",
    "volume_up", "volume_down",
    "mute", "power", "power_long",
    "play_pause", "play_pause_long",
    "play_pause_2x", "play_pause_3x",
    "bluetooth", "action", "next", "previous", "stop",
    NULL
};

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void logmsg(const char *fmt, ...) {
    char buf[1024];
    struct timespec ts;
    struct tm tm;
    va_list ap;
    int n;

    clock_gettime(CLOCK_REALTIME, &ts);
    localtime_r(&ts.tv_sec, &tm);
    n = snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d.%03ld ",
                 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                 tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1000000);
    if (n < 0 || n >= (int)sizeof(buf)) return;
    va_start(ap, fmt);
    vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
    va_end(ap);
    n = strlen(buf);
    if (n < (int)sizeof(buf) - 1) {
        buf[n++] = '\n';
        buf[n] = 0;
    }
    if (g_log_fd >= 0) {
        if (write(g_log_fd, buf, n) < 0) { /* ignore */ }
    }
    if (!g_daemonize) {
        fputs(buf, stderr);
        fflush(stderr);
    }
}

static int is_multiclick(const char *name) {
    char tmp[sizeof(g_multiclick)];
    char *p, *save = NULL;
    snprintf(tmp, sizeof(tmp), "%s", g_multiclick);
    for (p = strtok_r(tmp, ", ", &save); p; p = strtok_r(NULL, ", ", &save)) {
        if (!strcmp(p, name)) return 1;
    }
    return 0;
}

static char *trim(char *s) {
    char *e;
    while (*s && isspace((unsigned char)*s)) s++;
    e = s + strlen(s);
    while (e > s && isspace((unsigned char)e[-1])) *--e = 0;
    return s;
}

static int find_cmd_slot(const char *key) {
    for (int i = 0; g_cmd_names[i]; i++) {
        char want[64];
        snprintf(want, sizeof(want), "cmd_%s", g_cmd_names[i]);
        if (!strcmp(key, want)) return i;
    }
    return -1;
}

static void map_add(int code, const char *name) {
    if (code < 0 || code > KEY_MAX) return;
    for (int i = 0; i < g_nmap; i++) {
        if (g_map[i].code == code) {
            snprintf(g_map[i].name, sizeof(g_map[i].name), "%s", name);
            return;
        }
    }
    if (g_nmap >= MAX_MAP) return;
    g_map[g_nmap].code = code;
    snprintf(g_map[g_nmap].name, sizeof(g_map[g_nmap].name), "%s", name);
    g_nmap++;
}

static void load_config(const char *path) {
    FILE *f = fopen(path, "r");
    char line[1024];

    if (!f) {
        logmsg("config: cannot open %s: %s (using defaults)", path, strerror(errno));
    } else {
        while (fgets(line, sizeof(line), f)) {
            char *s = trim(line);
            char *eq;
            if (!*s || *s == '#') continue;
            eq = strchr(s, '=');
            if (!eq) continue;
            *eq = 0;
            char *key = trim(s);
            char *val = trim(eq + 1);
            if (!strcmp(key, "devices")) {
                snprintf(g_devices_cfg, sizeof(g_devices_cfg), "%s", val);
            } else if (!strcmp(key, "hook_dir")) {
                snprintf(g_hook_dir, sizeof(g_hook_dir), "%s", val);
            } else if (!strcmp(key, "log")) {
                snprintf(g_log_path, sizeof(g_log_path), "%s", val);
            } else if (!strcmp(key, "pid_file")) {
                snprintf(g_pid_path, sizeof(g_pid_path), "%s", val);
            } else if (!strcmp(key, "grab")) {
                g_grab = atoi(val) != 0;
            } else if (!strcmp(key, "suspend_with_maind")) {
                g_suspend_with_maind = atoi(val) != 0;
            } else if (!strcmp(key, "led_init")) {
                g_led_init = atoi(val) != 0;
            } else if (!strcmp(key, "volume_step")) {
                g_volume_step = atoi(val);
                if (g_volume_step < 1) g_volume_step = 1;
            } else if (!strcmp(key, "long_ms")) {
                g_long_ms = atoi(val);
                if (g_long_ms < 100) g_long_ms = 100;
            } else if (!strcmp(key, "repeat_delay_ms")) {
                g_repeat_delay_ms = atoi(val);
                if (g_repeat_delay_ms < 0) g_repeat_delay_ms = 0;
            } else if (!strcmp(key, "repeat_ms")) {
                g_repeat_ms = atoi(val);
                if (g_repeat_ms < 40) g_repeat_ms = 40;
            } else if (!strcmp(key, "multiclick_ms")) {
                g_multiclick_ms = atoi(val);
                if (g_multiclick_ms < 100) g_multiclick_ms = 100;
            } else if (!strcmp(key, "multiclick")) {
                snprintf(g_multiclick, sizeof(g_multiclick), "%s", val);
            } else if (!strncmp(key, "map_", 4)) {
                int code = atoi(key + 4);
                map_add(code, val);
            } else {
                int slot = find_cmd_slot(key);
                if (slot >= 0)
                    snprintf(g_cmd[slot], sizeof(g_cmd[slot]), "%s", val);
            }
        }
        fclose(f);
    }
    for (int i = 0; i < (int)(sizeof(g_default_map) / sizeof(g_default_map[0])); i++)
        map_add(g_default_map[i].code, g_default_map[i].name);

    memset(g_keys, 0, sizeof(g_keys));
    for (int i = 0; i < g_nmap; i++) {
        int c = g_map[i].code;
        g_keys[c].mapped = 1;
        snprintf(g_keys[c].name, sizeof(g_keys[c].name), "%s", g_map[i].name);
    }
}

static int hook_exists(const char *name, int is_long, char *out, size_t outsz) {
    struct stat st;
    snprintf(out, outsz, "%s/on_%s%s.sh", g_hook_dir, name, is_long ? "_long" : "");
    if (stat(out, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & 0111))
        return 1;
    return 0;
}

static const char *config_cmd(const char *name, int is_long) {
    char want[64];
    snprintf(want, sizeof(want), "%s%s", name, is_long ? "_long" : "");
    for (int i = 0; g_cmd_names[i]; i++) {
        if (!strcmp(g_cmd_names[i], want)) {
            if (g_cmd[i][0]) return g_cmd[i];
            return NULL;
        }
    }
    return NULL;
}

static const char *builtin_cmd(const char *name, int is_long) {
    if (!strcmp(name, "volume_up") && !is_long)
        return "/data/opt/bin/buttons_volume.sh up";
    if (!strcmp(name, "volume_down") && !is_long)
        return "/data/opt/bin/buttons_volume.sh down";
    if (!strcmp(name, "mute") && !is_long)
        return "/data/opt/bin/buttons_mute.sh";
    if (!strcmp(name, "activate") && !is_long)
        return "/data/opt/bin/buttons_led.sh pulse 0 90 255";
    if (!strcmp(name, "activate") && is_long)
        return "/data/opt/bin/buttons_led.sh fill 255 0 0";
    if ((!strcmp(name, "power") || !strcmp(name, "action")) && !is_long)
        return "/data/opt/bin/buttons_battery.sh";
    if (!strcmp(name, "play_pause") && !is_long)
        return "/data/opt/bin/buttons_playpause.sh toggle";
    if (!strcmp(name, "play_pause_2x") && !is_long)
        return "/data/opt/bin/buttons_playpause.sh next";
    if (!strcmp(name, "play_pause_3x") && !is_long)
        return "/data/opt/bin/buttons_playpause.sh previous";
    if (!strcmp(name, "bluetooth") && !is_long)
        return "/data/opt/bin/buttons_bluetooth.sh";
    return NULL;
}

static void run_shell(const char *cmd) {
    pid_t pid = fork();
    if (pid == 0) {
        if (g_log_fd >= 0) {
            dup2(g_log_fd, STDOUT_FILENO);
            dup2(g_log_fd, STDERR_FILENO);
        }
        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    } else if (pid < 0) {
        logmsg("fork failed: %s", strerror(errno));
    }
}

static void run_hook(const char *hook, const char *name, int is_long) {
    pid_t pid = fork();
    if (pid == 0) {
        if (g_log_fd >= 0) {
            dup2(g_log_fd, STDOUT_FILENO);
            dup2(g_log_fd, STDERR_FILENO);
        }
        execl(hook, hook, name, is_long ? "long" : "short", (char *)NULL);
        _exit(127);
    } else if (pid < 0) {
        logmsg("fork failed: %s", strerror(errno));
    }
}

static void do_action(const char *name, int is_long) {
    char hook[MAX_PATH];
    const char *cmd;

    logmsg("action: %s%s", name, is_long ? " (long)" : "");
    if (hook_exists(name, is_long, hook, sizeof(hook))) {
        run_hook(hook, name, is_long);
        return;
    }
    cmd = config_cmd(name, is_long);
    if (!cmd) cmd = builtin_cmd(name, is_long);
    if (cmd) run_shell(cmd);
}

static int split_devices(char paths[][MAX_PATH], int max) {
    char tmp[sizeof(g_devices_cfg)];
    char *p, *save = NULL;
    int n = 0;
    snprintf(tmp, sizeof(tmp), "%s", g_devices_cfg);
    for (p = strtok_r(tmp, ",", &save); p && n < max; p = strtok_r(NULL, ",", &save)) {
        p = trim(p);
        if (*p) snprintf(paths[n++], MAX_PATH, "%s", p);
    }
    return n;
}

static void open_devices(void) {
    char paths[MAX_DEV][MAX_PATH];
    int want = split_devices(paths, MAX_DEV);

    for (int i = 0; i < g_ndev; i++) {
        if (g_devs[i].fd < 0) continue;
        int alive = 1;
        if (fcntl(g_devs[i].fd, F_GETFD) < 0) alive = 0;
        if (!alive) { close(g_devs[i].fd); g_devs[i].fd = -1; }
    }

    for (int i = 0; i < want; i++) {
        int found = 0;
        for (int j = 0; j < g_ndev; j++)
            if (!strcmp(g_devs[j].path, paths[i])) { found = 1; break; }
        if (found) continue;
        if (g_ndev >= MAX_DEV) break;
        int fd = open(paths[i], O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            if (errno != ENOENT && errno != ENODEV)
                logmsg("open %s: %s", paths[i], strerror(errno));
            continue;
        }
        char name[128] = "?";
        ioctl(fd, EVIOCGNAME(sizeof(name)), name);
        if (g_grab && ioctl(fd, EVIOCGRAB, 1) < 0)
            logmsg("EVIOCGRAB %s failed: %s", paths[i], strerror(errno));
        snprintf(g_devs[g_ndev].path, sizeof(g_devs[g_ndev].path), "%s", paths[i]);
        g_devs[g_ndev].fd = fd;
        g_ndev++;
        logmsg("listening %s (%s)%s", paths[i], name, g_grab ? " [grabbed]" : "");
    }
}

// Returns 1 when maind --platformd is alive. In that case maind already owns
// the buttons, so buttonsd must not run actions in parallel.
static int maind_platformd_running(void) {
    DIR *d = opendir("/proc");
    struct dirent *de;
    if (!d) return 0;
    while ((de = readdir(d)) != NULL) {
        char path[64];
        char buf[512];
        int fd, n;
        char *p, *end;

        if (de->d_name[0] < '0' || de->d_name[0] > '9') continue;
        snprintf(path, sizeof(path), "/proc/%s/cmdline", de->d_name);
        fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = 0;
        p = buf;
        end = buf + n;
        while (p < end) {
            if (!strcmp(p, "--platformd")) {
                closedir(d);
                return 1;
            }
            p += strlen(p) + 1;
        }
    }
    closedir(d);
    return 0;
}

static void reset_key_states(void) {
    for (int i = 0; i <= KEY_MAX; i++) {
        g_keys[i].active = 0;
        g_keys[i].long_fired = 0;
        g_keys[i].clicks = 0;
    }
}

static void handle_key(int code, int value, long long now) {
    struct key_state *ks;

    if (code < 0 || code > KEY_MAX) return;
    ks = &g_keys[code];
    if (!ks->mapped) return;

    if (value == 1) {
        if (ks->active) return;
        ks->active = 1;
        ks->long_fired = 0;
        ks->press_ms = now;
        ks->last_repeat_ms = now;
        if (!strcmp(ks->name, "volume_up") || !strcmp(ks->name, "volume_down"))
            do_action(ks->name, 0);
    } else if (value == 0) {
        long long dur;
        if (!ks->active) return;
        dur = now - ks->press_ms;
        ks->active = 0;

        if (!strcmp(ks->name, "volume_up") || !strcmp(ks->name, "volume_down"))
            return;
        if (ks->long_fired || dur >= g_long_ms)
            return;

        if (is_multiclick(ks->name)) {
            // Defer until the click window expires, then fire 1x/2x/3x.
            ks->clicks++;
            ks->last_release_ms = now;
            if (ks->clicks > 3) ks->clicks = 3;
        } else {
            do_action(ks->name, 0);
        }
    }
}

static void handle_timers(long long now) {
    for (int c = 0; c <= KEY_MAX; c++) {
        struct key_state *ks = &g_keys[c];
        long long held;

        if (!ks->mapped) continue;

        if (!ks->active) {
            if (is_multiclick(ks->name) && ks->clicks > 0 &&
                now - ks->last_release_ms >= g_multiclick_ms) {
                int count = ks->clicks;
                char act[64];
                ks->clicks = 0;
                if (count == 1) {
                    do_action(ks->name, 0);
                } else {
                    snprintf(act, sizeof(act), "%s_%dx", ks->name, count >= 3 ? 3 : 2);
                    logmsg("multi-click: %s x%d", ks->name, count);
                    do_action(act, 0);
                }
            }
            continue;
        }

        held = now - ks->press_ms;

        if (!strcmp(ks->name, "volume_up") || !strcmp(ks->name, "volume_down")) {
            if (held >= g_repeat_delay_ms && now - ks->last_repeat_ms >= g_repeat_ms) {
                ks->last_repeat_ms = now;
                do_action(ks->name, 0);
            }
            continue;
        }

        if (!ks->long_fired && held >= g_long_ms) {
            const char *cmd = config_cmd(ks->name, 1);
            char hook[MAX_PATH];
            if (cmd || hook_exists(ks->name, 1, hook, sizeof(hook))) {
                ks->long_fired = 1;
                do_action(ks->name, 1);
            }
        }
    }
}

static void on_signal(int sig) {
    (void)sig;
    g_running = 0;
}

static void daemonize(void) {
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); exit(1); }
    if (pid > 0) _exit(0);
    if (setsid() < 0) { perror("setsid"); exit(1); }
    pid = fork();
    if (pid < 0) { perror("fork"); exit(1); }
    if (pid > 0) _exit(0);
    chdir("/");
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        if (devnull > STDERR_FILENO) close(devnull);
    }
    g_daemonize = 1;
}

int main(int argc, char **argv) {
    char config[MAX_PATH] = "/data/opt/etc/buttonsd.conf";
    int opt;

    while ((opt = getopt(argc, argv, "dfc:")) != -1) {
        switch (opt) {
        case 'd': g_daemonize = 1; break;
        case 'f': g_daemonize = 0; break;
        case 'c': snprintf(config, sizeof(config), "%s", optarg); break;
        default:
            fprintf(stderr, "usage: %s [-d] [-f] [-c config]\n", argv[0]);
            return 2;
        }
    }

    load_config(config);

    mkdir("/data/opt/var", 0755);
    mkdir("/data/opt/var/log", 0755);
    mkdir("/data/opt/var/run", 0755);

    g_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (g_log_fd < 0 && !g_daemonize) {
        fprintf(stderr, "cannot open log %s: %s\n", g_log_path, strerror(errno));
    }

    if (g_daemonize) daemonize();

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    logmsg("buttonsd starting (devices=%s grab=%d suspend_with_maind=%d long=%dms repeat=%d/%dms)",
           g_devices_cfg, g_grab, g_suspend_with_maind, g_long_ms, g_repeat_delay_ms, g_repeat_ms);

    open_devices();
    if (g_ndev == 0) logmsg("no input devices opened yet; will retry");

    if (g_pid_path[0]) {
        FILE *pf = fopen(g_pid_path, "w");
        if (pf) { fprintf(pf, "%d\n", (int)getpid()); fclose(pf); }
    }

    int rescan_at = 0;
    int maind_check_at = 0;
    long long start_ms = now_ms();
    long long led_init_at = start_ms + 6000;
    if (g_suspend_with_maind && maind_platformd_running()) {
        g_suspended = 1;
        logmsg("maind --platformd is running: actions suspended");
    }
    while (g_running) {
        struct pollfd pfd[MAX_DEV];
        int n = 0;
        int timeout = g_ndev ? 50 : 1000;

        for (int i = 0; i < g_ndev; i++) {
            if (g_devs[i].fd < 0) continue;
            pfd[n].fd = g_devs[i].fd;
            pfd[n].events = POLLIN;
            pfd[n].revents = 0;
            n++;
        }

        int r = poll(pfd, n, timeout);
        long long now = now_ms();
        if (r < 0 && errno != EINTR) {
            logmsg("poll: %s", strerror(errno));
            usleep(200000);
        }
        if (r > 0) {
            for (int i = 0; i < n; i++) {
                if (!(pfd[i].revents & (POLLIN | POLLERR | POLLHUP))) continue;
                struct input_event ev;
                while (read(pfd[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
                    if (ev.type == EV_KEY && !g_suspended)
                        handle_key(ev.code, ev.value, now_ms());
                }
                if (pfd[i].revents & (POLLERR | POLLHUP)) {
                    logmsg("device %s hung up", g_devs[i].path);
                    close(g_devs[i].fd);
                    g_devs[i].fd = -1;
                }
            }
        }
        if (!g_suspended) handle_timers(now);
        if (now >= maind_check_at) {
            if (g_suspend_with_maind) {
                int running = maind_platformd_running();
                if (running && !g_suspended) {
                    g_suspended = 1;
                    g_led_ready = 0;
                    reset_key_states();
                    logmsg("maind --platformd detected: actions suspended");
                } else if (!running && g_suspended) {
                    g_suspended = 0;
                    logmsg("maind --platformd gone: actions resumed");
                }
            }
            maind_check_at = now + 3000;
        }
        if (g_led_init && !g_suspended && !g_led_ready && now >= led_init_at) {
            run_shell("/data/opt/bin/buttons_led.sh init");
            g_led_ready = 1;
            logmsg("LEDs initialized for bunker mode");
        }
        if (now >= rescan_at) {
            int before = g_ndev;
            open_devices();
            if (g_ndev != before) logmsg("device count now %d", g_ndev);
            rescan_at = now + 5000;
        }
    }

    logmsg("buttonsd stopping");
    for (int i = 0; i < g_ndev; i++) {
        if (g_devs[i].fd >= 0) {
            if (g_grab) ioctl(g_devs[i].fd, EVIOCGRAB, 0);
            close(g_devs[i].fd);
        }
    }
    if (g_pid_path[0]) unlink(g_pid_path);
    if (g_log_fd >= 0) close(g_log_fd);
    return 0;
}
