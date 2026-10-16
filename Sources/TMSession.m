#import "TMSession.h"
#import "TMSettings.h"
#import <spawn.h>
#import <signal.h>
#import <fcntl.h>
#import <stdlib.h>
#import <sys/ioctl.h>
#import <sys/wait.h>
#import <termios.h>
#import <unistd.h>

extern char **environ;

@implementation TMSession {
    int _master;
    dispatch_source_t _readSource, _exitSource;
    dispatch_queue_t _ioQueue, _writeQueue;
    NSMutableData *_pending;
    BOOL _flushScheduled;
    BOOL _exited;
}

- (instancetype)initWithRoot:(BOOL)root {
    if ((self = [super init])) {
        _root = root; _master = -1;
        _ioQueue = dispatch_queue_create("com.makr.terminal.io", DISPATCH_QUEUE_SERIAL);
        _writeQueue = dispatch_queue_create("com.makr.terminal.write", DISPATCH_QUEUE_SERIAL);
        _pending = [NSMutableData data];
    }
    return self;
}

- (BOOL)running { return _pid > 0 && !_exited; }

- (NSArray<NSString *> *)environment {
    NSString *home = _root ? @"/var/root" : @"/var/mobile";
    NSString *user = _root ? @"root" : @"mobile";
    NSString *shell = [[TMSettings shared] resolvedShell];
    NSString *path = @"/var/jb/usr/local/sbin:/var/jb/usr/local/bin:/var/jb/usr/sbin:/var/jb/usr/bin:/var/jb/sbin:/var/jb/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    NSString *app = [NSBundle mainBundle].bundlePath;
    NSMutableArray *e = [@[
        [@"PATH=" stringByAppendingString:path], @"TERM=xterm-256color", @"COLORTERM=truecolor", @"LANG=en_US.UTF-8", @"LC_CTYPE=en_US.UTF-8",
        [@"HOME=" stringByAppendingString:home], [@"USER=" stringByAppendingString:user], [@"LOGNAME=" stringByAppendingString:user],
        [@"SHELL=" stringByAppendingString:shell], @"TMPDIR=/var/jb/tmp", @"TERM_PROGRAM=Terminal", @"TERMINFO_DIRS=/var/jb/usr/share/terminfo:/usr/share/terminfo",
        [@"ZDOTDIR=" stringByAppendingString:[app stringByAppendingPathComponent:@"shell/zsh"]],
        @"MT_LOGIN=1"] mutableCopy];
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/tmp"]) [e replaceObjectAtIndex:[e indexOfObject:@"TMPDIR=/var/jb/tmp"] withObject:@"TMPDIR=/tmp"];
    return e;
}

- (NSArray<NSString *> *)shellArguments:(NSString *)shell {
    NSString *name = shell.lastPathComponent;
    NSString *app = [NSBundle mainBundle].bundlePath;
    if ([name isEqualToString:@"bash"]) return @[@"--rcfile", [app stringByAppendingPathComponent:@"shell/bashrc"], @"-i"];
    if ([name isEqualToString:@"zsh"]) return @[@"-i"];
    return @[@"-i"];
}

static char **cArray(NSArray<NSString *> *a) {
    char **v = calloc(a.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < a.count; i++) v[i] = strdup(a[i].UTF8String);
    return v;
}
static void freeArray(char **v) { for (char **p = v; *p; p++) free(*p); free(v); }

- (BOOL)startWithCols:(int)cols rows:(int)rows error:(NSString **)error {
    NSString *shell = [[TMSettings shared] resolvedShell];
    NSString *helper = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"mtsh"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper]) { if (error) *error = TMT(@"Helper mtsh not found", @"Не найден помощник mtsh"); return NO; }

    int m = posix_openpt(O_RDWR | O_NOCTTY);
    if (m < 0 || grantpt(m) != 0 || unlockpt(m) != 0) { if (error) *error = [NSString stringWithFormat:@"PTY: %s", strerror(errno)]; if (m >= 0) close(m); return NO; }
    const char *slave = ptsname(m);
    if (!slave) { if (error) *error = @"ptsname"; close(m); return NO; }
    fcntl(m, F_SETFD, FD_CLOEXEC);
    struct winsize ws = {(unsigned short)rows, (unsigned short)cols, 0, 0};
    ioctl(m, TIOCSWINSZ, &ws);
    struct termios t;
    if (tcgetattr(m, &t) == 0) { t.c_iflag |= IUTF8; tcsetattr(m, TCSANOW, &t); }

    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, slave, O_RDWR, 0);
    posix_spawn_file_actions_adddup2(&fa, 0, 1);
    posix_spawn_file_actions_adddup2(&fa, 0, 2);
    posix_spawnattr_t at; posix_spawnattr_init(&at);
    sigset_t all, none; sigfillset(&all); sigemptyset(&none);
    posix_spawnattr_setsigdefault(&at, &all); posix_spawnattr_setsigmask(&at, &none);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);

    NSString *home = _root ? @"/var/root" : @"/var/mobile";
    NSMutableArray *args = [@[helper, _root ? @"root" : @"user", home, shell] mutableCopy];
    [args addObjectsFromArray:[self shellArguments:shell]];
    char **argv = cArray(args), **envp = cArray([self environment]);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, helper.UTF8String, &fa, &at, argv, envp);
    freeArray(argv); freeArray(envp);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
    if (rc != 0) { if (error) *error = [NSString stringWithFormat:@"posix_spawn: %s", strerror(rc)]; close(m); return NO; }

    _master = m; _pid = pid; _exited = NO; _shellName = shell.lastPathComponent;
    __weak TMSession *ws2 = self;
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, m, 0, _ioQueue);
    dispatch_source_set_event_handler(_readSource, ^{ [ws2 readAvailable]; });
    dispatch_source_set_cancel_handler(_readSource, ^{ close(m); });   // дескриптор закрывается только после остановки источника
    dispatch_resume(_readSource);
    _exitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, _ioQueue);
    dispatch_source_set_event_handler(_exitSource, ^{ [ws2 childExited]; });
    dispatch_resume(_exitSource);
    return YES;
}

- (void)readAvailable {
    uint8_t buf[65536];
    ssize_t n = read(_master, buf, sizeof buf);
    if (n <= 0) { if (n < 0 && (errno == EAGAIN || errno == EINTR)) return; [self childExited]; return; }
    @synchronized (_pending) { [_pending appendBytes:buf length:(NSUInteger)n]; }
    if (!_flushScheduled) {
        _flushScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self flush]; });
    }
}

- (void)flush {
    _flushScheduled = NO;
    NSData *d;
    @synchronized (_pending) { d = [_pending copy]; _pending.length = 0; }
    if (d.length) [self.delegate session:self didReceiveData:d];
}

- (void)childExited {
    if (_exited) return;
    _exited = YES;
    int status = 0; waitpid(_pid, &status, WNOHANG);
    if (_readSource) { dispatch_source_cancel(_readSource); _readSource = nil; }
    if (_exitSource) { dispatch_source_cancel(_exitSource); _exitSource = nil; }
    // дочитать остаток вывода
    dispatch_async(dispatch_get_main_queue(), ^{
        [self flush];
        self->_master = -1;
        [self.delegate session:self didExitWithStatus:WIFEXITED(status) ? WEXITSTATUS(status) : -1];
    });
}

- (void)writeData:(NSData *)data {
    if (_master < 0 || !data.length) return;
    int fd = _master;
    dispatch_async(_writeQueue, ^{
        const uint8_t *p = data.bytes; size_t left = data.length;
        while (left > 0) {
            ssize_t w = write(fd, p, left);
            if (w < 0) { if (errno == EINTR || errno == EAGAIN) { usleep(1000); continue; } return; }
            p += w; left -= (size_t)w;
        }
    });
}

- (void)resizeCols:(int)cols rows:(int)rows {
    if (_master < 0 || cols < 1 || rows < 1) return;
    struct winsize ws = {(unsigned short)rows, (unsigned short)cols, 0, 0};
    ioctl(_master, TIOCSWINSZ, &ws);
}

- (void)terminate {
    // закрытие мастера отправляет оболочке SIGHUP (kill на root-процесс из-под mobile не пройдёт)
    if (_readSource) { dispatch_source_cancel(_readSource); _readSource = nil; }
    _master = -1;
    if (_pid > 0 && !_exited) kill(_pid, SIGHUP);
}

- (void)dealloc { if (_readSource) dispatch_source_cancel(_readSource); if (_exitSource) dispatch_source_cancel(_exitSource); }

@end
