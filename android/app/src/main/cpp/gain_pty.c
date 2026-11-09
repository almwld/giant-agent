#include <jni.h>
#include <android/log.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define GAIN_MAX_PTY_SESSIONS 8
#define GAIN_TAG "GainPTY"

typedef struct {
    int master_fd;
    pid_t child_pid;
    uint32_t generation;
} GainPtySession;

static GainPtySession g_sessions[GAIN_MAX_PTY_SESSIONS];
static pthread_mutex_t g_sessions_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t g_sessions_once = PTHREAD_ONCE_INIT;

static void init_sessions(void) {
    for (int i = 0; i < GAIN_MAX_PTY_SESSIONS; ++i) {
        g_sessions[i].master_fd = -1;
        g_sessions[i].child_pid = -1;
        g_sessions[i].generation = 0;
    }
}

static void ensure_sessions(void) {
    (void)pthread_once(&g_sessions_once, init_sessions);
}

static GainPtySession *get_session(jint handle) {
    ensure_sessions();
    if (handle <= 0) return NULL;
    const uint32_t raw = (uint32_t)handle;
    const uint32_t slot_code = raw & 0xffU;
    const uint32_t generation = raw >> 8;
    if (slot_code == 0 || slot_code > GAIN_MAX_PTY_SESSIONS || generation == 0) return NULL;
    GainPtySession *session = &g_sessions[slot_code - 1U];
    if (session->master_fd < 0 || session->generation != generation) return NULL;
    return session;
}

static jint make_handle(int slot, uint32_t generation) {
    return (jint)((generation << 8) | (uint32_t)(slot + 1));
}

static void configure_terminal(int fd) {
    struct termios settings;
    if (tcgetattr(fd, &settings) != 0) return;
    settings.c_iflag |= (ICRNL | IXON);
    settings.c_oflag |= (OPOST | ONLCR);
    settings.c_lflag |= (ISIG | ICANON | ECHO | ECHOE | ECHOK);
#ifdef IUTF8
    settings.c_iflag |= IUTF8;
#endif
#ifdef ECHOCTL
    settings.c_lflag |= ECHOCTL;
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

static void *reap_child_thread(void *argument) {
    const pid_t pid = *((pid_t *)argument);
    free(argument);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    return NULL;
}

static void reap_child(pid_t pid) {
    if (pid <= 0) return;
    int status = 0;
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result == pid || (result < 0 && errno == ECHILD)) return;
    pid_t *child = (pid_t *)malloc(sizeof(pid_t));
    if (child == NULL) {
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        return;
    }
    *child = pid;
    pthread_t thread;
    if (pthread_create(&thread, NULL, reap_child_thread, child) == 0) {
        (void)pthread_detach(thread);
    } else {
        free(child);
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
}

JNIEXPORT jboolean JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativePtyAvailable(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    int fd = open("/dev/ptmx", O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (fd < 0) return JNI_FALSE;
    close(fd);
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeStartPty(
    JNIEnv *env, jobject thiz, jint rows, jint cols, jstring shell_arg) {
    (void)thiz;
    if (shell_arg != NULL) {
        const char *requested = (*env)->GetStringUTFChars(env, shell_arg, NULL);
        if (requested == NULL) return 0;
        const int allowed = requested[0] == '\0' || strcmp(requested, "/system/bin/sh") == 0;
        (*env)->ReleaseStringUTFChars(env, shell_arg, requested);
        if (!allowed) {
            __android_log_print(ANDROID_LOG_WARN, GAIN_TAG,
                                "Rejected unsupported shell; Gain currently exposes Android sh only");
            return 0;
        }
    }

    ensure_sessions();
    pthread_mutex_lock(&g_sessions_lock);
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
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
        if (master >= 0) close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    char slave_name[128];
    if (ptsname_r(master, slave_name, sizeof(slave_name)) != 0) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    int startup_pipe[2];
    if (pipe(startup_pipe) != 0) {
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }
    (void)fcntl(startup_pipe[0], F_SETFD, FD_CLOEXEC);
    (void)fcntl(startup_pipe[1], F_SETFD, FD_CLOEXEC);

    const pid_t parent_pid = getpid();
    const pid_t pid = fork();
    if (pid < 0) {
        close(startup_pipe[0]);
        close(startup_pipe[1]);
        close(master);
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    if (pid == 0) {
        // Arm parent-death handling immediately after fork. The parent may
        // disappear before the PTY handshake or exec sequence completes.
        if (prctl(PR_SET_PDEATHSIG, SIGHUP) != 0 || getppid() != parent_pid) {
            _exit(127);
        }
        close(startup_pipe[0]);
        close(master);
        const int slave = open(slave_name, O_RDWR | O_NOCTTY);
        if (slave < 0) {
            close(startup_pipe[1]);
            _exit(127);
        }
        const unsigned char ready = 1;
        (void)write(startup_pipe[1], &ready, sizeof(ready));
        close(startup_pipe[1]);

        configure_terminal(slave);
        (void)setsid();
#ifdef TIOCSCTTY
        (void)ioctl(slave, TIOCSCTTY, 0);
#endif
        (void)set_winsize(slave, rows, cols);
        (void)dup2(slave, STDIN_FILENO);
        (void)dup2(slave, STDOUT_FILENO);
        (void)dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) close(slave);
        (void)chdir("/");

        char *const argv[] = {(char *)"sh", (char *)"-i", NULL};
        char *const child_env[] = {
            (char *)"HOME=/",
            (char *)"PATH=/system/bin:/system/xbin:/vendor/bin",
            (char *)"SHELL=/system/bin/sh",
            (char *)"TERM=xterm-256color",
            (char *)"COLORTERM=truecolor",
            (char *)"PS1=$ ",
            (char *)"LANG=C.UTF-8",
            NULL
        };
        execve("/system/bin/sh", argv, child_env);
        _exit(127);
    }

    close(startup_pipe[1]);
    struct pollfd startup_wait = {startup_pipe[0], POLLIN | POLLHUP, 0};
    int ready_poll;
    do {
        ready_poll = poll(&startup_wait, 1, 1500);
    } while (ready_poll < 0 && errno == EINTR);
    unsigned char ready = 0;
    const ssize_t ready_bytes = ready_poll > 0
        ? read(startup_pipe[0], &ready, sizeof(ready))
        : -1;
    close(startup_pipe[0]);

    if (ready_bytes != (ssize_t)sizeof(ready) || ready != 1) {
        close(master);
        (void)kill(-pid, SIGKILL);
        (void)kill(pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
        pthread_mutex_unlock(&g_sessions_lock);
        return 0;
    }

    g_sessions[slot].master_fd = master;
    g_sessions[slot].child_pid = pid;
    const jint handle = make_handle(slot, generation);
    pthread_mutex_unlock(&g_sessions_lock);
    return handle;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeReadPty(
    JNIEnv *env, jobject thiz, jint handle) {
    (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (session == NULL) {
        pthread_mutex_unlock(&g_sessions_lock);
        return NULL;
    }

    unsigned char buffer[8192];
    const ssize_t count = read(session->master_fd, buffer, sizeof(buffer));
    if (count > 0) {
        jbyteArray output = (*env)->NewByteArray(env, (jsize)count);
        if (output != NULL) {
            (*env)->SetByteArrayRegion(env, output, 0, (jsize)count, (const jbyte *)buffer);
        }
        pthread_mutex_unlock(&g_sessions_lock);
        return output;
    }
    if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
        jbyteArray empty = (*env)->NewByteArray(env, 0);
        pthread_mutex_unlock(&g_sessions_lock);
        return empty;
    }

    const pid_t pid = session->child_pid;
    const int fd = session->master_fd;
    session->master_fd = -1;
    session->child_pid = -1;
    if (fd >= 0) close(fd);
    pthread_mutex_unlock(&g_sessions_lock);
    reap_child(pid);
    return NULL;
}

JNIEXPORT jint JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeWritePty(
    JNIEnv *env, jobject thiz, jint handle, jbyteArray data) {
    (void)thiz;
    if (data == NULL) return -1;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    const int fd = session != NULL ? dup(session->master_fd) : -1;
    pthread_mutex_unlock(&g_sessions_lock);
    if (fd < 0) return -1;

    const jsize length = (*env)->GetArrayLength(env, data);
    jbyte *bytes = (*env)->GetByteArrayElements(env, data, NULL);
    if (bytes == NULL) {
        close(fd);
        return -1;
    }

    jsize written = 0;
    while (written < length) {
        struct pollfd wait_write = {fd, POLLOUT, 0};
        const int ready = poll(&wait_write, 1, 5000);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0 || (wait_write.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) break;
        const ssize_t count = write(fd, bytes + written, (size_t)(length - written));
        if (count > 0) written += (jsize)count;
        else if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        else break;
    }

    (*env)->ReleaseByteArrayElements(env, data, bytes, JNI_ABORT);
    close(fd);
    return written;
}

JNIEXPORT jboolean JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeResizePty(
    JNIEnv *env, jobject thiz, jint handle, jint rows, jint cols) {
    (void)env;
    (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    const int ok = session != NULL && set_winsize(session->master_fd, rows, cols) == 0;
    pthread_mutex_unlock(&g_sessions_lock);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_example_giant_1agent_GainPtyBridge_nativeStopPty(
    JNIEnv *env, jobject thiz, jint handle) {
    (void)env;
    (void)thiz;
    pthread_mutex_lock(&g_sessions_lock);
    GainPtySession *session = get_session(handle);
    if (session == NULL) {
        pthread_mutex_unlock(&g_sessions_lock);
        return;
    }

    const int fd = session->master_fd;
    const pid_t pid = session->child_pid;
    session->master_fd = -1;
    session->child_pid = -1;
    if (fd >= 0) close(fd);
    pthread_mutex_unlock(&g_sessions_lock);

    if (pid > 0) {
        (void)kill(-pid, SIGHUP);
        (void)kill(-pid, SIGTERM);
        int reaped = 0;
        for (int attempt = 0; attempt < 50; ++attempt) {
            const pid_t result = waitpid(pid, NULL, WNOHANG);
            if (result == pid || (result < 0 && errno == ECHILD)) {
                reaped = 1;
                break;
            }
            usleep(10000);
        }
        if (!reaped) {
            (void)kill(-pid, SIGKILL);
            (void)kill(pid, SIGKILL);
            while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
        }
    }
}
