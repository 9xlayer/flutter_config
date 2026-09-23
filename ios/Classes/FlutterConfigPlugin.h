#import <Foundation/Foundation.h>

#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
#elif __has_include("Flutter.h")
#import "Flutter.h"
#else
NS_ASSUME_NONNULL_BEGIN

@protocol FlutterBinaryMessenger <NSObject>
@end

@protocol FlutterPluginRegistrar <NSObject>
- (NSObject<FlutterBinaryMessenger> *)messenger;
- (void)addMethodCallDelegate:(id)delegate channel:(id)channel;
@end

@protocol FlutterPlugin <NSObject>
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end

@interface FlutterMethodCall : NSObject
@property(nonatomic, readonly) NSString *method;
@property(nonatomic, readonly, nullable) id arguments;
@end

typedef void (^FlutterResult)(id _Nullable result);

extern id const FlutterMethodNotImplemented;

@interface FlutterMethodChannel : NSObject
+ (instancetype)methodChannelWithName:(NSString *)name
                      binaryMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (void)invokeMethod:(NSString *)method arguments:(id _Nullable)arguments;
@end

NS_ASSUME_NONNULL_END
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FlutterConfigPlugin : NSObject<FlutterPlugin>
+ (NSDictionary *)env;
+ (NSString *)envFor:(NSString *)key;
@end

NS_ASSUME_NONNULL_END

