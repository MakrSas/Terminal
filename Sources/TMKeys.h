#import "TMCommon.h"

// Последовательности клавиш для терминала (xterm)
NSData *TMSequenceForKey(UIKeyboardHIDUsage usage, UIKeyModifierFlags mods, BOOL appCursor);
// Управляющий символ для Ctrl+символ (nil, если не подходит)
NSData *TMControlForCharacter(NSString *ch);
