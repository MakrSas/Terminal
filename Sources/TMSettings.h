#import "TMCommon.h"

typedef NS_ENUM(NSInteger, TMCursorStyle) { TMCursorBlock = 0, TMCursorBar = 1, TMCursorUnderline = 2 };

// Настройки приложения (NSUserDefaults). Любое изменение шлёт TM_DEFAULTS_CHANGED.
@interface TMSettings : NSObject
+ (instancetype)shared;
@property (nonatomic) NSString *themeName;
@property (nonatomic) NSString *fontFamily;      // "JetBrains Mono" / "Menlo" / "SF Mono"
@property (nonatomic) double fontSize;           // 8…32
@property (nonatomic) TMCursorStyle cursorStyle;
@property (nonatomic) BOOL cursorBlink;
@property (nonatomic) NSInteger scrollback;      // строк
@property (nonatomic) NSString *shell;           // "auto" или путь
@property (nonatomic) BOOL startAsRoot;          // новая вкладка по умолчанию с правами root
@property (nonatomic) BOOL hapticBell;
@property (nonatomic) BOOL keepAwake;
@property (nonatomic, copy) NSArray<NSDictionary *> *keyBarItems;   // клавиши панели над клавиатурой (TMKeyBarConfig)
- (NSString *)cssFontFamily;
// Путь оболочки: выбранная пользователем или первая найденная (zsh, bash, sh)
- (NSString *)resolvedShell;
+ (NSArray<NSString *> *)availableShells;
@end
