#import "TMSettingsViewController.h"
#import "TMSettings.h"
#import "TMThemes.h"
#import "TMKeyBarEditorViewController.h"

// Список выбора с галочкой
@interface TMPickerViewController : UITableViewController
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray *values;
@property (nonatomic, copy) id (^current)(void);
@property (nonatomic, copy) void (^choose)(id value);
@property (nonatomic, copy) UIView *(^accessory)(NSInteger row);
@end
@implementation TMPickerViewController
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.titles.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.textLabel.text = self.titles[ip.row];
    c.accessoryType = [self.values[ip.row] isEqual:self.current()] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.accessoryView = nil;
    if (self.accessory) { UIView *v = self.accessory(ip.row); if (v) { c.accessoryView = v; } }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    self.choose(self.values[ip.row]);
    [t reloadData];
    [t deselectRowAtIndexPath:ip animated:YES];
}
@end

// Ряд цветных точек — превью темы
@interface TMSwatch : UIView
@property (nonatomic, strong) TMTheme *theme;
@end
@implementation TMSwatch
- (void)drawRect:(CGRect)r {
    [TMHex(self.theme.background) setFill]; [[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:6] fill];
    CGFloat x = 6;
    for (int i = 1; i < 7; i++) { [TMHex((uint32_t)[self.theme.ansi[i] unsignedIntValue]) setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x, 8, 8, 8)] fill]; x += 12; }
}
@end

@implementation TMSettingsViewController {
    NSArray<NSArray *> *_rows;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TMT(@"Settings", @"Настройки");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSArray<NSString *> *)sectionTitles { return @[TMT(@"Appearance", @"Оформление"), TMT(@"Terminal", @"Терминал"), TMT(@"About", @"О программе")]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return [self sectionTitles][s]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (s == 1) return TMT(@"Root tabs run the shell as the superuser. Be careful with commands.", @"Вкладки root запускают оболочку от суперпользователя. Осторожнее с командами.");
    if (s == 2) return TMT(@"⚠️ Vibe-coded: written almost entirely by an AI assistant (Claude), not audited. Use at your own risk.", @"⚠️ Вайбкод: написано почти целиком ИИ-ассистентом (Claude), не аудировано. На свой страх и риск.");
    return nil;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? 5 : s == 1 ? 6 : 2; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    TMSettings *st = [TMSettings shared];
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.accessoryView = nil; c.accessoryType = UITableViewCellAccessoryNone;
    void (^sw)(NSString *, BOOL, SEL) = ^(NSString *title, BOOL on, SEL a) {
        c.textLabel.text = title; UISwitch *s = [UISwitch new]; s.on = on; [s addTarget:self action:a forControlEvents:UIControlEventValueChanged]; c.accessoryView = s; c.selectionStyle = UITableViewCellSelectionStyleNone;
    };
    void (^nav)(NSString *, NSString *) = ^(NSString *title, NSString *detail) {
        c.textLabel.text = title; c.detailTextLabel.text = detail; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    };
    if (ip.section == 0) {
        switch (ip.row) {
            case 0: nav(TMT(@"Theme", @"Тема"), st.themeName); break;
            case 1: nav(TMT(@"Font", @"Шрифт"), st.fontFamily); break;
            case 2: {
                c.textLabel.text = TMT(@"Font size", @"Размер шрифта"); c.detailTextLabel.text = [NSString stringWithFormat:@"%g", st.fontSize];
                UIStepper *s = [UIStepper new]; s.minimumValue = 8; s.maximumValue = 32; s.stepValue = 0.5; s.value = st.fontSize;
                [s addTarget:self action:@selector(sizeStep:) forControlEvents:UIControlEventValueChanged];
                c.accessoryView = s; c.selectionStyle = UITableViewCellSelectionStyleNone; break; }
            case 3: nav(TMT(@"Cursor", @"Курсор"), st.cursorStyle == TMCursorBar ? TMT(@"Bar", @"Линия") : st.cursorStyle == TMCursorUnderline ? TMT(@"Underline", @"Подчёркивание") : TMT(@"Block", @"Блок")); break;
            default: sw(TMT(@"Blinking cursor", @"Мигающий курсор"), st.cursorBlink, @selector(blinkChanged:)); break;
        }
    } else if (ip.section == 1) {
        switch (ip.row) {
            case 0: nav(TMT(@"Shell", @"Оболочка"), [st.shell isEqualToString:@"auto"] ? TMT(@"Automatic", @"Автоматически") : st.shell.lastPathComponent); break;
            case 1: sw(TMT(@"New tabs as root", @"Новые вкладки от root"), st.startAsRoot, @selector(rootChanged:)); break;
            case 2: nav(TMT(@"Scrollback", @"История"), [NSString stringWithFormat:@"%ld", (long)st.scrollback]); break;
            case 3: sw(TMT(@"Haptic bell", @"Вибро при звонке"), st.hapticBell, @selector(hapticChanged:)); break;
            case 4: sw(TMT(@"Keep screen on", @"Не гасить экран"), st.keepAwake, @selector(awakeChanged:)); break;
            default: nav(TMT(@"Key bar", @"Панель клавиш"), [NSString stringWithFormat:@"%lu", (unsigned long)st.keyBarItems.count]); break;
        }
    } else {
        if (ip.row == 0) { c.textLabel.text = TMT(@"Version", @"Версия"); c.detailTextLabel.text = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"]; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        else nav(@"GitHub", @"MakrSas/Terminal");
    }
    return c;
}

- (void)sizeStep:(UIStepper *)s { [TMSettings shared].fontSize = s.value; [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)blinkChanged:(UISwitch *)s { [TMSettings shared].cursorBlink = s.on; }
- (void)rootChanged:(UISwitch *)s { [TMSettings shared].startAsRoot = s.on; }
- (void)hapticChanged:(UISwitch *)s { [TMSettings shared].hapticBell = s.on; }
- (void)awakeChanged:(UISwitch *)s { [TMSettings shared].keepAwake = s.on; }

- (void)push:(NSString *)title titles:(NSArray *)titles values:(NSArray *)values current:(id (^)(void))cur choose:(void (^)(id))choose accessory:(UIView *(^)(NSInteger))acc {
    TMPickerViewController *p = [[TMPickerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    p.title = title; p.titles = titles; p.values = values; p.current = cur; p.choose = ^(id v) { choose(v); [self.tableView reloadData]; }; p.accessory = acc;
    [self.navigationController pushViewController:p animated:YES];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    TMSettings *st = [TMSettings shared];
    if (ip.section == 0 && ip.row == 0) {
        NSArray *themes = [TMTheme all]; NSMutableArray *names = [NSMutableArray array];
        for (TMTheme *th in themes) [names addObject:th.name];
        [self push:TMT(@"Theme", @"Тема") titles:names values:names current:^id { return st.themeName; } choose:^(id v) { st.themeName = v; }
         accessory:^UIView *(NSInteger r) { TMSwatch *s = [[TMSwatch alloc] initWithFrame:CGRectMake(0, 0, 84, 24)]; s.theme = themes[r]; s.backgroundColor = UIColor.clearColor; return s; }];
    } else if (ip.section == 0 && ip.row == 1) {
        NSArray *f = @[@"JetBrains Mono", @"Menlo", @"SF Mono"];
        [self push:TMT(@"Font", @"Шрифт") titles:f values:f current:^id { return st.fontFamily; } choose:^(id v) { st.fontFamily = v; } accessory:nil];
    } else if (ip.section == 0 && ip.row == 3) {
        [self push:TMT(@"Cursor", @"Курсор") titles:@[TMT(@"Block", @"Блок"), TMT(@"Bar", @"Линия"), TMT(@"Underline", @"Подчёркивание")] values:@[@0, @1, @2]
           current:^id { return @(st.cursorStyle); } choose:^(id v) { st.cursorStyle = (TMCursorStyle)[v integerValue]; } accessory:nil];
    } else if (ip.section == 1 && ip.row == 0) {
        NSMutableArray *titles = [@[TMT(@"Automatic", @"Автоматически")] mutableCopy], *vals = [@[@"auto"] mutableCopy];
        for (NSString *p in [TMSettings availableShells]) { [titles addObject:p]; [vals addObject:p]; }
        [self push:TMT(@"Shell", @"Оболочка") titles:titles values:vals current:^id { return st.shell; } choose:^(id v) { st.shell = v; } accessory:nil];
    } else if (ip.section == 1 && ip.row == 2) {
        [self push:TMT(@"Scrollback", @"История") titles:@[@"1000", @"5000", @"10000", @"50000"] values:@[@1000, @5000, @10000, @50000]
           current:^id { return @(st.scrollback); } choose:^(id v) { st.scrollback = [v integerValue]; } accessory:nil];
    } else if (ip.section == 1 && ip.row == 5) {
        [self.navigationController pushViewController:[TMKeyBarEditorViewController new] animated:YES];
    } else if (ip.section == 2 && ip.row == 1) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/MakrSas/Terminal"] options:@{} completionHandler:nil];
    }
}

@end
