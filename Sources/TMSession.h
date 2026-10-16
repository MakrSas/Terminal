#import "TMCommon.h"

@class TMSession;
@protocol TMSessionDelegate <NSObject>
- (void)session:(TMSession *)session didReceiveData:(NSData *)data;
- (void)session:(TMSession *)session didExitWithStatus:(int)status;
@end

// Одна оболочка на псевдотерминале. Запускается через mtsh (setuid root): режим root или user.
@interface TMSession : NSObject
@property (nonatomic, weak) id<TMSessionDelegate> delegate;
@property (nonatomic, readonly) BOOL root;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) pid_t pid;
@property (nonatomic, readonly) NSString *shellName;
- (instancetype)initWithRoot:(BOOL)root;
// Запуск с начальным размером; error — понятное пользователю сообщение
- (BOOL)startWithCols:(int)cols rows:(int)rows error:(NSString **)error;
- (void)writeData:(NSData *)data;
- (void)resizeCols:(int)cols rows:(int)rows;
- (void)terminate;
@end
