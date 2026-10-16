#import "TMCommon.h"

@class TMTerminalView, TMExtraKeysBar;
@protocol TMTerminalViewDelegate <NSObject>
- (void)terminalViewReady:(TMTerminalView *)view;                         // первая раскладка: размер сетки известен
- (void)terminalView:(TMTerminalView *)view sendData:(NSData *)data;      // ввод пользователя и ответы терминала
- (void)terminalView:(TMTerminalView *)view resizedToCols:(int)cols rows:(int)rows;
- (void)terminalView:(TMTerminalView *)view titleChanged:(NSString *)title;
@end

// Экран терминала: собственный эмулятор (TMEmu) и отрисовка Core Text; нативный ввод, выделение, прокрутка, мышь, масштаб жестом
@interface TMTerminalView : UIView <UIKeyInput, UITextInputTraits>
@property (nonatomic, weak) id<TMTerminalViewDelegate> delegate;
@property (nonatomic, strong, readonly) TMExtraKeysBar *extraKeys;   // панель над клавиатурой
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) int cols, rows;
- (void)writeOutput:(NSData *)data;
- (void)applySettings;
- (void)sendString:(NSString *)s;               // как ввод пользователя (с учётом залипших Ctrl/Alt)
- (void)sendKey:(UIKeyboardHIDUsage)usage modifiers:(UIKeyModifierFlags)mods;
- (void)pasteFromPasteboard;
- (void)copySelection;
- (void)clearScreen;
- (BOOL)findText:(NSString *)q forward:(BOOL)fwd;
- (void)showKeyboard;
- (void)hideKeyboard;
- (NSString *)visibleText;                       // для отладки и тестов
@end
