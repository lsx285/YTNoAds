#import "Headers.h"

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME      @"YouTube"

static NSString *accessGroupID() {
    static NSString *cachedID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *query = @{
            (__bridge NSString *)kSecClass:            (__bridge NSString *)kSecClassGenericPassword,
            (__bridge NSString *)kSecAttrAccount:      @"bundleSeedID",
            (__bridge NSString *)kSecAttrService:      @"",
            (__bridge NSString *)kSecReturnAttributes: @YES
        };
        CFDictionaryRef result = nil;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status == errSecItemNotFound)
            status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status == errSecSuccess)
            cachedID = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
        if (result) CFRelease(result);
    });
    return cachedID;
}

%hook YTVersionUtils
+ (NSString *)appName { return YT_NAME; }
+ (NSString *)appID   { return YT_BUNDLE_ID; }
%end

%hook GCKBUtils
+ (NSString *)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOClientLogin
+ (NSString *)defaultSourceString { return YT_BUNDLE_ID; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    [(NSObject *)self setValue:YT_NAME    forKey:@"_shortAppName"];
    [(NSObject *)self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
    return self;
}
%end

%hook YTHotConfig
- (BOOL)clientInfraClientConfigIosEnableFillingEncodedHacksInnertubeContext { return NO; }
%end

%hook NSBundle
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:YT_BUNDLE_ID]) return NSBundle.mainBundle;
    return %orig(identifier);
}
- (NSString *)bundleIdentifier {
    return [self isEqual:NSBundle.mainBundle] ? YT_BUNDLE_ID : %orig;
}
- (NSDictionary *)infoDictionary {
    if (![self isEqual:NSBundle.mainBundle]) return %orig;
    NSMutableDictionary *info = [%orig mutableCopy];
    info[@"CFBundleIdentifier"]  = YT_BUNDLE_ID;
    info[@"CFBundleDisplayName"] = YT_NAME;
    info[@"CFBundleName"]        = YT_NAME;
    return info;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (![self isEqual:NSBundle.mainBundle]) return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])                                    return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"]) return YT_NAME;
    return %orig;
}
%end

%hook SSOKeychainHelper
+ (id)accessGroup       { return accessGroupID(); }
+ (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOFolsomKeychainUtils
- (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook GULKeychainStorage
- (void)getObjectForKey:(id)key objectClass:(Class)cls accessGroup:(id)ag completionHandler:(id)handler {
    %orig(key, cls, accessGroupID(), handler);
}
- (void)setObject:(id)obj forKey:(id)key accessGroup:(id)ag completionHandler:(id)handler {
    %orig(obj, key, accessGroupID(), handler);
}
- (void)removeObjectForKey:(id)key accessGroup:(id)ag completionHandler:(id)handler {
    %orig(key, accessGroupID(), handler);
}
- (void)getObjectFromKeychainForKey:(id)key objectClass:(Class)cls accessGroup:(id)ag completionHandler:(id)handler {
    %orig(key, cls, accessGroupID(), handler);
}
- (id)keychainQueryWithKey:(id)key accessGroup:(id)ag {
    return %orig(key, accessGroupID());
}
%end

%hook GNPEncryptionConfiguration
- (id)initWithKeychainAccessGroup:(id)arg { return %orig(accessGroupID()); }
- (id)keychainAccessGroup                 { return accessGroupID(); }
%end

%hook FIRInstallationsStore
- (id)initWithSecureStorage:(id)arg1 accessGroup:(id)arg2 { return %orig(arg1, accessGroupID()); }
- (id)accessGroup { return accessGroupID(); }
%end

%hook CHMConfiguration
- (void)setKeychainAccessGroup:(id)arg { %orig(accessGroupID()); }
- (id)keychainAccessGroup              { return accessGroupID(); }
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (!groupIdentifier) return %orig(groupIdentifier);
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [docs URLByAppendingPathComponent:@"AppGroup"];
}
%end