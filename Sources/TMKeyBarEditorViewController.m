#import "TMKeyBarEditorViewController.h"
#import "TMKeyBarConfig.h"
#import "TMSettings.h"
#import "TMThemes.h"
#import "TMExtraKeysBar.h"

// Выбор готовых клавиш из каталога: нажатие добавляет клавишу в конец или убирает её
@interface TMKeyPickerViewController : UITableViewController
@end
@implementation TMKeyPickerViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = TMT(@"Add key", @"Добавить клавишу"); }
- (NSString *)groupTitle:(NSString *)g {
    NSDictionary *n = @{@"mod": TMT(@"Basic", @"Основные"), @"nav": TMT(@"Navigation", @"Навигация"), @"fn": TMT(@"Function keys", @"Функциональные"),
                        @"sym": TMT(@"Symbols", @"Символы"), @"ctl": TMT(@"Ctrl combinations", @"Сочетания Ctrl"), @"act": TMT(@"Actions", @"Действия")};
    return n[g];
}
- (NSArray<TMKeyDef *> *)defsIn:(NSInteger)section {
    NSString *g = [TMKeyBarConfig groups][section]; NSMutableArray *a = [NSMutableArray array];
    for (TMKeyDef *d in [TMKeyBarConfig catalog]) if ([d.group isEqualToString:g]) [a addObject:d];
    return a;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return (NSInteger)[TMKeyBarConfig groups].count; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return [self groupTitle:[TMKeyBarConfig groups][s]]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)[self defsIn:s].count; }
- (BOOL)isUsed:(NSString *)ident { for (NSDictionary *i in [TMSettings shared].keyBarItems) if ([i[@"id"] isEqualToString:ident]) return YES; return NO; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    TMKeyDef *d = [self defsIn:ip.section][ip.row];
    c.textLabel.text = d.title; c.textLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightMedium];
    c.detailTextLabel.text = d.ident;
    c.accessoryType = [self isUsed:d.ident] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    TMKeyDef *d = [self defsIn:ip.section][ip.row];
    NSMutableArray *items = [[TMSettings shared].keyBarItems mutableCopy];
    if ([self isUsed:d.ident]) { NSIndexSet *rm = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *i, NSUInteger k, BOOL *s) { return [i[@"id"] isEqualToString:d.ident]; }]; [items removeObjectsAtIndexes:rm]; }
    else [items addObject:@{@"id": d.ident}];
    [TMSettings shared].keyBarItems = items;
    [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
    [t deselectRowAtIndexPath:ip animated:YES];
}
@end

@implementation TMKeyBarEditorViewController {
    NSMutableArray<NSDictionary *> *_items;
    TMExtraKeysBar *_preview;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TMT(@"Key bar", @"Панель клавиш");
    [self.tableView setEditing:YES animated:NO];
    self.tableView.allowsSelectionDuringEditing = YES;
    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 62)];
    _preview = [[TMExtraKeysBar alloc] initWithFrame:CGRectMake(0, 8, 100, 46)];
    _preview.interactive = NO; _preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _preview.layer.cornerRadius = 10; _preview.clipsToBounds = YES;
    [head addSubview:_preview];
    self.tableView.tableHeaderView = head;
    [self reload];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:TM_DEFAULTS_CHANGED object:nil];
    [self themeChanged];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat inset = 16; _preview.frame = CGRectMake(inset, 8, self.tableView.bounds.size.width - 2 * inset, 46);
}
- (void)themeChanged {
    TMTheme *t = [TMTheme themeNamed:[TMSettings shared].themeName];
    [_preview applyBackground:TMHex(t.keyBarBackground) foreground:TMHex(t.foreground) accent:TMHex(t.accent) lock:TMHex(t.lockColor)];
}
- (void)reload { _items = [[TMSettings shared].keyBarItems mutableCopy]; [self.tableView reloadData]; }
- (void)save { [TMSettings shared].keyBarItems = _items; }
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self reload]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s == 0 ? TMT(@"Keys (drag to reorder)", @"Клавиши (перетащите, чтобы поменять порядок)") : nil; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return s == 1 ? TMT(@"A custom key sends text. Use \\e for Esc, \\t Tab, \\r Enter, ^C for Ctrl+C, \\x03 for a byte.", @"Своя клавиша отправляет текст. \\e — Esc, \\t — Tab, \\r — Enter, ^C — Ctrl+C, \\x03 — байт.") : nil;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? (NSInteger)_items.count : 3; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (ip.section == 0) {
        NSDictionary *it = _items[ip.row];
        c.textLabel.text = [TMKeyBarConfig titleForItem:it]; c.textLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightMedium];
        c.detailTextLabel.text = [TMKeyBarConfig detailForItem:it]; c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        if ([it[@"id"] isEqualToString:@"custom"]) c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSArray *titles = @[TMT(@"Add key from list…", @"Добавить клавишу из списка…"), TMT(@"Add custom key…", @"Добавить свою клавишу…"), TMT(@"Reset to default", @"Сбросить по умолчанию")];
        c.textLabel.text = titles[ip.row];
        c.textLabel.textColor = ip.row == 2 ? UIColor.systemRedColor : self.view.tintColor;
    }
    return c;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)t editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)t shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 0; }
- (BOOL)tableView:(UITableView *)t canMoveRowAtIndexPath:(NSIndexPath *)ip { return ip.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)t targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to { return to.section == 0 ? to : [NSIndexPath indexPathForRow:(NSInteger)_items.count - 1 inSection:0]; }
- (void)tableView:(UITableView *)t moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSDictionary *it = _items[from.row]; [_items removeObjectAtIndex:from.row]; [_items insertObject:it atIndex:to.row]; [self save];
}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    [_items removeObjectAtIndex:ip.row]; [self save];
    [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) { if ([_items[ip.row][@"id"] isEqualToString:@"custom"]) [self editCustomAt:ip.row]; return; }
    if (ip.row == 0) [self.navigationController pushViewController:[TMKeyPickerViewController new] animated:YES];
    else if (ip.row == 1) [self editCustomAt:-1];
    else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:TMT(@"Reset the key bar?", @"Сбросить панель клавиш?") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:TMT(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:TMT(@"Reset", @"Сбросить") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [TMSettings shared].keyBarItems = [TMKeyBarConfig defaultItems]; [self reload]; }]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

// Своя клавиша: подпись и текст; index < 0 — новая
- (void)editCustomAt:(NSInteger)index {
    NSDictionary *cur = index >= 0 ? _items[index] : nil;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:index >= 0 ? TMT(@"Edit key", @"Изменить клавишу") : TMT(@"New key", @"Новая клавиша") message:TMT(@"Label and text to send", @"Подпись и отправляемый текст") preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = TMT(@"Label", @"Подпись"); f.text = cur[@"label"]; f.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = TMT(@"Text, e.g. ls -la\\r or ^C", @"Текст, например ls -la\\r или ^C"); f.text = cur[@"text"]; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:TMT(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:TMT(@"Save", @"Сохранить") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *label = a.textFields[0].text, *text = a.textFields[1].text;
        if (!label.length || !text.length) return;
        NSDictionary *it = @{@"id": @"custom", @"label": label, @"text": text};
        if (index >= 0) _items[index] = it; else [_items addObject:it];
        [self save]; [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
