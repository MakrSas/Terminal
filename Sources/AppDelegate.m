#import "AppDelegate.h"
#import "TMRootViewController.h"
#import <notify.h>
#import <CoreText/CoreText.h>

#ifdef TM_DEBUG
void TMLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    NSString *dir = @"/var/mobile/Library/Caches/com.makr.terminal";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:[dir stringByAppendingPathComponent:@"log.txt"]];
    if (!h) { [@"" writeToFile:[dir stringByAppendingPathComponent:@"log.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil]; h = [NSFileHandle fileHandleForWritingAtPath:[dir stringByAppendingPathComponent:@"log.txt"]]; }
    [h seekToEndOfFile]; [h writeData:[[m stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}
#endif

@implementation AppDelegate

// Шрифты из пакета (JetBrains Mono, OFL) — регистрируем для процесса
static void registerFonts(void) {
    NSString *dir = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"fonts"];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        if (![f.pathExtension isEqualToString:@"ttf"]) continue;
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:f]], kCTFontManagerScopeProcess, NULL);
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    registerFonts();
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [TMRootViewController new];
    [self.window makeKeyAndVisible];
#ifdef TM_DEBUG
    // Отладка: снимок экрана и ввод текста по уведомлению (только отладочная сборка)
    int tok;
    notify_register_dispatch("com.makr.terminal/screenshot", &tok, dispatch_get_main_queue(), ^(int t) {
        UIGraphicsBeginImageContextWithOptions(self.window.bounds.size, YES, 1);
        [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/Caches/com.makr.terminal" withIntermediateDirectories:YES attributes:nil error:nil];
        [UIImagePNGRepresentation(img) writeToFile:@"/var/mobile/Library/Caches/com.makr.terminal/screen.png" atomically:YES];
    });
    int tok2;
    notify_register_dispatch("com.makr.terminal/input", &tok2, dispatch_get_main_queue(), ^(int t) {
        NSString *s = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/com.makr.terminal/input.txt" encoding:NSUTF8StringEncoding error:nil];
        if (s) [(TMRootViewController *)self.window.rootViewController debugSendText:s];
    });
#endif
#ifdef TM_DEBUG
    int tok5;
    notify_register_dispatch("com.makr.terminal/ui", &tok5, dispatch_get_main_queue(), ^(int t) {
        NSString *cmd = [[NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/com.makr.terminal/ui.txt" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [(TMRootViewController *)self.window.rootViewController debugUI:cmd];
    });
    int tok4;
    notify_register_dispatch("com.makr.terminal/newroot", &tok4, dispatch_get_main_queue(), ^(int t) { [(TMRootViewController *)self.window.rootViewController newTabRoot:YES]; });
    int tok3;
    notify_register_dispatch("com.makr.terminal/dump", &tok3, dispatch_get_main_queue(), ^(int t) {
        NSString *s = [(TMRootViewController *)self.window.rootViewController debugVisibleText];
        [s writeToFile:@"/var/mobile/Library/Caches/com.makr.terminal/dump.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
#endif
    return YES;
}

@end
