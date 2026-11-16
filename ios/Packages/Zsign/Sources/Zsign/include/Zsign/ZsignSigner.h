#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Подпись распакованного `.app` на устройстве (zsign). Синхронно и небыстро — только не на главном потоке.
@interface ZsignSigner : NSObject

/// Переподписывает каждый Mach-O и вложенный бандл в `appPath` (папка `.app`) сертификатом из `p12Path`
/// и кладёт `provisionPath` внутрь. Entitlements — из профиля. nil — успех, иначе текст ошибки.
+ (NSString * _Nullable)signAppAtPath:(NSString *)appPath
                        provisionPath:(NSString *)provisionPath
                              p12Path:(NSString *)p12Path
                             password:(NSString *)password NS_SWIFT_NAME(sign(appPath:provisionPath:p12Path:password:));

/// Открывается ли `.p12` паролем и подходит ли к профилю — без подписи. nil — пара годится.
+ (NSString * _Nullable)checkProvisionPath:(NSString *)provisionPath
                                   p12Path:(NSString *)p12Path
                                  password:(NSString *)password NS_SWIFT_NAME(check(provisionPath:p12Path:password:));

@end

NS_ASSUME_NONNULL_END
