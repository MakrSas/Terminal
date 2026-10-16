#import "TMCommon.h"

@protocol TMTabBarDelegate <NSObject>
- (void)tabBarSelect:(NSInteger)index;
- (void)tabBarClose:(NSInteger)index;
- (void)tabBarNewTab;                       // «+»: режим по умолчанию
- (void)tabBarNewTabRoot:(BOOL)root;        // пункты меню: явно root или обычная
- (void)tabBarOpenSettings;
@end

// Полоса вкладок над терминалом: капсулы, «+» (долгое нажатие — меню root/user) и шестерёнка
@interface TMTabBar : UIView
@property (nonatomic, weak) id<TMTabBarDelegate> delegate;
- (void)setTitles:(NSArray<NSString *> *)titles roots:(NSArray<NSNumber *> *)roots selected:(NSInteger)selected;
- (void)applyBackground:(UIColor *)bg foreground:(UIColor *)fg accent:(UIColor *)accent;
@end
