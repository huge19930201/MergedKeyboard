//
//  KeyboardThemeEngine.m
//  MergedKeyboard
//
//  键盘主题引擎实现。通过 CFPreferences 读取 com.merged.keyboard 下的设置，
//  统一提供给各个 %hook 使用。所有功能默认关闭，需用户在设置中开启。
//

#import "KeyboardThemeEngine.h"

static NSString *const kPrefsID = @"com.merged.keyboard";
static NSString *const kReloadNotification = @"com.merged.keyboard/ReloadPrefs";

#pragma mark - 工具函数实现

UIColor *MKColorFromHex(NSString *hex) {
	if (hex.length == 0) return nil;
	NSString *s = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
	if (s.length == 3) {
		// #RGB -> #RRGGBB
		s = [NSString stringWithFormat:@"%c%c%c%c%c%c",
		     [s characterAtIndex:0], [s characterAtIndex:0],
		     [s characterAtIndex:1], [s characterAtIndex:1],
		     [s characterAtIndex:2], [s characterAtIndex:2]];
	}
	if (s.length != 6 && s.length != 8) return nil;
	unsigned int value = 0;
	[[NSScanner scannerWithString:s] scanHexInt:&value];
	CGFloat a = 1.0;
	if (s.length == 8) {
		a = ((value & 0xFF)) / 255.0;
		value >>= 8;
	}
	CGFloat r = ((value >> 16) & 0xFF) / 255.0;
	CGFloat g = ((value >> 8) & 0xFF) / 255.0;
	CGFloat b = (value & 0xFF) / 255.0;
	return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

#pragma mark - 偏好读取（多重兜底）

/*
 * CFPreferences 在被沙盒限制的 App（微信这类 App Store 应用）里可能读不到别的域，
 * 表现为「设置了但插件完全没反应、值永远是默认」。所以这里做三级兜底：
 *   1) CFPreferences（正常路径）
 *   2) NSUserDefaults -persistentDomainForName:
 *   3) 直接读 /var/mobile/Library/Preferences/ 下的 plist 文件
 */
static NSDictionary *MKLoadPrefsFallback(void) {
	@try {
		NSDictionary *d = [[NSUserDefaults standardUserDefaults] persistentDomainForName:kPrefsID];
		if (d.count) return d;
	} @catch (NSException *e) { }

	NSArray *paths = @[
		@"/var/mobile/Library/Preferences/com.merged.keyboard.plist",
		@"/var/jb/var/mobile/Library/Preferences/com.merged.keyboard.plist",
		@"/private/var/mobile/Library/Preferences/com.merged.keyboard.plist"
	];
	for (NSString *p in paths) {
		@try {
			NSDictionary *x = [NSDictionary dictionaryWithContentsOfFile:p];
			if (x.count) return x;
		} @catch (NSException *e) { }
	}
	return nil;
}

static BOOL MKBool(NSString *k, BOOL def, NSDictionary *fb) {
	Boolean valid = false;
	Boolean v = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)k,
	                                            (__bridge CFStringRef)kPrefsID, &valid);
	if (valid) return (BOOL)v;
	id o = fb[k];
	if ([o isKindOfClass:[NSNumber class]]) return [(NSNumber *)o boolValue];
	if ([o isKindOfClass:[NSString class]]) {
		NSString *s = [(NSString *)o lowercaseString];
		return ([s isEqualToString:@"1"] || [s isEqualToString:@"yes"] ||
		        [s isEqualToString:@"true"] || [s isEqualToString:@"on"]);
	}
	return def;
}

static NSString *MKStr(NSString *k, NSString *def, NSDictionary *fb) {
	id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)k,
	                                                       (__bridge CFStringRef)kPrefsID);
	if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
	id o = fb[k];
	if ([o isKindOfClass:[NSString class]] && [(NSString *)o length]) return o;
	return def;
}

static double MKDouble(NSString *k, double def, NSDictionary *fb) {
	id v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)k,
	                                                       (__bridge CFStringRef)kPrefsID);
	if ([v respondsToSelector:@selector(doubleValue)]) return [(id)v doubleValue];
	id o = fb[k];
	if ([o respondsToSelector:@selector(doubleValue)]) return [(id)o doubleValue];
	return def;
}

BOOL MKViewIsDarkMode(UIView *view) {
	// 优先用视图自身的 traitCollection，没有再退回屏幕
	UITraitCollection *tc = nil;
	if ([view respondsToSelector:@selector(traitCollection)]) {
		tc = view.traitCollection;
	}
	if (!tc) {
		tc = [UIScreen mainScreen].traitCollection;
	}
	if (@available(iOS 12.0, *)) {
		return tc.userInterfaceStyle == UIUserInterfaceStyleDark;
	}
	return NO;
}

#pragma mark - 引擎主体

@implementation KeyboardThemeEngine {
	BOOL   _enabled;

	NSString *_darkColorHex;
	NSString *_lightColorHex;

	BOOL   _enableCandidateColor;
	NSString *_candidateColorHex;
	BOOL   _enableCandidateGradientColor;
	NSString *_candidateGradientHex;
	BOOL   _hideSeparatorLine;

	BOOL   _enableCornerRadius;
	CGFloat _cornerRadius;
	BOOL   _enableSystemKeyboardCorner;
	CGFloat _systemKeyboardCornerRadius;

	BOOL   _hideChineseEnglish;

	BOOL   _enableKeyBorder;
	NSString *_keyBorderDarkHex;
	NSString *_keyBorderLightHex;
	CGFloat _keyBorderOpacity;
	CGFloat _keyBorderWidth;

	BOOL   _enableKeyShadow;
	CGFloat _keyShadowOpacity;
	CGFloat _keyShadowOffsetX;
	CGFloat _keyShadowOffsetY;
	CGFloat _keyShadowRadius;

	BOOL   _hideSystemKeyBackground;

	BOOL   _unifyBackground;
	BOOL   _forceBackground;

	BOOL   _toolbarEnabled;

	// 诊断
	BOOL   _debugEnabled;
	NSString *_prefsSource;
}

+ (instancetype)shared {
	static KeyboardThemeEngine *inst = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		inst = [[KeyboardThemeEngine alloc] init];
		[inst reloadPrefs];
	});
	return inst;
}

- (instancetype)init {
	if (self = [super init]) {
		// 给一份合理的默认值，reloadPrefs 会覆盖
		_darkColorHex  = @"#202020";
		_lightColorHex = @"#F2F2F2";
		_candidateColorHex = @"#FFFFFF";
		_candidateGradientHex = @"#FFFFFF";
		_keyBorderDarkHex = @"#000000";
		_keyBorderLightHex = @"#000000";
		_cornerRadius = 8.0;
		_systemKeyboardCornerRadius = 12.0;
		_keyBorderOpacity = 1.0;
		_keyBorderWidth = 1.0;
		_keyShadowOpacity = 0.3;
		_keyShadowOffsetX = 0.0;
		_keyShadowOffsetY = 1.0;
		_keyShadowRadius = 2.0;
	}
	return self;
}

- (void)reloadPrefs {
	@try {
		CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsID);
	} @catch (NSException *e) { }

	NSDictionary *fb = MKLoadPrefsFallback();
	_prefsSource = fb ? @"兜底(NSUserDefaults/文件)" : @"CFPreferences";

	// 默认开启（与原版一致）：装上去就能看到效果，用户可自行关闭
	_enabled                      = MKBool(@"enabled", YES, fb);
	// 诊断默认开启，确认生效后用户在设置里关掉即可
	_debugEnabled                 = MKBool(@"debug", NO, fb);

	_darkColorHex                 = MKStr(@"darkColor", @"#202020", fb);
	_lightColorHex                = MKStr(@"lightColor", @"#F2F2F2", fb);

	_enableCandidateColor         = MKBool(@"enableCandidateColor", NO, fb);
	_candidateColorHex            = MKStr(@"candidateColor", @"#FFFFFF", fb);
	_enableCandidateGradientColor = MKBool(@"enableCandidateGradientColor", NO, fb);
	_candidateGradientHex         = MKStr(@"candidateGradientColor", @"#FFFFFF", fb);
	_hideSeparatorLine            = MKBool(@"hideSeparatorLine", NO, fb);

	_enableCornerRadius           = MKBool(@"enableCornerRadius", NO, fb);
	_cornerRadius                 = (CGFloat)MKDouble(@"cornerRadius", 8.0, fb);
	_enableSystemKeyboardCorner   = MKBool(@"enableSystemKeyboardCorner", NO, fb);
	_systemKeyboardCornerRadius   = (CGFloat)MKDouble(@"systemKeyboardCornerRadius", 12.0, fb);

	_hideChineseEnglish           = MKBool(@"hideChineseEnglish", NO, fb);

	_enableKeyBorder              = MKBool(@"enableKeyBorder", NO, fb);
	_keyBorderDarkHex             = MKStr(@"keyBorderDarkColor", @"#000000", fb);
	_keyBorderLightHex            = MKStr(@"keyBorderLightColor", @"#000000", fb);
	_keyBorderOpacity             = (CGFloat)MKDouble(@"keyBorderOpacity", 1.0, fb);
	_keyBorderWidth               = (CGFloat)MKDouble(@"keyBorderWidth", 1.0, fb);

	_enableKeyShadow              = MKBool(@"enableKeyShadow", NO, fb);
	_keyShadowOpacity             = (CGFloat)MKDouble(@"keyShadowOpacity", 0.3, fb);
	_keyShadowOffsetX             = (CGFloat)MKDouble(@"keyShadowOffsetX", 0.0, fb);
	_keyShadowOffsetY             = (CGFloat)MKDouble(@"keyShadowOffsetY", 1.0, fb);
	_keyShadowRadius              = (CGFloat)MKDouble(@"keyShadowRadius", 2.0, fb);

	_hideSystemKeyBackground      = MKBool(@"hideSystemKeyBackground", NO, fb);
	// 1.3.0：默认开启，避免「改了深色色值但手机在浅色模式」这种看不出效果的坑
	_unifyBackground              = MKBool(@"unifyBackground", YES, fb);
	_forceBackground              = MKBool(@"forceBackground", YES, fb);
	_toolbarEnabled               = MKBool(@"toolbarEnabled", NO, fb);
}

- (double)_doubleForKey:(NSString *)k default:(double)def {
	CFPropertyListRef val = CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)kPrefsID);
	if (val && CFGetTypeID(val) == CFNumberGetTypeID()) {
		double d = 0;
		CFNumberGetValue((CFNumberRef)val, kCFNumberDoubleType, &d);
		CFRelease(val);
		return d;
	}
	if (val) CFRelease(val);
	return def;
}

#pragma mark - 对外查询

- (BOOL)isEnabled { return _enabled; }

- (NSString *)backgroundHexForView:(UIView *)view {
	if (_unifyBackground) return _darkColorHex;
	return MKViewIsDarkMode(view) ? _darkColorHex : _lightColorHex;
}

- (BOOL)unifyBackground { return _unifyBackground; }
- (BOOL)forceBackground { return _forceBackground; }

- (UIColor *)keyboardBackgroundColorForView:(UIView *)view {
	NSString *hex = [self backgroundHexForView:view];
	UIColor *c = MKColorFromHex(hex);
	// 解析不出来时不要返回透明（透明 = 看起来完全没生效），退回深色
	return c ?: (MKColorFromHex(_darkColorHex) ?: [UIColor clearColor]);
}

- (BOOL)hideSystemKeyBackground { return _hideSystemKeyBackground; }

- (BOOL)enableCandidateColor { return _enableCandidateColor; }
- (UIColor *)candidateTextColorForView:(UIView *)view {
	return MKColorFromHex(_candidateColorHex) ?: [UIColor labelColor];
}
- (BOOL)enableCandidateGradientColor { return _enableCandidateGradientColor; }
- (UIColor *)candidateGradientColorForView:(UIView *)view {
	return MKColorFromHex(_candidateGradientHex) ?: [UIColor clearColor];
}
- (BOOL)hideSeparatorLine { return _hideSeparatorLine; }

- (BOOL)enableCornerRadius { return _enableCornerRadius; }
- (CGFloat)cornerRadius { return _cornerRadius; }
- (BOOL)enableSystemKeyboardCorner { return _enableSystemKeyboardCorner; }
- (CGFloat)systemKeyboardCornerRadius { return _systemKeyboardCornerRadius; }

- (BOOL)hideChineseEnglish { return _hideChineseEnglish; }

- (BOOL)enableKeyBorder { return _enableKeyBorder; }
- (UIColor *)keyBorderColorForView:(UIView *)view {
	NSString *hex = MKViewIsDarkMode(view) ? _keyBorderDarkHex : _keyBorderLightHex;
	return MKColorFromHex(hex) ?: [UIColor blackColor];
}
- (CGFloat)keyBorderOpacity { return _keyBorderOpacity; }
- (CGFloat)keyBorderWidth { return _keyBorderWidth; }

- (BOOL)enableKeyShadow { return _enableKeyShadow; }
- (CGFloat)keyShadowOpacity { return _keyShadowOpacity; }
- (CGFloat)keyShadowOffsetX { return _keyShadowOffsetX; }
- (CGFloat)keyShadowOffsetY { return _keyShadowOffsetY; }
- (CGFloat)keyShadowRadius { return _keyShadowRadius; }

- (BOOL)toolbarEnabled { return _toolbarEnabled; }

#pragma mark - 诊断

- (BOOL)debugEnabled { return _debugEnabled; }

- (NSString *)prefsSource { return _prefsSource ?: @"(未知)"; }

- (NSString *)debugSummary {
	NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)";
	NSMutableString *s = [NSMutableString string];
	[s appendFormat:@"进程: %@\n", bid];
	[s appendFormat:@"偏好来源: %@\n", _prefsSource ?: @"(未知)"];
	[s appendFormat:@"总开关 enabled: %@\n", _enabled ? @"YES ✅" : @"NO ❌"];
	[s appendFormat:@"微信功能栏: %@\n", _toolbarEnabled ? @"YES" : @"NO"];
	[s appendFormat:@"深色背景: %@ / 浅色: %@ (当前实际用: %@)\n",
		_darkColorHex, _lightColorHex, [self backgroundHexForView:nil]];
	[s appendFormat:@"统一背景色: %@ / 强力上色: %@\n",
		_unifyBackground ? @"开" : @"关", _forceBackground ? @"开" : @"关"];
	[s appendFormat:@"键帽圆角: %@(%g) 边框:%@ 阴影:%@\n",
		_enableCornerRadius ? @"开" : @"关", _cornerRadius,
		_enableKeyBorder ? @"开" : @"关", _enableKeyShadow ? @"开" : @"关"];
	[s appendFormat:@"隐藏系统背景: %@\n", _hideSystemKeyBackground ? @"YES" : @"NO"];
	[s appendString:@"\n--- 类是否命中 ---\n"];
	static NSArray *cls = nil;
	if (!cls) {
		cls = @[@"UIKeyboardDockView", @"UIInputView", @"UIKBKeyView", @"UIKBBackdropView",
		        @"UIKBKeyBackgroundView", @"UIKeyboardCandidateViewStyle",
		        @"WBMainInputView", @"WBTopBar", @"WBFunctionToolBar", @"WBKeyView",
		        @"WBSecKeyboardKeyView", @"WBKeyViewItem", @"WBConfigManager"];
	}
	for (NSString *c in cls) {
		[s appendFormat:@"%@: %@\n", c, NSClassFromString(c) ? @"有 ✅" : @"无"];
	}

	[s appendString:@"\n--- 实际读到的原始值 ---\n"];
	NSDictionary *raw = MKLoadPrefsFallback();
	if (raw.count) {
		for (NSString *k in [raw.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
			[s appendFormat:@"%@ = %@\n", k, raw[k]];
		}
	} else {
		[s appendString:@"(兜底字典为空)\n"];
	}
	CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)kPrefsID,
	                                           kCFPreferencesCurrentUser,
	                                           kCFPreferencesAnyHost);
	if (keys) {
		NSDictionary *cf = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
			keys, (__bridge CFStringRef)kPrefsID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		[s appendFormat:@"CFPreferences 键数量: %lu\n", (unsigned long)cf.count];
		CFRelease(keys);
	} else {
		[s appendString:@"CFPreferences 键列表为空\n"];
	}
	return s;
}

@end
