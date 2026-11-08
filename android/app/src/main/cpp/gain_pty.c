#include <jni.h>
#include <android/log.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <time.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif

extern char **environ;

#define GAIN_MAX_PTY_SESSIONS 8

typedef struct {
    int master_fd;
    pid_t child_pid;
    uint32_t generation;
} GainPtySession;

static GainPtySession g_sessions[GAIN_MAX_PTY_SESSIONS];
static pthread_mutex_t g_sessions_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t g_sessions_once = PTHREAD_ONCE_INIT;
static char g_files_dir[PATH_MAX] = "/data/data/com.example.giant_agent/files/gain_terminal";
/* select_shell() returns one of these paths to nativeStartPty; keep storage
 * alive until fork rather than returning a pointer into a local stack array. */
static char g_shell_candidates[5][PATH_MAX];

static void init_sessions_once(void) {
    for (int i = 0; i < GAIN_MAX_PTY_SESSIONS; ++i) {
        g_sessions[i].master_fd = -1;
        g_sessions[i].child_pid = -1;
        g_sessions[i].generation = 0;
    }
}

static void ensure_sessions_init(void) {
    (void)pthread_once(&g_sessions_once, init_sessions_once);
}

static void path_join(char *out, size_t capacity, const char *suffix) {
    if (out == NULL || capacity == 0) return;
    const char *base = g_files_dir[0] ? g_files_dir : "/data/data/com.example.giant_agent/files/gain_terminal";
    const char *tail = suffix ? suffix : "";
    (void)snprintf(out, capacity, "%s/%s", base, tail);
}

static int is_userland_path(const char *path) {
    if (path == NULL) return 0;
    char prefix[PATH_MAX];
    path_join(prefix, sizeof(prefix), "usr/");
    if (strncmp(path, prefix, strlen(prefix)) == 0) return 1;
    return strncmp(path, "/data/data/com.example.giant_agent/files/gain_terminal/usr/",
                   strlen("/data/data/com.example.giant_agent/files/gain_terminal/usr/")) == 0;
}

static int is_bash_real_path(const char *path) {
    if (path == NULL) return 0;
    char expected[PATH_MAX];
    path_join(expected, sizeof(expected), "usr/bin/bash.real");
    return strcmp(path, expected) == 0 ||
           strcmp(path, "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/bash.real") == 0;
}

static GainPtySession *get_session(jint handle) {
    ensure_sessions_init();
    if (handle <= 0) return NULL;
    const uint32_t raw = (uint32_t)handle;
    const uint32_t slot_code = raw & 0xffU;
    const uint32_t generation = raw >> 8;
    if (slot_code == 0 || slot_code > GAIN_MAX_PTY_SESSIONS || generation == 0) return NULL;
    GainPtySession *session = &g_sessions[slot_code - 1U];
    if (session->master_fd < 0 || session->generation != generation) return NULL;
    return session;
}

static jint make_session_handle(int slot, uint32_t generation) {
    return (jint)((generation << 8) | (uint32_t)(slot + 1));
}

static void configure_terminal(int fd) {
    struct termios settings;
    if (tcgetattr(fd, &settings) != 0) return;

    // Do not rely on the PTY driver's inherited defaults: some Android builds
    // expose a slave with ECHO/ICANON disabled. In that state characters appear
    // to vanish when Enter submits a line, and shells can receive CR without
    // the expected line discipline processing.
    settings.c_iflag |= (ICRNL | IXON);
#ifdef IMAXBEL
    settings.c_iflag |= IMAXBEL;
#endif
    settings.c_oflag |= (OPOST | ONLCR);
    settings.c_lflag |= (ISIG | ICANON | ECHO | ECHOE | ECHOK);
#ifdef ECHOCTL
    settings.c_lflag |= ECHOCTL;
#endif
#ifdef IUTF8
    settings.c_iflag |= IUTF8;
#endif
    settings.c_cc[VERASE] = 0x7f;
    settings.c_cc[VKILL] = 0x15;
    settings.c_cc[VEOF] = 0x04;
    settings.c_cc[VINTR] = 0x03;
    settings.c_cc[VQUIT] = 0x1c;
    settings.c_cc[VSUSP] = 0x1a;
    (void)tcsetattr(fd, TCSANOW, &settings);
}

static int set_winsize(int fd, int rows, int cols) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    ws.ws_col = (unsigned short)(cols > 0 ? cols : 80);
    return ioctl(fd, TIOCSWINSZ, &ws);
}

static void mkdir_p(const char *path, mode_t mode) {
    char buffer[512];
    size_t length = strlen(path);
    if (length == 0 || length >= sizeof(buffer)) return;
    memcpy(buffer, path, length + 1);
    for (char *p = buffer + 1; *p; ++p) {
        if (*p != '/') continue;
        *p = '\0';
        (void)mkdir(buffer, mode);
        *p = '/';
    }
    (void)mkdir(buffer, mode);
}

static void prepare_environment(void) {
    char home[PATH_MAX], prefix[PATH_MAX], tmp[PATH_MAX], proot_tmp[PATH_MAX];
    char bin[PATH_MAX], sbin[PATH_MAX], lib[PATH_MAX], lib64[PATH_MAX], libexec[PATH_MAX];
    char bashrc[PATH_MAX], terminfo[PATH_MAX], lib_terminfo[PATH_MAX], terminfo_dirs[PATH_MAX], cert[PATH_MAX];
    char path[PATH_MAX * 2], library_path[PATH_MAX * 3];
    path_join(home, sizeof(home), "home");
    path_join(prefix, sizeof(prefix), "usr");
    path_join(tmp, sizeof(tmp), "tmp");
    path_join(proot_tmp, sizeof(proot_tmp), "tmp/proot");
    path_join(bin, sizeof(bin), "usr/bin");
    path_join(sbin, sizeof(sbin), "usr/sbin");
    path_join(lib, sizeof(lib), "usr/lib");
    path_join(lib64, sizeof(lib64), "usr/lib64");
    path_join(libexec, sizeof(libexec), "usr/libexec");
    path_join(bashrc, sizeof(bashrc), "usr/etc/gain-bashrc");
    path_join(terminfo, sizeof(terminfo), "usr/share/terminfo");
    path_join(lib_terminfo, sizeof(lib_terminfo), "usr/lib/terminfo");
    (void)snprintf(path, sizeof(path), "%s:%s:/system/bin:/system/xbin:/vendor/bin", bin, sbin);
    (void)snprintf(library_path, sizeof(library_path), "%s:%s:%s", lib, lib64, libexec);
    (void)snprintf(terminfo_dirs, sizeof(terminfo_dirs), "%s:%s:/system/usr/share/terminfo",
                   terminfo, lib_terminfo);

    const char *directories[] = {
        "home", "tmp", "tmp/proot", "gain/tmp", "etc", "home/storage",
        "usr", "usr/bin", "usr/sbin", "usr/etc", "usr/include", "usr/lib",
        "usr/libexec", "usr/share", "usr/tmp", "usr/var", "usr/var/lib",
        "usr/var/lib/gain-pkg", "usr/var/cache", "usr/var/log"
    };
    for (size_t i = 0; i < sizeof(directories) / sizeof(directories[0]); ++i) {
        char directory[PATH_MAX];
        path_join(directory, sizeof(directory), directories[i]);
        mkdir_p(directory, 0700);
    }
    setenv("HOME", home, 1);
    setenv("PREFIX", prefix, 1);
    setenv("PATH", path, 1);
    setenv("TMPDIR", tmp, 1);
    setenv("PROOT_TMP_DIR", proot_tmp, 1);
    setenv("PROOT_NO_SECCOMP", "1", 1);
    setenv("LD_LIBRARY_PATH", library_path, 1);
    setenv("BASH_ENV", bashrc, 1);
    setenv("TERMINFO", terminfo, 1);
    setenv("TERMINFO_DIRS", terminfo_dirs, 1);
    path_join(cert, sizeof(cert), "usr/etc/tls/cert.pem");
    if (access(cert, R_OK) == 0) {
        setenv("SSL_CERT_FILE", cert, 1);
        setenv("CURL_CA_BUNDLE", cert, 1);
    } else {
        unsetenv("SSL_CERT_FILE");
        unsetenv("CURL_CA_BUNDLE");
    }
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);
    setenv("PS1", "$ ", 1);
    setenv("LANG", "C.UTF-8", 1);
    setenv("LC_ALL", "C.UTF-8", 1);
    char shell[PATH_MAX];
    path_join(shell, sizeof(shell), "usr/bin/bash");
    setenv("SHELL", shell, 1);
    setenv("GAIN_TERMINAL", "1", 1);
}

static int is_allowed_shell(const char *shell) {
    if (shell == NULL || shell[0] == '\0') return 0;
    if (strncmp(shell, "kali:", 5) == 0 || strcmp(shell, "/system/bin/sh") == 0) return 1;
    char candidate[PATH_MAX];
    const char *allowed_names[] = {"bash", "bash.real", "zsh", "fish", "ash", NULL};
    for (int i = 0; allowed_names[i] != NULL; ++i) {
        (void)snprintf(candidate, sizeof(candidate), "%s/usr/bin/%s", g_files_dir, allowed_names[i]);
        if (strcmp(shell, candidate) == 0) return 1;
        (void)snprintf(candidate, sizeof(candidate), "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/%s", allowed_names[i]);
        if (strcmp(shell, candidate) == 0) return 1;
    }
    return 0;
}

static const char *select_shell(const char *configured_shell) {
    if (configured_shell != NULL && strncmp(configured_shell, "kali:", 5) == 0) return configured_shell;
    /* access(X_OK) can reject private-prefix ELF files even when Android's
     * dynamic linker can load them. Use F_OK for candidate discovery. */
    if (is_allowed_shell(configured_shell) && access(configured_shell, F_OK) == 0) {
        return configured_shell;
    }

    const char *names[] = {"bash.real", "bash", "zsh", "fish", "ash"};
    for (int i = 0; i < 5; ++i) {
        (void)snprintf(g_shell_candidates[i], sizeof(g_shell_candidates[i]),
                       "%s/usr/bin/%s", g_files_dir, names[i]);
        if (access(g_shell_candidates[i], F_OK) == 0) return g_shell_candidates[i];
    }
    static const char *fallbacks[] = {
        "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/bash.real",
        "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/bash",
        "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/zsh",
        "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/fish",
        "/data/data/com.example.giant_agent/files/gain_terminal/usr/bin/ash",
        "/system/bin/sh",
        NULL
    };
    for (int i = 0; fallbacks[i] != NULL; ++i) {
        if (access(fallbacks[i], F_OK) == 0) return fallbacks[i];
    }
    return NULL;
}

/*
 * Explicit root mode: selected only by the "root:" PTY prefix. The shell path
 * must pass the native allowlist before reaching this function. SELinux remains
 * enabled and root launch failures never fall back to an unprivileged shell.
 */
static void exec_root_shell(const char *shell_path) {
    if (shell_path == NULL || !is_allowed_shell(shell_path) ||
        strncmp(shell_path, "kali:", 5) == 0) {
        __android_log_print(ANDROID_LOG_WARN, "GainPTY", "Root shell rejected by native allowlist");
        _exit(126);
    }

    char real_path[PATH_MAX];
    const char *selected = shell_path;
    size_t length = strlen(shell_path);
    if (length < sizeof(real_path) && length >= 5 &&
        strcmp(shell_path + length - 5, "/bash") == 0) {
        (void)snprintf(real_path, sizeof(real_path), "%s.real", shell_path);
        if (access(real_path, F_OK) == 0) selected = real_path;
    }

    char bashrc[PATH_MAX], command[PATH_MAX * 3];
    path_join(bashrc, sizeof(bashrc), "usr/etc/gain-bashrc");
    if (is_userland_path(selected)) {
        if (is_bash_real_path(selected) && access(bashrc, R_OK) == 0) {
            (void)snprintf(command, sizeof(command),
                "export LD_LIBRARY_PATH='%s/usr/lib:%s/usr/lib64:%s/usr/libexec'; exec /system/bin/linker64 '%s' --init-file '%s' -i",
                g_files_dir, g_files_dir, g_files_dir, selected, bashrc);
        } else {
            (void)snprintf(command, sizeof(command),
                "export LD_LIBRARY_PATH='%s/usr/lib:%s/usr/lib64:%s/usr/libexec'; exec /system/bin/linker64 '%s' -i",
                g_files_dir, g_files_dir, g_files_dir, selected);
        }
    } else {
        (void)snprintf(command, sizeof(command), "exec '%s' -i", selected);
    }

    execlp("su", "su", "-c", command, (char *)NULL);
    __android_log_print(ANDROID_LOG_WARN, "GainPTY",
                        "Root shell launch failed (errno=%d); check Magisk authorization", errno);
    _exit(127);
}

static void exec_kali_proot(const char *proot, const char *rootfs) {
    /*
     * The bundled PRoot ELF is stored under app-private data, where direct
     * execve can be denied on some Android builds. Launch it through Android's
     * linker, preserving the PREFIX LD_LIBRARY_PATH prepared before fork().
     */
    char lib_bind[1024];
    char usr_lib_bind[1024];
    const int lib_len = snprintf(lib_bind, sizeof(lib_bind),
        "%s/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu", rootfs);
    const int usr_lib_len = snprintf(usr_lib_bind, sizeof(usr_lib_bind),
        "%s/usr/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu", rootfs);
    if (lib_len <= 0 || (size_t)lib_len >= sizeof(lib_bind) ||
        usr_lib_len <= 0 || (size_t)usr_lib_len >= sizeof(usr_lib_bind)) {
        _exit(126);
    }

    /* PRoot temp and seccomp variables are prepared in the parent before fork(). */

    char home_bind[PATH_MAX * 2];
    (void)snprintf(home_bind, sizeof(home_bind), "%s/home:/root", g_files_dir);
    execl("/system/bin/linker64", "linker64", proot,
          "--link2symlink", "-0", "-r", rootfs,
          "-b", "/dev", "-b", "/proc", "-b", "/sys",
          "-b", "/storage/emulated/0",
          "-b", home_bind,
          "-b", lib_bind,
          "-b", usr_lib_bind,
          "-w", "/root",
          "/usr/bin/env", "-i",
          "HOME=/root",
          "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
          "TERM=xterm-256color", "LANG=C.UTF-8", "LC_ALL=C.UTF-8",
          "SHELL=/bin/bash", "GAIN_KALI=1",
          "/bin/bash", "--login", (char *)NULL);
    __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
        "Unable to launch PRoot via linker64: errno=%d (%s)", errno, strerror(errno));
    _exit(127);
}

/*
 * Launch a Termux ELF through Android's dynamic linker when direct exec is
 * rejected for a private app-data path. This is a supported loader path, not
 * an attempt to bypass SELinux. It still requires valid ELF dependencies and
 * device policy that permits the linker to load the binary.
 */
static void exec_selected_shell(const char *shell_path) {
    if (shell_path == NULL || shell_path[0] == '\0') _exit(127);

    char real_path[PATH_MAX];
    const char *selected = shell_path;
    size_t length = strlen(shell_path);
    if (length < sizeof(real_path) && length >= 5 &&
        strcmp(shell_path + length - 5, "/bash") == 0) {
        (void)snprintf(real_path, sizeof(real_path), "%s.real", shell_path);
        if (access(real_path, F_OK) == 0) selected = real_path;
    }

    if (is_bash_real_path(selected)) {
        char bashrc[PATH_MAX];
        path_join(bashrc, sizeof(bashrc), "usr/etc/gain-bashrc");
        if (access(bashrc, R_OK) == 0) {
            execl("/system/bin/linker64", "linker64", selected,
                  "--init-file", bashrc, "-i", (char *)NULL);
        } else {
            execl("/system/bin/linker64", "linker64", selected, "-i", (char *)NULL);
        }
        __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
                            "linker64 exec for Bash failed (errno=%d: %s); falling back to Android sh",
                            errno, strerror(errno));
        execl("/system/bin/sh", "sh", "-i", (char *)NULL);
        _exit(127);
    }

    if (strcmp(selected, "/system/bin/sh") == 0) {
        execl("/system/bin/sh", "sh", "-i", (char *)NULL);
        __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
                            "Android system shell exec failed (errno=%d: %s)",
                            errno, strerror(errno));
        _exit(127);
    }

    // Other allowlisted Userland shells are ELF files too; launch through the
    // Android linker because direct exec may be denied for app-private paths.
    if (is_userland_path(selected)) {
        execl("/system/bin/linker64", "linker64", selected, "-i", (char *)NULL);
        __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
                            "linker64 exec for Userland shell %s failed (errno=%d: %s)",
                            selected, errno, strerror(errno));
    } else {
        execl(selected, selected, "-i", (char *)NULL);
        __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
                            "exec for shell %s failed (errno=%d: %s)",
                            selected, errno, strerror(errno));
    }

    execl("/system/bin/sh", "sh", "-i", (char *)NULL);
    _exit(127);
}

JNIEXPORT void JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeSetPaths(JNIEnv *env, jobject thiz, jstring files_dir) {
    (void)thiz;
    if (files_dir == NULL) return;
    const char *path = (*env)->GetStringUTFChars(env, files_dir, NULL);
    if (path == NULL) return;
    size_t length = strlen(path);
    if (length > 0 && length < sizeof(g_files_dir) &&
        path[0] == '/' && strstr(path, "/../") == NULL) {
        pthread_mutex_lock(&g_sessions_lock);
        memcpy(g_files_dir, path, length + 1);
        while (length > 1 && g_files_dir[length - 1] == '/') {
            g_files_dir[--length] = '\0';
        }
        pthread_mutex_unlock(&g_sessions_lock);
    }
    (*env)->ReleaseStringUTFChars(env, files_dir, path);
}

JNIEXPORT jboolean JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativePtyAvailable(JNIEnv *env, jobject thiz) {
    (void)env; (void)thiz;
    int fd = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (fd < 0) return JNI_FALSE;
    close(fd);
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeStartPty(JNIEnv *env, jobject thiz, jint rows, jint cols, jstring shell_arg) {
    (void)thiz;
    char configured_shell[512] = {0};
    char kali_proot[512] = {0};
    char kali_rootfs[512] = {0};
    char kali_loader[512] = {0};
    int kali_mode = 0;
    if (shell_arg != NULL) {
        const char *raw = (*env)->GetStringUTFChars(env, shell_arg, NULL);
        if (raw != NULL) {
            size_t length = strlen(raw);
            if (length < sizeof(configured_shell)) {
                memcpy(configured_shell, raw, length);
                configured_shell[length] = '\0';
            }
            (*env)->ReleaseStringUTFChars(env, shell_arg, raw);
        }
    }

    int root_mode = 0;
    if (strncmp(configured_shell, "root:", 5) == 0) {
        root_mode = 1;
        memmove(configured_shell, configured_shell + 5,
                strlen(configured_shell + 5) + 1);
    }

    if (root_mode && (!is_allowed_shell(configured_shell) ||
        strncmp(configured_shell, "kali:", 5) == 0 ||
        access(configured_shell, F_OK) != 0)) {
        return 0;
    }

    if (strncmp(configured_shell, "kali:", 5) == 0) {
        kali_mode = 1;
        const char *spec = configured_shell + 5;
        const char *sep1 = strchr(spec, '|');
        const char *sep2 = sep1 ? strchr(sep1 + 1, '|') : NULL;
        if (!sep1 || !sep2) return 0;
        size_t pLen = (size_t)(sep1 - spec);
        size_t rLen = (size_t)(sep2 - sep1 - 1);
        size_t lLen = strlen(sep2 + 1);
        if (pLen == 0 || pLen >= sizeof(kali_proot) ||
            rLen == 0 || rLen >= sizeof(kali_rootfs) ||
            lLen == 0 || lLen >= sizeof(kali_loader)) return 0;
        memcpy(kali_proot, spec, pLen); kali_proot[pLen] = '\0';
        memcpy(kali_rootfs, sep1 + 1, rLen); kali_rootfs[rLen] = '\0';
        memcpy(kali_loader, sep2 + 1, lLen); kali_loader[lLen] = '\0';
        if (access(kali_proot, R_OK) != 0 ||
            access(kali_rootfs, R_OK | X_OK) != 0 ||
            access(kali_loader, R_OK) != 0) return 0;
    }

    pthread_mutex_lock(&g_sessions_lock);
    ensure_sessions_init();

    int slot = -1;
    for (int i = 0; i < GAIN_MAX_PTY_SESSIONS; ++i) {
        if (g_sessions[i].master_fd < 0) {
            slot = i;
            break;
        }
    }
    if (slot < 0) {
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    uint32_t generation = (g_sessions[slot].generation + 1U) & 0x007fffffU;
    if (generation == 0U) generation = 1U;
    g_sessions[slot].generation = generation;

    int master = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_CLOEXEC | O_NONBLOCK);
    if (master < 0) {
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    char slave_name[128];
    if (ptsname_r(master, slave_name, sizeof(slave_name)) != 0) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    // Prepare the base process environment before fork(). Android/Flutter is
    // heavily multi-threaded; calling malloc-backed functions such as
    // setenv()/mkdir() in the post-fork child can deadlock or crash.
    prepare_environment();
    const char *selected_shell = root_mode
        ? configured_shell
        : select_shell(configured_shell[0] == '\0' ? NULL : configured_shell);
    if (selected_shell == NULL) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }
    setenv("SHELL", selected_shell, 1);
    if (root_mode) {
        setenv("GAIN_SHELL_MODE", "root-opt-in", 1);
    }
    if (kali_mode) {
        setenv("PROOT_LOADER", kali_loader, 1);
        char proot_tmp[PATH_MAX], tmp[PATH_MAX];
        path_join(proot_tmp, sizeof(proot_tmp), "tmp/proot");
        path_join(tmp, sizeof(tmp), "tmp");
        setenv("PROOT_TMP_DIR", proot_tmp, 1);
        setenv("TMPDIR", tmp, 1);
        setenv("PROOT_NO_SECCOMP", "1", 1);
        mkdir_p(proot_tmp, 0700);
        setenv("GAIN_SHELL_MODE", "kali-proot", 1);
    } else if (strcmp(selected_shell, "/system/bin/sh") == 0) {
        // Android host-shell mode is intentionally independent of the broken
        // Userland prefix: keep PATH limited to Android's shipped commands.
        char home[PATH_MAX], tmp[PATH_MAX];
        path_join(home, sizeof(home), "home");
        path_join(tmp, sizeof(tmp), "tmp");
        setenv("HOME", home, 1);
        setenv("TMPDIR", tmp, 1);
        setenv("PATH", "/system/bin:/system/xbin:/vendor/bin", 1);
        setenv("LD_LIBRARY_PATH", "", 1);
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        setenv("SHELL", "/system/bin/sh", 1);
        // Keep a conventional, stable Android shell prompt with no path prefix.
        setenv("PS1", "$ ", 1);
        setenv("GAIN_SHELL_MODE", "android-system", 1);
    } else {
        setenv("GAIN_SHELL_MODE", "zion-userland", 1);
    }

    // Synchronize PTY startup with the child opening the slave. Without this
    // handshake, the parent reader can race the child's open(slave_name), see
    // EIO on the master before the slave exists, and incorrectly close a healthy
    // session immediately after the UI reports it connected.
    int startup_pipe[2];
    if (pipe(startup_pipe) != 0) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }
    (void)fcntl(startup_pipe[0], F_SETFD, FD_CLOEXEC);
    (void)fcntl(startup_pipe[1], F_SETFD, FD_CLOEXEC);

    pid_t pid = fork();
    if (pid < 0) {
        close(startup_pipe[0]);
        close(startup_pipe[1]);
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    if (pid == 0) {
        close(startup_pipe[0]);
        // After fork(), never unlock g_sessions_lock here: if another thread
        // held it at fork time, the inherited pthread mutex is not safely
        // unlockable in the child and can deadlock the PTY process.
        // The child owns the slave side only. Keeping the PTY master open in
        // the child can prevent EOF/EIO from reaching the Flutter reader and
        // can leave a stopped shell session looking alive.
        close(master);
        int slave = open(slave_name, O_RDWR | O_NOCTTY);
        if (slave < 0) {
            close(startup_pipe[1]);
            _exit(127);
        }
        const unsigned char ready = 1;
        (void)write(startup_pipe[1], &ready, sizeof(ready));
        close(startup_pipe[1]);
        configure_terminal(slave);

        prctl(PR_SET_PDEATHSIG, SIGHUP);
        setsid();
#ifdef TIOCSCTTY
        ioctl(slave, TIOCSCTTY, 0);
#endif
        set_winsize(slave, rows, cols);
        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) close(slave);

        char home[PATH_MAX];
        path_join(home, sizeof(home), "home");
        if (chdir(home) != 0) _exit(126);
        if (kali_mode) exec_kali_proot(kali_proot, kali_rootfs);
        if (root_mode) exec_root_shell(selected_shell);
        exec_selected_shell(selected_shell);
    }

    close(startup_pipe[1]);
    struct pollfd startup_wait = {startup_pipe[0], POLLIN | POLLHUP, 0};
    int startup_ready;
    do {
        startup_ready = poll(&startup_wait, 1, 1500);
    } while (startup_ready < 0 && errno == EINTR);
    unsigned char ready = 0;
    ssize_t ready_bytes = startup_ready > 0
        ? read(startup_pipe[0], &ready, sizeof(ready))
        : -1;
    close(startup_pipe[0]);
    if (ready_bytes != (ssize_t)sizeof(ready) || ready != 1) {
        __android_log_print(ANDROID_LOG_ERROR, "GainPTY",
            "PTY child did not open its slave within 1500ms (poll=%d errno=%d); refusing a dead session",
            startup_ready, errno);
        close(master);
        (void)kill(pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    g_sessions[slot].master_fd = master;
    g_sessions[slot].child_pid = pid;
    const jint handle = make_session_handle(slot, generation);
    pthread_mutex_unlock(&g_sessions_lock);
    return handle;
}

static void *gain_reap_child_thread(void *argument) {
    pid_t pid = *((pid_t *)argument);
    free(argument);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    return NULL;
}

static void reap_child_after_eof(pid_t pid) {
    if (pid <= 0) return;
    for (int attempt = 0; attempt < 10; ++attempt) {
        int status = 0;
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid || (result < 0 && errno == ECHILD)) return;
        if (result < 0 && errno != EINTR) return;
        usleep(10000);
    }
    pid_t *child = (pid_t *)malloc(sizeof(pid_t));
    if (child == NULL) {
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        return;
    }
    *child = pid;
    pthread_t thread;
    if (pthread_create(&thread, NULL, gain_reap_child_thread, child) == 0) {
        (void)pthread_detach(thread);
    } else {
        free(child);
        int status = 0;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeReadPty(JNIEnv *env, jobject thiz, jint handle) {
    (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (!session) {
        pthread_mutex_unlock(&g_sessions_lock);
        return NULL;
    }

    unsigned char buffer[8192];
    ssize_t n = read(session->master_fd, buffer, sizeof(buffer));
    if (n > 0) {
        jbyteArray out = (*env)->NewByteArray(env, (jsize)n);
        if (!out) {
            pthread_mutex_unlock(&g_sessions_lock);
            return NULL;
        }
        (*env)->SetByteArrayRegion(env, out, 0, (jsize)n, (const jbyte *)buffer);
        pthread_mutex_unlock(&g_sessions_lock);
        return out;
    }
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
        pthread_mutex_unlock(&g_sessions_lock);
        return (*env)->NewByteArray(env, 0);
    }

    // Invalidate the generation-tagged handle before reaping. Retrying outside
    // the session lock prevents a slow child exit from blocking other PTYs.
    pid_t pid = session->child_pid;
    int fd = session->master_fd;
    session->master_fd = -1;
    session->child_pid = -1;
    if (fd >= 0) close(fd);
    pthread_mutex_unlock(&g_sessions_lock);
    reap_child_after_eof(pid);
    return NULL;
}

JNIEXPORT jint JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeWritePty(JNIEnv *env, jobject thiz, jint handle, jbyteArray data) {
    (void)thiz;
    if (data == NULL) return -1;

    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (!session) {
        pthread_mutex_unlock(&g_sessions_lock);
        return -1;
    }
    int fd = dup(session->master_fd);
    pthread_mutex_unlock(&g_sessions_lock);
    if (fd < 0) return -1;

    jsize len = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    if (!bytes) {
        close(fd);
        return -1;
    }

    struct timespec started;
    (void)clock_gettime(CLOCK_MONOTONIC, &started);
    jsize written = 0;
    while (written < len) {
        struct timespec now;
        (void)clock_gettime(CLOCK_MONOTONIC, &now);
        int64_t elapsed_ms = (int64_t)(now.tv_sec - started.tv_sec) * 1000LL +
            (int64_t)(now.tv_nsec - started.tv_nsec) / 1000000LL;
        int remaining_ms = 5000 - (int)elapsed_ms;
        if (remaining_ms <= 0) break;

        struct pollfd pfd = {fd, POLLOUT, 0};
        int ready = poll(&pfd, 1, remaining_ms);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0 || (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) break;
        ssize_t n = write(fd, bytes + written, (size_t)(len - written));
        if (n > 0) written += (jsize)n;
        else if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        else break;
    }

    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    close(fd);
    return written;
}

JNIEXPORT jboolean JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeResizePty(JNIEnv *env, jobject thiz, jint handle, jint rows, jint cols) {
    (void)env; (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (!session) {
        pthread_mutex_unlock(&g_sessions_lock);
        return JNI_FALSE;
    }
    int ok = set_winsize(session->master_fd, rows, cols) == 0;
    pthread_mutex_unlock(&g_sessions_lock);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeStopPty(JNIEnv *env, jobject thiz, jint handle) {
    (void)env; (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (!session) {
        pthread_mutex_unlock(&g_sessions_lock);
        return;
    }

    int fd = session->master_fd;
    pid_t pid = session->child_pid;
    session->master_fd = -1;
    session->child_pid = -1;
    if (fd >= 0) close(fd);
    pthread_mutex_unlock(&g_sessions_lock);

    if (pid > 0) {
        kill(-pid, SIGHUP);
        kill(-pid, SIGTERM);
        int reaped = 0;
        for (int i = 0; i < 50; ++i) {
            pid_t result = waitpid(pid, NULL, WNOHANG);
            if (result == pid || (result < 0 && errno == ECHILD)) {
                reaped = 1;
                break;
            }
            usleep(10000);
        }
        if (!reaped) {
            kill(-pid, SIGKILL);
            kill(pid, SIGKILL);
            waitpid(pid, NULL, 0);
        }
    }
}
