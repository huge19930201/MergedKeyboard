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

	BOOL   _toolbarEnabled;
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
	// 使用 CFPreferences 读取本插件设置（App 与 tweak 共享同一份 plist）
	CFStringRef key = (__bridge CFStringRef)kPrefsID;
	Boolean valid = false;

#define RD_BOOL(_name, _def) \
	({ Boolean _v = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)_name, key, &valid); \
	   valid ? _v : _def; })

	_enabled = RD_BOOL(@"enabled", NO);

	_darkColorHex  = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("darkColor"), key);
	if (!_darkColorHex) _darkColorHex = @"#202020";
	_lightColorHex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("lightColor"), key);
	if (!_lightColorHex) _lightColorHex = @"#F2F2F2";

	_enableCandidateColor = RD_BOOL(@"enableCandidateColor", NO);
	_candidateColorHex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("candidateColor"), key);
	if (!_candidateColorHex) _candidateColorHex = @"#FFFFFF";
	_enableCandidateGradientColor = RD_BOOL(@"enableCandidateGradientColor", NO);
	_candidateGradientHex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("candidateGradientColor"), key);
	if (!_candidateGradientHex) _candidateGradientHex = @"#FFFFFF";
	_hideSeparatorLine = RD_BOOL(@"hideSeparatorLine", NO);

	_enableCornerRadius = RD_BOOL(@"enableCornerRadius", NO);
	_cornerRadius = (CGFloat)[self _doubleForKey:@"cornerRadius" default:8.0];
	_enableSystemKeyboardCorner = RD_BOOL(@"enableSystemKeyboardCorner", NO);
	_systemKeyboardCornerRadius = (CGFloat)[self _doubleForKey:@"systemKeyboardCornerRadius" default:12.0];

	_hideChineseEnglish = RD_BOOL(@"hideChineseEnglish", NO);

	_enableKeyBorder = RD_BOOL(@"enableKeyBorder", NO);
	_keyBorderDarkHex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("keyBorderDarkColor"), key);
	if (!_keyBorderDarkHex) _keyBorderDarkHex = @"#000000";
	_keyBorderLightHex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(CFSTR("keyBorderLightColor"), key);
	if (!_keyBorderLightHex) _keyBorderLightHex = @"#000000";
	_keyBorderOpacity = (CGFloat)[self _doubleForKey:@"keyBorderOpacity" default:1.0];
	_keyBorderWidth = (CGFloat)[self _doubleForKey:@"keyBorderWidth" default:1.0];

	_enableKeyShadow = RD_BOOL(@"enableKeyShadow", NO);
	_keyShadowOpacity = (CGFloat)[self _doubleForKey:@"keyShadowOpacity" default:0.3];
	_keyShadowOffsetX = (CGFloat)[self _doubleForKey:@"keyShadowOffsetX" default:0.0];
	_keyShadowOffsetY = (CGFloat)[self _doubleForKey:@"keyShadowOffsetY" default:1.0];
	_keyShadowRadius = (CGFloat)[self _doubleForKey:@"keyShadowRadius" default:2.0];

	_hideSystemKeyBackground = RD_BOOL(@"hideSystemKeyBackground", NO);

	_toolbarEnabled = RD_BOOL(@"toolbarEnabled", NO);

#undef RD_BOOL
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

- (UIColor *)keyboardBackgroundColorForView:(UIView *)view {
	NSString *hex = MKViewIsDarkMode(view) ? _darkColorHex : _lightColorHex;
	return MKColorFromHex(hex) ?: [UIColor clearColor];
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

@end
