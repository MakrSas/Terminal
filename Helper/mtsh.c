// mtsh — запуск оболочки на псевдотерминале.
// Использование: mtsh <user|root> <каталог> <программа> [аргументы...]
// Стандартные ввод/вывод/ошибка уже подключены к подчинённой стороне PTY (это делает приложение через posix_spawn).
// Файл ставится с битом setuid root. Root-режим разрешён только если процесс запущен самим приложением Terminal;
// режим user сбрасывает права до реального пользователя (mobile).
#include <errno.h>
#include <limits.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <grp.h>

#ifndef MT_APP_EXEC
#define MT_APP_EXEC "/var/jb/Applications/Terminal.app/Terminal"
#endif
extern int proc_pidpath(int pid, void *buffer, unsigned int size);

static int parentIsApp(void) {
    char path[1024] = {0};
    if (proc_pidpath(getppid(), path, sizeof path) <= 0) return 0;
    // /var/jb — символическая ссылка, поэтому сравниваем реальные пути
    char want[PATH_MAX], have[PATH_MAX];
    if (!realpath(MT_APP_EXEC, want) || !realpath(path, have)) return 0;
    return strcmp(want, have) == 0;
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: mtsh user|root cwd program [args]\n"); return 64; }
    int wantRoot = strcmp(argv[1], "root") == 0;
    uid_t realUID = getuid(); gid_t realGID = getgid();
    if (wantRoot) {
        if (geteuid() != 0) { fprintf(stderr, "mtsh: no root privileges (setuid bit is missing)\n"); return 77; }
        if (!parentIsApp()) { fprintf(stderr, "mtsh: root shell can only be started by Terminal\n"); return 77; }
        if (setgid(0) != 0 || setuid(0) != 0) { perror("mtsh: setuid"); return 77; }
    } else {
        if (geteuid() == 0) {   // сбросить повышенные права до реального пользователя
            if (setgroups(0, NULL) != 0) { /* не критично */ }
            if (setgid(realGID) != 0 || setuid(realUID) != 0) { perror("mtsh: drop privileges"); return 77; }
        }
    }
    setsid();
    if (ioctl(0, TIOCSCTTY, 0) != 0) { /* без управляющего терминала часть программ работает хуже, но продолжаем */ }
    if (chdir(argv[2]) != 0) chdir("/");
    char *prog = argv[3];
    char *args[argc];   // argv[3..] -> новый argv; argv[0] — имя, как у login-оболочки, если задан MT_LOGIN
    int n = 0;
    char login[256];
    if (getenv("MT_LOGIN")) {
        char *copy = strdup(prog); snprintf(login, sizeof login, "-%s", basename(copy)); args[n++] = login;
    } else args[n++] = prog;
    for (int i = 4; i < argc; i++) args[n++] = argv[i];
    args[n] = NULL;
    unsetenv("MT_LOGIN");
    execv(prog, args);
    perror(prog);
    return 127;
}
