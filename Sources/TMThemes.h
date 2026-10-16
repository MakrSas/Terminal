#import "TMCommon.h"

// Цветовая схема терминала
@interface TMTheme : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) uint32_t background, foreground, cursor, selection;
@property (nonatomic, readonly) NSArray<NSNumber *> *ansi;   // 16 цветов
@property (nonatomic, readonly) BOOL light;
+ (NSArray<TMTheme *> *)all;
+ (TMTheme *)themeNamed:(NSString *)name;
// Словарь для xterm.js
- (NSDictionary *)xtermTheme;
// Цвета панелей, выведенные из темы терминала
- (uint32_t)chromeBackground;    // полоса вкладок (и под строкой состояния)
- (uint32_t)keyBarBackground;    // панель клавиш
- (uint32_t)accent;              // активные элементы (курсор темы)
- (uint32_t)lockColor;           // залипший модификатор
@end
uint32_t TMMix(uint32_t a, uint32_t b, double t);   // a·(1−t) + b·t
