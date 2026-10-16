#import <UIKit/UIKit.h>

// Строки интерфейса: английский и русский по языку системы
static inline BOOL TMIsRussian(void) { return [[NSLocale preferredLanguages].firstObject hasPrefix:@"ru"]; }
#define TMT(en, ru) (TMIsRussian() ? (ru) : (en))

#define TM_APP_EXEC @"/var/jb/Applications/Terminal.app/Terminal"
#define TM_DEFAULTS_CHANGED @"TMSettingsChanged"

static inline UIColor *TMHex(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
static inline NSString *TMHexString(uint32_t rgb) { return [NSString stringWithFormat:@"#%06x", rgb & 0xffffff]; }

#ifdef TM_DEBUG
void TMLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
#else
#define TMLog(...) ((void)0)
#endif
