#import "TMCommon.h"

@class TMExtraKeysBar;
@protocol TMExtraKeysBarDelegate <NSObject>
- (void)extraKeysBar:(TMExtraKeysBar *)bar sendText:(NSString *)text;
- (void)extraKeysBar:(TMExtraKeysBar *)bar sendKey:(UIKeyboardHIDUsage)usage;
- (void)extraKeysBarPaste:(TMExtraKeysBar *)bar;
- (void)extraKeysBarHideKeyboard:(TMExtraKeysBar *)bar;
@end

typedef NS_ENUM(NSInteger, TMModState) { TMModOff = 0, TMModOnce = 1, TMModLocked = 2 };

// Панель над клавиатурой: Esc, Tab, залипающие Ctrl/Alt, стрелки с автоповтором, символы, ряд F1–F12
@interface TMExtraKeysBar : UIView
@property (nonatomic, weak) id<TMExtraKeysBarDelegate> delegate;
@property (nonatomic, readonly) TMModState ctrl, alt;
- (void)consumeModifiers;   // после использования сбрасывает одноразовые Ctrl/Alt
- (void)applyBackground:(UIColor *)bg foreground:(UIColor *)fg accent:(UIColor *)accent lock:(UIColor *)lock;
@property (nonatomic) BOOL interactive;   // NO — только для предпросмотра в редакторе
@end
