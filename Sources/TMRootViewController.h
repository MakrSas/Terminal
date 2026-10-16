#import "TMCommon.h"
@interface TMRootViewController : UIViewController
- (void)newTabRoot:(BOOL)root;
- (void)debugSendText:(NSString *)text;
- (NSString *)debugVisibleText;
- (void)debugUI:(NSString *)cmd;      // только для отладочной сборки
@end
