#import "TMCommon.h"

typedef NS_ENUM(NSInteger, TMKeyKind) { TMKeyKindUsage, TMKeyKindText, TMKeyKindCtrl, TMKeyKindAlt, TMKeyKindPaste, TMKeyKindFn };

// Описание клавиши панели над клавиатурой
@interface TMKeyDef : NSObject
@property (nonatomic, copy) NSString *ident;     // стабильный идентификатор для настроек
@property (nonatomic, copy) NSString *title;     // подпись на кнопке
@property (nonatomic, copy) NSString *group;     // раздел в каталоге
@property (nonatomic) TMKeyKind kind;
@property (nonatomic) UIKeyboardHIDUsage usage;
@property (nonatomic, copy) NSString *text;      // что отправить (для текстовых клавиш)
@property (nonatomic) BOOL repeats;
@end

// Набор клавиш панели хранится в настройках как массив словарей: {id} для клавиш каталога, {id:"custom", label, text} для своих
@interface TMKeyBarConfig : NSObject
+ (NSArray<TMKeyDef *> *)catalog;                          // все готовые клавиши
+ (NSArray<NSString *> *)groups;                           // порядок разделов каталога
+ (NSArray<NSDictionary *> *)defaultItems;
+ (TMKeyDef *)defForItem:(NSDictionary *)item;             // nil, если клавиши нет в каталоге
+ (NSString *)titleForItem:(NSDictionary *)item;
+ (NSString *)detailForItem:(NSDictionary *)item;
// «\e», «\t», «\r», «\n», «\\», «\xNN», «^C» → байты
+ (NSString *)expandEscapes:(NSString *)s;
@end
