/*
 *  Tweak.xm — MergedKeyboard
 *
 *  合并版键盘增强插件（全新重写，开源免费，不含付费授权逻辑）。
 *  两部分功能：
 *    1) 微信键盘功能栏（原 WXKBToolbar）：在 UIKeyboardDockView 上挂载一条快捷按钮栏。
 *    2) 键盘主题引擎（原 Keyboardhook）：背景色 / 圆角 / 键帽边框 / 阴影 /
 *       候选栏配色 / 隐藏分隔线 / 隐藏系统中/英键 / 深浅色自适应。
 *
 *  全部行为由 com.merged.keyboard 下的设置开关控制，默认全部关闭。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "KeyboardThemeEngine.h"
#import "MergedKBToolbar.h"

#pragma mark - 私有类前向声明（运行时通过 %hook 解析，无需头文件）
@interface UIKeyboardDockView : UIView @end
@interface UIInputView : UIView @end
@interface UIKBVisualEffectView : UIView @end
@interface UIKBBackdropView : UIView @end
@interface UIKBKeyBackgroundView : UIView @end
@interface UIKBKeyView : UIView @end
@interface UIKBRenderConfig : NSObject @end
@interface UIKBRenderGeometry : NSObject @end
@interface UIKeyboardCandidateViewStyle : NSObject @end
@interface WBMainInputView : UIView @end
@interface WBKeyView : UIView @end
@interface WBSecKeyboardKeyView : UIView @end
@interface WBKeyViewItem : NSObject @end
@interface WBConfigManager : NSObject @end
@interface UIPredictionViewController : UIViewController @end

#pragma mark - 通用工具：键帽边框 / 阴影

static void MKApplyKeyDecoration(UIView *v) {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	CALayer *layer = v.layer;

	if ([e enableCornerRadius]) {
		layer.cornerRadius = [e cornerRadius];
		layer.masksToBounds = YES;
	}
	if ([e enableKeyBorder]) {
		layer.borderWidth = [e keyBorderWidth];
		UIColor *c = [[e keyBorderColorForView:v] colorWithAlphaComponent:[e keyBorderOpacity]];
		layer.borderColor = c.CGColor;
	}
	if ([e enableKeyShadow]) {
		layer.shadowOpacity = (float)[e keyShadowOpacity];
		layer.shadowOffset = CGSizeMake([e keyShadowOffsetX], [e keyShadowOffsetY]);
		layer.shadowRadius = [e keyShadowRadius];
		layer.shadowColor = [UIColor blackColor].CGColor;
		layer.masksToBounds = NO;
	}
}

#pragma mark - 偏好变更通知

static void MKReloadPrefs(CFNotificationCenterRef center, void *observer,
						  CFStringRef name, const void *object, CFDictionaryRef info) {
	[[KeyboardThemeEngine shared] reloadPrefs];
}

#pragma mark - 键盘主题 Hook 组

%group KeyboardTheme

%hook UIKeyboardDockView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	if (![e hideSystemKeyBackground]) {
		self.backgroundColor = [e keyboardBackgroundColorForView:self];
	}
	if ([e enableSystemKeyboardCorner]) {
		self.layer.cornerRadius = [e systemKeyboardCornerRadius];
		self.layer.masksToBounds = YES;
	}
	// 同时挂载微信功能栏
	if ([[MergedKBToolbar shared] shouldShowInCurrentApp] && [e toolbarEnabled]) {
		[[MergedKBToolbar shared] attachToDock:self];
	}
}
%end

%hook UIInputView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	if (![e hideSystemKeyBackground]) {
		self.backgroundColor = [e keyboardBackgroundColorForView:self];
	}
	if ([e enableSystemKeyboardCorner]) {
		self.layer.cornerRadius = [e systemKeyboardCornerRadius];
		self.layer.masksToBounds = YES;
	}
}
%end

%hook UIKBVisualEffectView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled] || [e hideSystemKeyBackground]) return;
	self.backgroundColor = [e keyboardBackgroundColorForView:self];
}
%end

%hook UIKBBackdropView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	// 隐藏系统键盘背景：设为透明
	if ([e hideSystemKeyBackground]) {
		self.backgroundColor = [UIColor clearColor];
	} else {
		self.backgroundColor = [e keyboardBackgroundColorForView:self];
	}
}
%end

%hook UIKBKeyBackgroundView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	if (![e hideSystemKeyBackground]) {
		self.backgroundColor = [e keyboardBackgroundColorForView:self];
	}
	MKApplyKeyDecoration(self);
}
%end

%hook UIKBKeyView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	MKApplyKeyDecoration(self);
}
%end

%hook UIKBRenderConfig
- (void)setKeyBackgroundType:(NSInteger)type {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e hideSystemKeyBackground]) {
		%orig(0); // 无背景
	} else {
		%orig;
	}
}
- (void)setKeyBackgroundOpacity:(double)opacity {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e hideSystemKeyBackground]) {
		%orig(0.0);
	} else {
		%orig;
	}
}
%end

%hook UIKBRenderGeometry
- (void)setRoundRectRadius:(double)radius {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCornerRadius]) {
		%orig([e cornerRadius]);
	} else {
		%orig;
	}
}
%end

%hook UIKeyboardCandidateViewStyle
- (UIColor *)arrowButtonBackgroundColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:self];
	return %orig;
}
- (UIColor *)gridBackgroundColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && ([e enableCandidateColor] || [e enableCandidateGradientColor])) {
		return [e candidateGradientColorForView:self];
	}
	return %orig;
}
- (UIColor *)highlightedBackgroundColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:self];
	return %orig;
}
- (UIColor *)highlightedTextColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:self];
	return %orig;
}
- (UIColor *)lineColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e hideSeparatorLine]) return [UIColor clearColor];
	return %orig;
}
- (UIImage *)arrowButtonSeparatorImage {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e hideSeparatorLine]) return nil;
	return %orig;
}
%end

#pragma mark - 微信私有类 Hook（仅在微信内生效，类不存在时 Logos 自动跳过）

%hook WBMainInputView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	if (![e hideSystemKeyBackground]) {
		self.backgroundColor = [e keyboardBackgroundColorForView:self];
	}
	MKApplyKeyDecoration(self);
}
%end

%hook WBKeyView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled]) return;
	MKApplyKeyDecoration(self);
}
%end

%hook WBSecKeyboardKeyView
- (void)layoutSubviews {
	%orig;
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if (![e isEnabled] || ![e hideChineseEnglish]) return;
	// 隐藏中/英切换键：找到显示 "中"/"英"/"ABC" 的子视图并隐藏
	for (UIView *sub in self.subviews) {
		NSString *txt = nil;
		if ([sub respondsToSelector:@selector(text)]) txt = [sub performSelector:@selector(text)];
		if ([txt isKindOfClass:[NSString class]] &&
			([txt containsString:@"中"] || [txt containsString:@"英"] ||
			 [txt isEqualToString:@"ABC"] || [txt.uppercaseString containsString:@"ABC"])) {
			sub.hidden = YES;
		}
	}
}
%end

%hook WBKeyViewItem
- (double)cornerRadius {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCornerRadius]) return [e cornerRadius];
	return %orig;
}
%end

%hook WBConfigManager
- (UIColor *)candidateFocusedTextColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:nil];
	return %orig;
}
%end

%hook UIPredictionViewController
- (id)_currentTextSuggestions {
	// 保留系统原始行为；如需屏蔽预测条可在此返回 nil
	return %orig;
}
%end

%end // group KeyboardTheme

#pragma mark - 构造入口

%ctor {
	@autoreleasepool {
		// 初始化偏好
		[[KeyboardThemeEngine shared] reloadPrefs];

		// 监听设置变更（设置面板保存后发送 Darwin 通知）
		CFNotificationCenterAddObserver(
			CFNotificationCenterGetDarwinNotifyCenter(),
			NULL,
			MKReloadPrefs,
			CFSTR("com.merged.keyboard/ReloadPrefs"),
			NULL,
			CFNotificationSuspensionBehaviorDeliverImmediately);

		%init(KeyboardTheme);
	}
}
