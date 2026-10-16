#import "TerminalViewController.h"

#import <WebKit/WebKit.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/ioctl.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <termios.h>
#import <unistd.h>

@interface TerminalViewController () <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) dispatch_source_t readSource;
@property (nonatomic, strong) dispatch_queue_t ptyQueue;
@property (nonatomic) int ptyMaster;
@property (nonatomic) pid_t shellPID;
@property (nonatomic) NSUInteger sessionGeneration;
@property (nonatomic) NSUInteger ptyColumns;
@property (nonatomic) NSUInteger ptyRows;
@property (nonatomic) BOOL webReady;
@property (nonatomic) BOOL shellStarted;
@end

@implementation TerminalViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _ptyMaster = -1;
        _shellPID = 0;
        _ptyColumns = 80;
        _ptyRows = 24;
        _ptyQueue = dispatch_queue_create("com.makr.terminal.pty", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:8.0 / 255.0 green:10.0 / 255.0 blue:16.0 / 255.0 alpha:1.0];
    self.view.tintColor = [UIColor whiteColor];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *contentController = [[WKUserContentController alloc] init];
    [contentController addScriptMessageHandler:self name:@"terminalReady"];
    [contentController addScriptMessageHandler:self name:@"ptyInput"];
    [contentController addScriptMessageHandler:self name:@"ptyResize"];
    [contentController addScriptMessageHandler:self name:@"terminalRestart"];
    configuration.userContentController = contentController;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.opaque = NO;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"Web"];
    if (htmlPath.length == 0) {
        [self showNativeError:@"В приложении не найдены файлы интерфейса терминала."];
        return;
    }
    NSURL *htmlURL = [NSURL fileURLWithPath:htmlPath];
    [self.webView loadFileURL:htmlURL allowingReadAccessToURL:htmlURL.URLByDeletingLastPathComponent];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return NO;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;

    if ([message.name isEqualToString:@"terminalReady"]) {
        self.webReady = YES;
        [self startTerminalSession];
        return;
    }

    if ([message.name isEqualToString:@"ptyInput"] && [message.body isKindOfClass:[NSString class]]) {
        [self writeInput:message.body];
        return;
    }

    if ([message.name isEqualToString:@"ptyResize"] && [message.body isKindOfClass:[NSDictionary class]]) {
        [self resizeTerminal:message.body];
        return;
    }

    if ([message.name isEqualToString:@"terminalRestart"]) {
        [self restartTerminalSession];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self showNativeError:error.localizedDescription ?: @"Не удалось открыть экран терминала."];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    [self showNativeError:error.localizedDescription ?: @"Не удалось открыть экран терминала."];
}

- (void)showNativeError:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Makr Terminal"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (NSString *)availableShellPath {
    NSArray<NSString *> *candidates = @[
        @"/bin/zsh", @"/usr/bin/zsh", @"/bin/bash", @"/usr/bin/bash",
        @"/bin/sh"
    ];
    for (NSString *candidate in candidates) {
        if (access(candidate.fileSystemRepresentation, X_OK) == 0) {
            return candidate;
        }
    }
    return nil;
}

- (void)startTerminalSession {
    if (self.shellStarted || !self.webReady) {
        return;
    }
    self.shellStarted = YES;
    [self setStatus:@"Запускаю shell…"];

    NSString *shellPath = [self availableShellPath];
    if (shellPath.length == 0) {
        self.shellStarted = NO;
        [self writeOutputString:@"\r\nНе найдена shell-программа. Проверьте /bin/sh или установите bash/zsh.\r\n"];
        [self setStatus:@"Shell не найдена"];
        return;
    }

    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
        int savedError = errno;
        if (master >= 0) {
            close(master);
        }
        self.shellStarted = NO;
        [self writeOutputString:[NSString stringWithFormat:@"\r\nCould not create a PTY: %s\r\n", strerror(savedError)]];
        [self setStatus:@"PTY недоступна"];
        return;
    }

    char *slaveName = ptsname(master);
    if (slaveName == NULL) {
        int savedError = errno;
        close(master);
        self.shellStarted = NO;
        [self writeOutputString:[NSString stringWithFormat:@"\r\nНе удалось найти PTY slave: %s\r\n", strerror(savedError)]];
        [self setStatus:@"PTY недоступна"];
        return;
    }

    int slave = open(slaveName, O_RDWR | O_NOCTTY);
    if (slave < 0) {
        int savedError = errno;
        close(master);
        self.shellStarted = NO;
        [self writeOutputString:[NSString stringWithFormat:@"\r\nНе удалось открыть PTY slave: %s\r\n", strerror(savedError)]];
        [self setStatus:@"PTY недоступна"];
        return;
    }

    struct winsize initialSize = {
        .ws_row = (unsigned short)self.ptyRows,
        .ws_col = (unsigned short)self.ptyColumns,
        .ws_xpixel = 0,
        .ws_ypixel = 0
    };
    ioctl(slave, TIOCSWINSZ, &initialSize);

    const char *shellFile = shellPath.fileSystemRepresentation;
    BOOL isPOSIXShell = [shellPath.lastPathComponent isEqualToString:@"sh"];
    char *shellArguments[] = {
        (char *)shellPath.lastPathComponent.UTF8String,
        isPOSIXShell ? (char *)"-i" : (char *)"--login",
        isPOSIXShell ? NULL : (char *)"-i",
        NULL
    };
    NSString *homePath = NSHomeDirectory();
    NSString *temporaryPath = NSTemporaryDirectory();
    NSString *pathEnvironment = @"PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    NSString *homeEnvironment = [@"HOME=" stringByAppendingString:homePath];
    NSString *pwdEnvironment = [@"PWD=" stringByAppendingString:homePath];
    NSString *temporaryEnvironment = [@"TMPDIR=" stringByAppendingString:temporaryPath];
    const char *workingDirectory = homePath.fileSystemRepresentation;
    const char *shellEnvironment[] = {
        (char *)pathEnvironment.UTF8String,
        (char *)homeEnvironment.UTF8String,
        "USER=mobile",
        "LOGNAME=mobile",
        "TERM=xterm-256color",
        "TERM_PROGRAM=MakrTerminal",
        "COLORTERM=truecolor",
        "LANG=en_US.UTF-8",
        "LC_ALL=en_US.UTF-8",
        (char *)pwdEnvironment.UTF8String,
        (char *)temporaryEnvironment.UTF8String,
        NULL
    };

    pid_t child = fork();
    if (child == -1) {
        int savedError = errno;
        close(slave);
        close(master);
        self.shellStarted = NO;
        [self writeOutputString:[NSString stringWithFormat:@"\r\nНе удалось запустить shell: %s\r\n", strerror(savedError)]];
        [self setStatus:@"Не удалось запустить shell"];
        return;
    }

    if (child == 0) {
        close(master);
        if (setsid() < 0 || ioctl(slave, TIOCSCTTY, 0) < 0) {
            _exit(126);
        }
        if (dup2(slave, STDIN_FILENO) < 0 || dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0) {
            _exit(126);
        }
        if (slave > STDERR_FILENO) {
            close(slave);
        }
        chdir(workingDirectory);
        execve(shellFile, shellArguments, (char *const *)shellEnvironment);
        const char errorMessage[] = "Makr Terminal: execve failed\r\n";
        write(STDERR_FILENO, errorMessage, sizeof(errorMessage) - 1);
        _exit(127);
    }

    close(slave);
    int descriptorFlags = fcntl(master, F_GETFL, 0);
    if (descriptorFlags >= 0) {
        fcntl(master, F_SETFL, descriptorFlags | O_NONBLOCK);
    }
    self.ptyMaster = master;
    self.shellPID = child;

    __weak typeof(self) weakSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)master, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf drainPTY];
    });
    dispatch_resume(source);
    self.readSource = source;

    [self setStatus:[NSString stringWithFormat:@"%@ · sandbox", shellPath.lastPathComponent]];
}

- (void)drainPTY {
    if (self.ptyMaster < 0) {
        return;
    }

    char buffer[8192];
    while (YES) {
        ssize_t count = read(self.ptyMaster, buffer, sizeof(buffer));
        if (count > 0) {
            NSData *output = [NSData dataWithBytes:buffer length:(NSUInteger)count];
            [self writeOutput:output];
            continue;
        }
        if (count == 0 || (count < 0 && errno == EIO)) {
            [self finishTerminalSession];
            return;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
            return;
        }
        if (count < 0) {
            int savedError = errno;
            [self writeOutputString:[NSString stringWithFormat:@"\r\nPTY read failed: %s\r\n", strerror(savedError)]];
            [self finishTerminalSession];
            return;
        }
    }
}

- (void)writeOutput:(NSData *)data {
    if (!self.webReady || data.length == 0) {
        return;
    }
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    NSString *script = [NSString stringWithFormat:@"window.makrTerminal && window.makrTerminal.writeBase64('%@');", base64];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)writeOutputString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [self writeOutput:data];
}

- (void)writeInput:(NSString *)input {
    if (input.length == 0 || self.ptyMaster < 0) {
        return;
    }
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    int descriptor = self.ptyMaster;
    NSUInteger generation = self.sessionGeneration;
    dispatch_async(self.ptyQueue, ^{
        const uint8_t *bytes = data.bytes;
        size_t remaining = data.length;
        while (remaining > 0) {
            if (self.sessionGeneration != generation || self.ptyMaster != descriptor) {
                return;
            }
            ssize_t written = write(descriptor, bytes, remaining);
            if (written > 0) {
                bytes += written;
                remaining -= (size_t)written;
                continue;
            }
            if (written < 0 && errno == EINTR) {
                continue;
            }
            if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                struct pollfd pollDescriptor = { .fd = descriptor, .events = POLLOUT, .revents = 0 };
                if (poll(&pollDescriptor, 1, 1000) > 0) {
                    continue;
                }
            }
            break;
        }
    });
}

- (void)resizeTerminal:(NSDictionary *)size {
    NSInteger columns = [size[@"cols"] integerValue];
    NSInteger rows = [size[@"rows"] integerValue];
    if (columns < 2 || rows < 2 || columns > 300 || rows > 150) {
        return;
    }
    self.ptyColumns = (NSUInteger)columns;
    self.ptyRows = (NSUInteger)rows;
    if (self.ptyMaster < 0) {
        return;
    }

    struct winsize terminalSize = {
        .ws_row = (unsigned short)rows,
        .ws_col = (unsigned short)columns,
        .ws_xpixel = 0,
        .ws_ypixel = 0
    };
    if (ioctl(self.ptyMaster, TIOCSWINSZ, &terminalSize) == 0 && self.shellPID > 0) {
        kill(self.shellPID, SIGWINCH);
    }
}

- (void)restartTerminalSession {
    pid_t oldPID = self.shellPID;
    if (oldPID > 0) {
        kill(-oldPID, SIGHUP);
        kill(-oldPID, SIGTERM);
    }
    [self closePTY];
    self.shellStarted = NO;
    [self.webView evaluateJavaScript:@"window.makrTerminal && window.makrTerminal.reset();" completionHandler:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.ptyQueue, ^{
        if (oldPID > 0) {
            int status = 0;
            for (NSUInteger attempt = 0; attempt < 20; attempt++) {
                pid_t result = waitpid(oldPID, &status, WNOHANG);
                if (result == oldPID || (result < 0 && errno == ECHILD)) {
                    break;
                }
                usleep(25000);
            }
            if (waitpid(oldPID, &status, WNOHANG) == 0) {
                kill(oldPID, SIGKILL);
                waitpid(oldPID, NULL, 0);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startTerminalSession];
        });
    });
}

- (void)finishTerminalSession {
    if (self.shellPID > 0) {
        waitpid(self.shellPID, NULL, WNOHANG);
    }
    [self closePTY];
    self.shellStarted = NO;
    [self writeOutputString:@"\r\n[Сессия завершена. Нажмите ↻, чтобы открыть новую.]\r\n"];
    [self setStatus:@"Сессия завершена"];
}

- (void)closePTY {
    self.sessionGeneration += 1;
    if (self.readSource != nil) {
        dispatch_source_cancel(self.readSource);
        self.readSource = nil;
    }
    if (self.ptyMaster >= 0) {
        close(self.ptyMaster);
        self.ptyMaster = -1;
    }
    self.shellPID = 0;
}

- (void)setStatus:(NSString *)status {
    if (!self.webReady) {
        return;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[status ?: @""] options:0 error:nil];
    NSString *encoded = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *script = [NSString stringWithFormat:@"window.makrTerminal && window.makrTerminal.setStatus((%@)[0]);", encoded ?: @"['Terminal']"];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)dealloc {
    if (self.shellPID > 0) {
        kill(-self.shellPID, SIGHUP);
        kill(self.shellPID, SIGTERM);
    }
    [self closePTY];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"terminalReady"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"ptyInput"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"ptyResize"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"terminalRestart"];
}

@end
