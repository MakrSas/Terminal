#import "TMRootViewController.h"
#import "TMTabBar.h"
#import "TMTerminalView.h"
#import "TMSession.h"
#import "TMSettings.h"
#import "TMThemes.h"
#import "TMSettingsViewController.h"
#import "TMKeyBarEditorViewController.h"

@interface TMTab : NSObject
@property (nonatomic, strong) TMSession *session;
@property (nonatomic, strong) TMTerminalView *view;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL exited;
@end
@implementation TMTab
@end

@interface TMRootViewController () <TMTabBarDelegate, TMTerminalViewDelegate, TMSessionDelegate>
@end

@implementation TMRootViewController {
    TMTabBar *_tabBar;
    UIView *_content, *_topBack;
    NSMutableArray<TMTab *> *_tabs;
    NSInteger _selected;
    NSLayoutConstraint *_bottom;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _tabs = [NSMutableArray array];
    _tabBar = [TMTabBar new]; _tabBar.delegate = self; _tabBar.translatesAutoresizingMaskIntoConstraints = NO;
    _content = [UIView new]; _content.translatesAutoresizingMaskIntoConstraints = NO;
    _topBack = [UIView new]; _topBack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_content]; [self.view addSubview:_topBack]; [self.view addSubview:_tabBar];
    _bottom = [_content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_topBack.topAnchor constraintEqualToAnchor:self.view.topAnchor], [_topBack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_topBack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [_topBack.bottomAnchor constraintEqualToAnchor:_tabBar.bottomAnchor],
        [_tabBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tabBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tabBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tabBar.heightAnchor constraintEqualToConstant:44],
        [_content.topAnchor constraintEqualToAnchor:_tabBar.bottomAnchor],
        [_content.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_content.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        _bottom]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:TM_DEFAULTS_CHANGED object:nil];
    [self settingsChanged];
    [self newTabRoot:[TMSettings shared].startAsRoot];
}

#pragma mark - Оформление и клавиатура

- (TMTheme *)theme { return [TMTheme themeNamed:[TMSettings shared].themeName]; }
- (UIStatusBarStyle)preferredStatusBarStyle { return [self theme].light ? UIStatusBarStyleDarkContent : UIStatusBarStyleLightContent; }

- (void)settingsChanged {
    TMTheme *t = [self theme];
    self.view.backgroundColor = TMHex(t.background);
    UIColor *chrome = TMHex(t.chromeBackground);
    _topBack.backgroundColor = chrome;
    [_tabBar applyBackground:chrome foreground:TMHex(t.foreground) accent:TMHex(t.accent)];
    for (TMTab *tab in _tabs) [tab.view applySettings];
    [UIApplication sharedApplication].idleTimerDisabled = [TMSettings shared].keepAwake;
    [self setNeedsStatusBarAppearanceUpdate];
    self.overrideUserInterfaceStyle = t.light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}

- (void)keyboardChanged:(NSNotification *)n {
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - local.origin.y);
    _bottom.constant = -overlap;
    double dur = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur delay:0 options:[n.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16 animations:^{ [self.view layoutIfNeeded]; } completion:nil];
}

#pragma mark - Вкладки

- (TMTab *)current { return _selected >= 0 && _selected < (NSInteger)_tabs.count ? _tabs[_selected] : nil; }

- (void)newTabRoot:(BOOL)root {
    TMTab *tab = [TMTab new];
    tab.session = [[TMSession alloc] initWithRoot:root]; tab.session.delegate = self;
    tab.view = [[TMTerminalView alloc] initWithFrame:_content.bounds];
    tab.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tab.view.delegate = self; tab.view.hidden = YES;
    tab.title = root ? @"root" : @"mobile";
    [_content addSubview:tab.view];
    [_tabs addObject:tab];
    [self selectTab:(NSInteger)_tabs.count - 1];
}

- (void)selectTab:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_tabs.count) return;
    _selected = i;
    for (NSInteger k = 0; k < (NSInteger)_tabs.count; k++) _tabs[k].view.hidden = k != i;
    [self refreshTabBar];
    [_tabs[i].view applySettings];
    [_tabs[i].view showKeyboard];
}

- (void)refreshTabBar {
    NSMutableArray *titles = [NSMutableArray array], *roots = [NSMutableArray array];
    for (TMTab *t in _tabs) { [titles addObject:t.title]; [roots addObject:@(t.session.root)]; }
    [_tabBar setTitles:titles roots:roots selected:_selected];
}

- (TMTab *)tabForView:(TMTerminalView *)v { for (TMTab *t in _tabs) if (t.view == v) return t; return nil; }
- (TMTab *)tabForSession:(TMSession *)s { for (TMTab *t in _tabs) if (t.session == s) return t; return nil; }

- (void)closeTabAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_tabs.count) return;
    TMTab *t = _tabs[i];
    [t.session terminate]; t.session.delegate = nil; t.view.delegate = nil;
    [t.view removeFromSuperview];
    [_tabs removeObjectAtIndex:i];
    if (_tabs.count == 0) { [self newTabRoot:[TMSettings shared].startAsRoot]; return; }
    [self selectTab:MIN(i, (NSInteger)_tabs.count - 1)];
}

#pragma mark - TMTabBarDelegate

- (void)tabBarSelect:(NSInteger)index { [self selectTab:index]; }
- (void)tabBarClose:(NSInteger)index { [self closeTabAtIndex:index]; }
- (void)tabBarNewTab { [self newTabRoot:[TMSettings shared].startAsRoot]; }
- (void)tabBarNewTabRoot:(BOOL)root { [self newTabRoot:root]; }
- (void)tabBarOpenSettings {
    TMSettingsViewController *vc = [TMSettingsViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.overrideUserInterfaceStyle = [self theme].light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - TMTerminalViewDelegate

- (void)terminalViewReady:(TMTerminalView *)view {
    TMTab *t = [self tabForView:view];
    if (!t || t.session.running) return;
    NSString *err = nil;
    TMLog(@"ready: %dx%d, starting session root=%d", view.cols, view.rows, t.session.root);
    if (![t.session startWithCols:view.cols rows:view.rows error:&err]) {
        NSString *msg = [NSString stringWithFormat:@"\x1b[31m%@\x1b[0m\r\n%@\r\n", TMT(@"Could not start the shell", @"Не удалось запустить оболочку"), err ?: @""];
        [view writeOutput:[msg dataUsingEncoding:NSUTF8StringEncoding]];
        t.exited = YES;
    } else { t.title = t.session.shellName; [self refreshTabBar]; }
}

- (void)terminalView:(TMTerminalView *)view sendData:(NSData *)data {
    TMTab *t = [self tabForView:view];
    if (t.exited) {   // после завершения любая клавиша закрывает вкладку
        [self closeTabAtIndex:[_tabs indexOfObject:t]];
        return;
    }
    [t.session writeData:data];
}

- (void)terminalView:(TMTerminalView *)view resizedToCols:(int)cols rows:(int)rows {
    [[self tabForView:view].session resizeCols:cols rows:rows];
}

- (void)terminalView:(TMTerminalView *)view titleChanged:(NSString *)title {
    TMTab *t = [self tabForView:view];
    if (title.length) { t.title = title; [self refreshTabBar]; }
}

#pragma mark - TMSessionDelegate

- (void)session:(TMSession *)s didReceiveData:(NSData *)data { [[self tabForSession:s].view writeOutput:data]; }

- (void)session:(TMSession *)s didExitWithStatus:(int)status {
    TMTab *t = [self tabForSession:s];
    if (!t) return;
    if (status == 0) { [self closeTabAtIndex:[_tabs indexOfObject:t]]; return; }
    t.exited = YES;
    NSString *msg = [NSString stringWithFormat:@"\r\n\x1b[2m[%@ %d — %@]\x1b[0m\r\n", TMT(@"process exited with code", @"процесс завершился с кодом"), status, TMT(@"press any key to close", @"нажмите любую клавишу, чтобы закрыть")];
    [t.view writeOutput:[msg dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Горячие клавиши

- (NSArray<UIKeyCommand *> *)keyCommands {
    NSMutableArray *a = [NSMutableArray array];
    UIKeyCommand *(^k)(NSString *, UIKeyModifierFlags, SEL, NSString *) = ^UIKeyCommand *(NSString *in, UIKeyModifierFlags m, SEL s, NSString *title) {
        UIKeyCommand *c = [UIKeyCommand commandWithTitle:title image:nil action:s input:in modifierFlags:m propertyList:nil];
        c.wantsPriorityOverSystemBehavior = YES; return c;
    };
    UIKeyCommand *(^kp)(NSString *, UIKeyModifierFlags, SEL, NSString *, id) = ^UIKeyCommand *(NSString *in, UIKeyModifierFlags m, SEL s, NSString *title, id plist) {
        UIKeyCommand *c = [UIKeyCommand commandWithTitle:title image:nil action:s input:in modifierFlags:m propertyList:plist];
        c.wantsPriorityOverSystemBehavior = YES; return c;
    };
    [a addObject:k(@"t", UIKeyModifierCommand, @selector(cmdNewTab), TMT(@"New tab", @"Новая вкладка"))];
    [a addObject:k(@"t", UIKeyModifierCommand | UIKeyModifierShift, @selector(cmdNewRootTab), TMT(@"New root tab", @"Новая вкладка root"))];
    [a addObject:k(@"w", UIKeyModifierCommand, @selector(cmdCloseTab), TMT(@"Close tab", @"Закрыть вкладку"))];
    [a addObject:k(@"k", UIKeyModifierCommand, @selector(cmdClear), TMT(@"Clear", @"Очистить"))];
    [a addObject:k(@"=", UIKeyModifierCommand, @selector(cmdBigger), TMT(@"Bigger font", @"Крупнее шрифт"))];
    [a addObject:k(@"-", UIKeyModifierCommand, @selector(cmdSmaller), TMT(@"Smaller font", @"Мельче шрифт"))];
    [a addObject:k(@"0", UIKeyModifierCommand, @selector(cmdResetFont), TMT(@"Default font size", @"Размер шрифта по умолчанию"))];
    [a addObject:k(@",", UIKeyModifierCommand, @selector(tabBarOpenSettings), TMT(@"Settings", @"Настройки"))];
    [a addObject:k(@"]", UIKeyModifierCommand | UIKeyModifierShift, @selector(cmdNext), TMT(@"Next tab", @"Следующая вкладка"))];
    [a addObject:k(@"[", UIKeyModifierCommand | UIKeyModifierShift, @selector(cmdPrev), TMT(@"Previous tab", @"Предыдущая вкладка"))];
    for (int i = 1; i <= 9; i++) {
        [a addObject:kp([NSString stringWithFormat:@"%d", i], UIKeyModifierCommand, @selector(cmdGoto:), [NSString stringWithFormat:TMT(@"Tab %d", @"Вкладка %d"), i], @(i - 1))];
    }
    return a;
}
- (void)cmdNewTab { [self newTabRoot:[TMSettings shared].startAsRoot]; }
- (void)cmdNewRootTab { [self newTabRoot:YES]; }
- (void)cmdCloseTab { [self closeTabAtIndex:_selected]; }
- (void)cmdClear { [[self current].view clearScreen]; }
- (void)cmdBigger { [TMSettings shared].fontSize += 1; }
- (void)cmdSmaller { [TMSettings shared].fontSize -= 1; }
- (void)cmdResetFont { [TMSettings shared].fontSize = 13; }
- (void)cmdNext { [self selectTab:(_selected + 1) % (NSInteger)_tabs.count]; }
- (void)cmdPrev { [self selectTab:(_selected + (NSInteger)_tabs.count - 1) % (NSInteger)_tabs.count]; }
- (void)cmdGoto:(UIKeyCommand *)c { [self selectTab:[c.propertyList integerValue]]; }

- (void)debugSendText:(NSString *)text { [[self current].view sendString:text]; }
- (void)debugUI:(NSString *)cmd {
    if ([cmd isEqualToString:@"dismiss"]) { [self dismissViewControllerAnimated:NO completion:nil]; return; }
    if ([cmd hasPrefix:@"theme "]) { [TMSettings shared].themeName = [cmd substringFromIndex:6]; return; }
    UINavigationController *nav;
    if ([cmd isEqualToString:@"keyeditor"]) { nav = [[UINavigationController alloc] initWithRootViewController:[TMKeyBarEditorViewController new]]; }
    else { nav = [[UINavigationController alloc] initWithRootViewController:[TMSettingsViewController new]]; }
    nav.overrideUserInterfaceStyle = [self theme].light ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:NO completion:nil];
}
- (NSString *)debugVisibleText { return [[self current].view visibleText]; }

@end
