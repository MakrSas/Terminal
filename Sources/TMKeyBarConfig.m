#import "TMKeyBarConfig.h"

@implementation TMKeyDef
@end

static NSArray<TMKeyDef *> *gCatalog;

static TMKeyDef *D(NSString *ident, NSString *title, NSString *group, TMKeyKind kind) {
    TMKeyDef *d = [TMKeyDef new]; d.ident = ident; d.title = title; d.group = group; d.kind = kind; return d;
}
static TMKeyDef *U(NSString *ident, NSString *title, NSString *group, UIKeyboardHIDUsage u, BOOL rep) {
    TMKeyDef *d = D(ident, title, group, TMKeyKindUsage); d.usage = u; d.repeats = rep; return d;
}
static TMKeyDef *T(NSString *ident, NSString *title, NSString *group, NSString *text) {
    TMKeyDef *d = D(ident, title, group, TMKeyKindText); d.text = text; return d;
}

@implementation TMKeyBarConfig

+ (NSArray<NSString *> *)groups { return @[@"mod", @"nav", @"fn", @"sym", @"ctl", @"act"]; }

+ (NSArray<TMKeyDef *> *)catalog {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        [a addObject:U(@"esc", @"esc", @"mod", UIKeyboardHIDUsageKeyboardEscape, NO)];
        [a addObject:U(@"tab", @"tab", @"mod", UIKeyboardHIDUsageKeyboardTab, NO)];
        [a addObject:D(@"ctrl", @"ctrl", @"mod", TMKeyKindCtrl)];
        [a addObject:D(@"alt", @"alt", @"mod", TMKeyKindAlt)];
        [a addObject:T(@"enter", @"⏎", @"mod", @"\r")];
        [a addObject:U(@"left", @"←", @"nav", UIKeyboardHIDUsageKeyboardLeftArrow, YES)];
        [a addObject:U(@"down", @"↓", @"nav", UIKeyboardHIDUsageKeyboardDownArrow, YES)];
        [a addObject:U(@"up", @"↑", @"nav", UIKeyboardHIDUsageKeyboardUpArrow, YES)];
        [a addObject:U(@"right", @"→", @"nav", UIKeyboardHIDUsageKeyboardRightArrow, YES)];
        [a addObject:U(@"home", @"home", @"nav", UIKeyboardHIDUsageKeyboardHome, NO)];
        [a addObject:U(@"end", @"end", @"nav", UIKeyboardHIDUsageKeyboardEnd, NO)];
        [a addObject:U(@"pgup", @"pgup", @"nav", UIKeyboardHIDUsageKeyboardPageUp, YES)];
        [a addObject:U(@"pgdn", @"pgdn", @"nav", UIKeyboardHIDUsageKeyboardPageDown, YES)];
        [a addObject:U(@"ins", @"ins", @"nav", UIKeyboardHIDUsageKeyboardInsert, NO)];
        [a addObject:U(@"del", @"del", @"nav", UIKeyboardHIDUsageKeyboardDeleteForward, YES)];
        for (int i = 0; i < 12; i++) [a addObject:U([NSString stringWithFormat:@"f%d", i + 1], [NSString stringWithFormat:@"F%d", i + 1], @"fn", (UIKeyboardHIDUsage)(UIKeyboardHIDUsageKeyboardF1 + i), NO)];
        for (NSString *s in @[@"/", @"-", @"|", @"~", @"$", @"\\", @"_", @"&", @"*", @".", @",", @":", @";", @"'", @"\"", @"`", @"(", @")", @"[", @"]", @"{", @"}", @"<", @">", @"=", @"+", @"!", @"@", @"#", @"%", @"^", @"?"])
            [a addObject:T([@"sym:" stringByAppendingString:s], s, @"sym", s)];
        [a addObject:T(@"ctrl-c", @"^C", @"ctl", @"\x03")];
        [a addObject:T(@"ctrl-d", @"^D", @"ctl", @"\x04")];
        [a addObject:T(@"ctrl-z", @"^Z", @"ctl", @"\x1a")];
        [a addObject:T(@"ctrl-l", @"^L", @"ctl", @"\x0c")];
        [a addObject:T(@"ctrl-a", @"^A", @"ctl", @"\x01")];
        [a addObject:T(@"ctrl-e", @"^E", @"ctl", @"\x05")];
        [a addObject:T(@"ctrl-r", @"^R", @"ctl", @"\x12")];
        [a addObject:T(@"ctrl-u", @"^U", @"ctl", @"\x15")];
        [a addObject:T(@"ctrl-w", @"^W", @"ctl", @"\x17")];
        [a addObject:D(@"paste", @"paste", @"act", TMKeyKindPaste)];
        [a addObject:D(@"fn", @"Fn", @"act", TMKeyKindFn)];
        gCatalog = a;
    });
    return gCatalog;
}

+ (NSArray<NSDictionary *> *)defaultItems {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *i in @[@"esc", @"tab", @"ctrl", @"alt", @"left", @"down", @"up", @"right",
                          @"sym:/", @"sym:-", @"sym:|", @"sym:~", @"sym:$", @"sym:\\", @"sym:_", @"sym:&", @"sym:*", @"sym:.", @"sym:,", @"sym::", @"sym:;", @"sym:'", @"sym:\"", @"sym:`",
                          @"sym:(", @"sym:)", @"sym:[", @"sym:]", @"sym:{", @"sym:}", @"sym:<", @"sym:>", @"sym:=", @"sym:+", @"sym:!", @"sym:@", @"sym:#", @"sym:%", @"sym:^", @"sym:?",
                          @"paste", @"fn"])
        [a addObject:@{@"id": i}];
    return a;
}

+ (TMKeyDef *)defForItem:(NSDictionary *)item {
    NSString *ident = item[@"id"];
    if ([ident isEqualToString:@"custom"]) {
        TMKeyDef *d = D(@"custom", item[@"label"] ?: @"?", @"custom", TMKeyKindText);
        d.text = [self expandEscapes:item[@"text"] ?: @""]; return d;
    }
    for (TMKeyDef *d in [self catalog]) if ([d.ident isEqualToString:ident]) return d;
    return nil;
}

+ (NSString *)titleForItem:(NSDictionary *)item { return [self defForItem:item].title ?: @"?"; }

+ (NSString *)detailForItem:(NSDictionary *)item {
    if ([item[@"id"] isEqualToString:@"custom"]) return [NSString stringWithFormat:@"%@ %@", TMT(@"Custom:", @"Своя:"), item[@"text"] ?: @""];
    TMKeyDef *d = [self defForItem:item];
    NSDictionary *names = @{@"mod": TMT(@"Modifiers and basic", @"Основные"), @"nav": TMT(@"Navigation", @"Навигация"), @"fn": TMT(@"Function keys", @"Функциональные"),
                            @"sym": TMT(@"Symbol", @"Символ"), @"ctl": TMT(@"Control combination", @"Сочетание с Ctrl"), @"act": TMT(@"Action", @"Действие")};
    return names[d.group] ?: @"";
}

+ (NSString *)expandEscapes:(NSString *)s {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' && i + 1 < s.length) {
            unichar n = [s characterAtIndex:++i];
            switch (n) {
                case 'e': [out appendString:@"\x1b"]; break;
                case 't': [out appendString:@"\t"]; break;
                case 'r': case 'n': [out appendString:@"\r"]; break;
                case '\\': [out appendString:@"\\"]; break;
                case 'x': if (i + 2 < s.length) { unsigned v = 0; if ([[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(i + 1, 2)]] scanHexInt:&v]) { [out appendFormat:@"%C", (unichar)v]; i += 2; } } break;
                default: [out appendFormat:@"\\%C", n]; break;
            }
        } else if (c == '^' && i + 1 < s.length) {
            unichar n = [s characterAtIndex:i + 1];
            if ((n >= '@' && n <= '_') || (n >= 'a' && n <= 'z')) { [out appendFormat:@"%C", (unichar)(n & 0x1f)]; i++; }
            else [out appendFormat:@"%C", c];
        } else [out appendFormat:@"%C", c];
    }
    return out;
}

@end
