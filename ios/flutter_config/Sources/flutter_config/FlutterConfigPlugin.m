#import "./include/flutter_config/FlutterConfigPlugin.h"

#if __has_include("GeneratedDotEnv.m")
#import "GeneratedDotEnv.m" // written during build by BuildDotenvConfig.ruby
#endif

@implementation FlutterConfigPlugin

static NSDictionary *_cachedEnv = nil;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"flutter_config"
            binaryMessenger:[registrar messenger]];
  FlutterConfigPlugin* instance = [[FlutterConfigPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

+ (NSDictionary *)env {
#ifdef DOT_ENV
    NSDictionary *compileTimeEnv = (NSDictionary *)DOT_ENV;
    if (compileTimeEnv != nil && [compileTimeEnv count] > 0) {
        return compileTimeEnv;
    }
#endif
    @synchronized (self) {
        if (_cachedEnv != nil) {
            return _cachedEnv;
        }
        _cachedEnv = [self loadEnvFromBundle];
        return _cachedEnv;
    }
}

+ (NSString *)envFor: (NSString *)key {
    NSString *value = (NSString *)[self.env objectForKey:key];
    return value;
}

- (NSDictionary *)constantsToExport {
    return [FlutterConfigPlugin env];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"loadEnvVariables" isEqualToString:call.method]) {
      NSDictionary *variables = [FlutterConfigPlugin env];
      result(variables);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

+ (NSDictionary *)loadEnvFromBundle {
    NSBundle *bundle = [NSBundle mainBundle];

    // 1. Check for GeneratedDotEnv.plist in bundle (generated at build time without raw .env exposure)
    NSString *plistPath = [self resolveBundlePath:@"GeneratedDotEnv.plist" bundle:bundle];
    if (plistPath != nil) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (dict != nil && [dict count] > 0) {
            return dict;
        }
    }

    NSString *defaultEnvFile = @".env";
    NSString *envFileName = nil;

    // 2. Check Info.plist for custom env filename
    NSString *infoPlistEnv = [bundle objectForInfoDictionaryKey:@"FlutterConfigEnvFile"];
    if (infoPlistEnv != nil && [infoPlistEnv length] > 0) {
        envFileName = [infoPlistEnv stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    // 2. Check for .envfile in bundle or flutter_assets
    if (envFileName == nil) {
        NSString *envFilePath = [self resolveBundlePath:@".envfile" bundle:bundle];
        if (envFilePath != nil) {
            NSError *readError = nil;
            NSString *customName = [NSString stringWithContentsOfFile:envFilePath encoding:NSUTF8StringEncoding error:&readError];
            if (customName != nil) {
                customName = [customName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([customName length] > 0) {
                    envFileName = customName;
                }
            }
        }
    }

    if (envFileName == nil) {
        envFileName = defaultEnvFile;
    }

    // 3. Locate the env file in the bundle
    NSString *targetPath = [self resolveBundlePath:envFileName bundle:bundle];
    if (targetPath == nil) {
        // Fallback: try .env if custom env file was not found
        if (![envFileName isEqualToString:defaultEnvFile]) {
            targetPath = [self resolveBundlePath:defaultEnvFile bundle:bundle];
        }
    }

    if (targetPath == nil) {
        NSLog(@"[FlutterConfig] Warning: Could not locate GeneratedDotEnv.plist or '%@' in app bundle. If using Swift Package Manager, ensure GeneratedDotEnv.plist is generated in Xcode Pre-actions and added to Copy Bundle Resources.", envFileName);
        return @{};
    }

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:targetPath encoding:NSUTF8StringEncoding error:&error];
    if (error != nil || content == nil) {
        NSLog(@"[FlutterConfig] Error reading '%@': %@", targetPath, error.localizedDescription);
        return @{};
    }

    return [self parseDotEnvString:content];
}

+ (NSString *)resolveBundlePath:(NSString *)filename bundle:(NSBundle *)bundle {
    // 1. Direct path in main bundle
    NSString *path = [bundle pathForResource:filename ofType:nil];
    if (path != nil && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return path;
    }

    // 2. Inside flutter_assets/
    NSString *assetPath = [bundle pathForResource:filename ofType:nil inDirectory:@"flutter_assets"];
    if (assetPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:assetPath]) {
        return assetPath;
    }

    // 3. App.framework/flutter_assets/ (older Flutter or custom framework bundles)
    NSString *frameworkPath = [[bundle bundlePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"Frameworks/App.framework/flutter_assets/%@", filename]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworkPath]) {
        return frameworkPath;
    }

    return nil;
}

+ (NSDictionary *)parseDotEnvString:(NSString *)content {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // Regex pattern matching: ^(?:export\s+|)([a-zA-Z0-9_]+)=(.*)$
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(?:export\\s+|)([a-zA-Z0-9_]+)=(.*)$" options:0 error:nil];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line length] == 0 || [line hasPrefix:@"#"]) {
            continue;
        }

        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, [line length])];
        if (match && [match numberOfRanges] >= 3) {
            NSString *key = [line substringWithRange:[match rangeAtIndex:1]];
            NSString *val = [line substringWithRange:[match rangeAtIndex:2]];

            // Strip enclosing quotes if present: "val" or 'val'
            val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([val length] >= 2) {
                unichar firstChar = [val characterAtIndex:0];
                unichar lastChar = [val characterAtIndex:[val length] - 1];
                if ((firstChar == '"' && lastChar == '"') || (firstChar == '\'' && lastChar == '\'')) {
                    val = [val substringWithRange:NSMakeRange(1, [val length] - 2)];
                }
            }

            [dict setObject:val forKey:key];
        }
    }

    return [NSDictionary dictionaryWithDictionary:dict];
}

@end
