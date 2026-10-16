#import "TMSettings.h"
#import "TMKeyBarConfig.h"

@implementation TMSettings {
    NSUserDefaults *_d;
}

+ (instancetype)shared {
    static TMSettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TMSettings new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _d = [NSUserDefaults standardUserDefaults];
        [_d registerDefaults:@{@"theme": @"Terminal", @"font": @"JetBrains Mono", @"fontSize": @13, @"cursorStyle": @0, @"cursorBlink": @YES,
                               @"scrollback": @5000, @"shell": @"auto", @"startAsRoot": @NO, @"hapticBell": @YES, @"keepAwake": @NO}];
    }
    return self;
}

- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:TM_DEFAULTS_CHANGED object:nil]; }

- (NSString *)themeName { return [_d stringForKey:@"theme"]; }
- (void)setThemeName:(NSString *)v { [_d setObject:v forKey:@"theme"]; [self changed]; }
- (NSString *)fontFamily { return [_d stringForKey:@"font"]; }
- (void)setFontFamily:(NSString *)v { [_d setObject:v forKey:@"font"]; [self changed]; }
- (double)fontSize { return MIN(32, MAX(8, [_d doubleForKey:@"fontSize"])); }
- (void)setFontSize:(double)v { [_d setDouble:MIN(32, MAX(8, v)) forKey:@"fontSize"]; [self changed]; }
- (TMCursorStyle)cursorStyle { return (TMCursorStyle)[_d integerForKey:@"cursorStyle"]; }
- (void)setCursorStyle:(TMCursorStyle)v { [_d setInteger:v forKey:@"cursorStyle"]; [self changed]; }
- (BOOL)cursorBlink { return [_d boolForKey:@"cursorBlink"]; }
- (void)setCursorBlink:(BOOL)v { [_d setBool:v forKey:@"cursorBlink"]; [self changed]; }
- (NSInteger)scrollback { return [_d integerForKey:@"scrollback"]; }
- (void)setScrollback:(NSInteger)v { [_d setInteger:v forKey:@"scrollback"]; [self changed]; }
- (NSString *)shell { return [_d stringForKey:@"shell"]; }
- (void)setShell:(NSString *)v { [_d setObject:v forKey:@"shell"]; [self changed]; }
- (BOOL)startAsRoot { return [_d boolForKey:@"startAsRoot"]; }
- (void)setStartAsRoot:(BOOL)v { [_d setBool:v forKey:@"startAsRoot"]; [self changed]; }
- (BOOL)hapticBell { return [_d boolForKey:@"hapticBell"]; }
- (void)setHapticBell:(BOOL)v { [_d setBool:v forKey:@"hapticBell"]; [self changed]; }
- (BOOL)keepAwake { return [_d boolForKey:@"keepAwake"]; }
- (void)setKeepAwake:(BOOL)v { [_d setBool:v forKey:@"keepAwake"]; [self changed]; }

- (NSArray<NSDictionary *> *)keyBarItems {
    NSArray *a = [_d arrayForKey:@"keyBar"];
    return a.count ? a : [TMKeyBarConfig defaultItems];
}
- (void)setKeyBarItems:(NSArray<NSDictionary *> *)v { [_d setObject:v forKey:@"keyBar"]; [self changed]; }

- (NSString *)cssFontFamily {
    NSString *f = self.fontFamily;
    if ([f isEqualToString:@"Menlo"]) return @"Menlo, \"JetBrains Mono\", monospace";
    if ([f isEqualToString:@"SF Mono"]) return @"ui-monospace, \"SF Mono\", Menlo, \"JetBrains Mono\", monospace";
    return @"\"JetBrains Mono\", Menlo, monospace";
}

+ (NSArray<NSString *> *)availableShells {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *p in @[@"/var/jb/bin/zsh", @"/var/jb/usr/bin/zsh", @"/var/jb/bin/bash", @"/var/jb/usr/bin/bash", @"/var/jb/bin/fish", @"/var/jb/usr/bin/fish",
                          @"/var/jb/bin/dash", @"/var/jb/bin/sh", @"/bin/zsh", @"/bin/bash", @"/bin/sh"])
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) [a addObject:p];
    return a;
}

- (NSString *)resolvedShell {
    NSString *s = self.shell;
    if (![s isEqualToString:@"auto"] && [[NSFileManager defaultManager] isExecutableFileAtPath:s]) return s;
    return [TMSettings availableShells].firstObject ?: @"/bin/sh";
}

@end
