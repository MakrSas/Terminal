#import "TMKeys.h"

static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

static int modParam(UIKeyModifierFlags m) {
    int p = 1;
    if (m & UIKeyModifierShift) p += 1;
    if (m & UIKeyModifierAlternate) p += 2;
    if (m & UIKeyModifierControl) p += 4;
    return p;
}

NSData *TMSequenceForKey(UIKeyboardHIDUsage u, UIKeyModifierFlags mods, BOOL app) {
    int p = modParam(mods);
    BOOL plain = p == 1;
    NSString *arrow = nil;
    switch (u) {
        case UIKeyboardHIDUsageKeyboardUpArrow: arrow = @"A"; break;
        case UIKeyboardHIDUsageKeyboardDownArrow: arrow = @"B"; break;
        case UIKeyboardHIDUsageKeyboardRightArrow: arrow = @"C"; break;
        case UIKeyboardHIDUsageKeyboardLeftArrow: arrow = @"D"; break;
        case UIKeyboardHIDUsageKeyboardHome: arrow = @"H"; break;
        case UIKeyboardHIDUsageKeyboardEnd: arrow = @"F"; break;
        default: break;
    }
    if (arrow) {
        NSString *seq;
        if (!plain) seq = [NSString stringWithFormat:@"\e[1;%d%@", p, arrow];
        else seq = [(app ? @"\eO" : @"\e[") stringByAppendingString:arrow];
        return D(seq);
    }
    int tilde = 0;
    switch (u) {
        case UIKeyboardHIDUsageKeyboardInsert: tilde = 2; break;
        case UIKeyboardHIDUsageKeyboardDeleteForward: tilde = 3; break;
        case UIKeyboardHIDUsageKeyboardPageUp: tilde = 5; break;
        case UIKeyboardHIDUsageKeyboardPageDown: tilde = 6; break;
        case UIKeyboardHIDUsageKeyboardF5: tilde = 15; break;
        case UIKeyboardHIDUsageKeyboardF6: tilde = 17; break;
        case UIKeyboardHIDUsageKeyboardF7: tilde = 18; break;
        case UIKeyboardHIDUsageKeyboardF8: tilde = 19; break;
        case UIKeyboardHIDUsageKeyboardF9: tilde = 20; break;
        case UIKeyboardHIDUsageKeyboardF10: tilde = 21; break;
        case UIKeyboardHIDUsageKeyboardF11: tilde = 23; break;
        case UIKeyboardHIDUsageKeyboardF12: tilde = 24; break;
        default: break;
    }
    if (tilde) {
        NSString *seq = plain ? [NSString stringWithFormat:@"\e[%d~", tilde] : [NSString stringWithFormat:@"\e[%d;%d~", tilde, p];
        return D(seq);
    }
    NSString *fn = nil;
    switch (u) {
        case UIKeyboardHIDUsageKeyboardF1: fn = @"P"; break;
        case UIKeyboardHIDUsageKeyboardF2: fn = @"Q"; break;
        case UIKeyboardHIDUsageKeyboardF3: fn = @"R"; break;
        case UIKeyboardHIDUsageKeyboardF4: fn = @"S"; break;
        default: break;
    }
    if (fn) {
        NSString *seq = plain ? [@"\eO" stringByAppendingString:fn] : [NSString stringWithFormat:@"\e[1;%d%@", p, fn];
        return D(seq);
    }
    if (u == UIKeyboardHIDUsageKeyboardEscape) return D(@"\e");
    if (u == UIKeyboardHIDUsageKeyboardTab) return (mods & UIKeyModifierShift) ? D(@"\e[Z") : D(@"\t");
    return nil;
}

NSData *TMControlForCharacter(NSString *ch) {
    if (ch.length != 1) return nil;
    unichar c = [ch characterAtIndex:0];
    uint8_t b;
    if (c >= 'a' && c <= 'z') b = (uint8_t)(c - 'a' + 1);
    else if (c >= 'A' && c <= 'Z') b = (uint8_t)(c - 'A' + 1);
    else if (c == '@' || c == ' ' || c == '2') b = 0;
    else if (c == '[' || c == '3') b = 27;
    else if (c == '\\' || c == '4') b = 28;
    else if (c == ']' || c == '5') b = 29;
    else if (c == '^' || c == '6') b = 30;
    else if (c == '_' || c == '7' || c == '-') b = 31;
    else if (c == '?' || c == '8') b = 127;
    else return nil;
    return [NSData dataWithBytes:&b length:1];
}
