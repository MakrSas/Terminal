#import <UIKit/UIKit.h>

// Псевдографика рисуется прямоугольниками по сетке ячейки: линии и блоки стыкуются без щелей, как в настоящих терминалах.
// Возвращает YES, если символ обработан (иначе его нарисует шрифт).
BOOL TMDrawBoxChar(CGContextRef ctx, uint32_t ch, CGRect cell, CGFloat scale, CGColorRef color);
