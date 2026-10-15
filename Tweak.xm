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
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import "KeyboardThemeEngine.h"
#import "MergedKBToolbar.h"

#pragma mark - 私有类前向声明（运行时通过 %hook 解析，无需头文件）
// 注意：UIInputView 是 UIKit 公开类（UIInputView.h 已定义），不能再重复声明
@interface UIKeyboardDockView : UIView @end
@interface UIKBVisualEffectView : UIView @end
@interface UIKBBackdropView : UIView @end
@interface UIKBKeyBackgroundView : UIView @end
@interface UIKBKeyView : UIView @end
@interface UIKBRenderConfig : NSObject @end
@interface UIKBRenderGeometry : NSObject @end
@interface UIKeyboardCandidateViewStyle : NSObject @end
@interface WBMainInputView : UIView @end
// 微信输入法自己的工具栏类（原版 WXKBToolbar 就是 hook 这两个）
@interface WBTopBar : UIView @end
@interface WBFunctionToolBar : UIView @end
@interface WBKeyView : UIView @end
@interface WBSecKeyboardKeyView : UIView @end
@interface WBKeyViewItem : NSObject @end
@interface WBConfigManager : NSObject @end
@interface UIPredictionViewController : UIViewController @end

#pragma mark - 通用工具：键帽边框 / 阴影

// 所有改界面的操作都加异常保护：任何意外都不允许影响宿主 App / SpringBoard
static void MKApplyKeyDecoration(UIView *v) {
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		CALayer *layer = v.layer;
		if (!layer) return;

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
	} @catch (NSException *exception) {
		// 静默忽略，保证稳定性优先
	}
}

/*
 * 1.0.8 已删除上一版的「递归兜底上色」：它把圆角 + masksToBounds 套到了
 * 键盘所有带背景的容器上，直接把微信输入法的键盘布局裁坏了（用户实测键盘错乱）。
 * 教训：对未知视图树做无差别 layer 改动非常危险，上色必须限定在明确命中的类里。
 */

#pragma mark - 诊断弹窗

// 诊断弹窗只弹一次；设置被改动后重置，方便反复排查
static BOOL MKDebugAlertShown = NO;

// 只在微信/微信输入法里弹，避免每个 App 都弹。默认开启，拿到诊断信息后可在设置里关掉。
static void MKShowDebugIfNeeded(void) {
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e debugEnabled]) return;
		NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
		// 只在微信主 App 里弹：键盘扩展进程没有 keyWindow，
		// 这里的弹窗会抢掉键盘扩展里那份诊断弹窗的位置
		if (![bid isEqualToString:@"com.tencent.xin"]) return;

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			@try {
				UIViewController *root = nil;
				if (@available(iOS 13.0, *)) {
					for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
						if (scene.activationState != UISceneActivationStateForegroundActive) continue;
						if (![scene isKindOfClass:[UIWindowScene class]]) continue;
						for (UIWindow *w in ((UIWindowScene *)scene).windows) {
							if (w.isKeyWindow && w.rootViewController) root = w.rootViewController;
						}
					}
				}
				if (!root) root = [UIApplication sharedApplication].keyWindow.rootViewController;
				if (!root) return;

				UIAlertController *ac = [UIAlertController
					alertControllerWithTitle:@"MergedKeyboard 诊断"
					                 message:[e debugSummary]
					          preferredStyle:UIAlertControllerStyleAlert];
			[ac addAction:[UIAlertAction actionWithTitle:@"好"
			                                       style:UIAlertActionStyleCancel
			                                     handler:nil]];
			[ac addAction:[UIAlertAction actionWithTitle:@"复制诊断信息"
			                                       style:UIAlertActionStyleDefault
			                                     handler:^(UIAlertAction *action) {
				[UIPasteboard generalPasteboard].string = [e debugSummary];
			}]];
			[root presentViewController:ac animated:YES completion:nil];
			MKDebugAlertShown = YES;
			} @catch (NSException *exception) { }
		});
	} @catch (NSException *exception) { }
}

#pragma mark - 偏好变更通知

static void MKReloadPrefs(CFNotificationCenterRef center, void *observer,
						  CFStringRef name, const void *object, CFDictionaryRef info) {
	[[KeyboardThemeEngine shared] reloadPrefs];
	// 设置改了就允许诊断弹窗再弹一次
	MKDebugAlertShown = NO;
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
	// 同时挂载微信功能栏（加异常保护）
	@try {
		if ([[MergedKBToolbar shared] shouldShowInCurrentApp] && [e toolbarEnabled]) {
			[[MergedKBToolbar shared] attachToDock:self];
		}
	} @catch (NSException *exception) {
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
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:nil];
	return %orig;
}
- (UIColor *)gridBackgroundColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && ([e enableCandidateColor] || [e enableCandidateGradientColor])) {
		return [e candidateGradientColorForView:nil];
	}
	return %orig;
}
- (UIColor *)highlightedBackgroundColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:nil];
	return %orig;
}
- (UIColor *)highlightedTextColor {
	KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
	if ([e isEnabled] && [e enableCandidateColor]) return [e candidateTextColorForView:nil];
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

#pragma mark - 诊断增强（1.0.9）：把真实类名带出来

/*
 * 之前一直靠猜类名，猜错就全都不生效。
 * 1.0.9 直接在运行时枚举当前进程里所有 WB* 开头的 Objective-C 类，
 * 并把键盘视图树 dump 出来 —— 有了这份报告就不用再猜了。
 */
static NSString *MKClassProbe(void) {
	NSMutableString *s = [NSMutableString string];
	NSArray *want = @[@"WBMainInputView", @"WBKeyboardView", @"WBKeyView",
	                  @"WBTopBar", @"WBFunctionToolBar", @"WBConfigManager",
	                  @"UIKeyboardDockView", @"UIInputView",
	                  @"UIKBKeyView", @"UIKBKeyBackgroundView"];
	for (NSString *c in want) {
		[s appendFormat:@"%@:%@  ", c, NSClassFromString(c) ? @"有" : @"无"];
	}
	{
		Class *classes = (Class *)malloc(sizeof(Class) * 30000);
		if (classes) {
			int count = objc_getClassList(classes, 30000);
			NSMutableArray *wb = [NSMutableArray array];
			for (int i = 0; i < count; i++) {
				NSString *n = NSStringFromClass(classes[i]);
				if ([n hasPrefix:@"WB"]) [wb addObject:n];
			}
			free(classes);
			[wb sortUsingSelector:@selector(compare:)];
			[s appendFormat:@"\n运行时 WB* 类(%lu个): %@\n",
				(unsigned long)wb.count, [wb componentsJoinedByString:@", "]];
		}
	}
	return s;
}

static void MKDumpViewTree(UIView *v, int depth, NSMutableString *s, int *budget) {
	if (!v || depth > 4 || *budget <= 0) return;
	(*budget)--;
	NSString *pad = [@"" stringByPaddingToLength:(NSUInteger)(depth * 2)
	                                    withString:@" " startingAtIndex:0];
	CGFloat a = v.backgroundColor ? CGColorGetAlpha(v.backgroundColor.CGColor) : 0.0;
	[s appendFormat:@"%@%@ %.0fx%.0f bgA=%.2f sub=%lu\n",
		pad, NSStringFromClass(v.class),
		v.bounds.size.width, v.bounds.size.height, a, (unsigned long)v.subviews.count];
	for (UIView *c in v.subviews) MKDumpViewTree(c, depth + 1, s, budget);
}

// 键帽启发式：只改「叶子 + 键帽尺寸 + 背景不透明」的小视图，绝不动容器
static void MKApplyKeycapHeuristic(UIView *v, int depth) {
	if (!v || depth > 5) return;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		BOOL wantDeco = [e enableCornerRadius] || [e enableKeyBorder] || [e enableKeyShadow];
		if (wantDeco && v.subviews.count == 0 && v.backgroundColor) {
			CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
			CGFloat a = CGColorGetAlpha(v.backgroundColor.CGColor);
			if (a > 0.05 && h >= 24 && h <= 80 && w >= 20 && w <= 140) {
				MKApplyKeyDecoration(v);
			}
		}
		for (UIView *c in v.subviews) MKApplyKeycapHeuristic(c, depth + 1);
	} @catch (NSException *exception) { }
}

%hook UIInputViewController
- (void)viewDidAppear:(BOOL)animated {
	%orig;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";

		// ---- 主题应用（不依赖任何 WB 类名）----
		if ([e isEnabled]) {
			if (![e hideSystemKeyBackground]) {
				self.view.backgroundColor = [e keyboardBackgroundColorForView:self.view];
			}
			MKApplyKeycapHeuristic(self.view, 0);
			if ([e toolbarEnabled] && [[MergedKBToolbar shared] shouldShowInCurrentApp]) {
				[[MergedKBToolbar shared] attachToDock:self.view];
			}
		}

		if (![e debugEnabled]) return;
		if (![bid hasPrefix:@"com.tencent.wetype"] &&
		    ![bid isEqualToString:@"com.tencent.xin"]) return;

		// ---- 1.0.9 诊断：剪贴板 + 落盘 + 键盘上一行摘要 + 弹窗 ----
		if (MKDebugAlertShown) return;
		MKDebugAlertShown = YES;

		NSString *probe = MKClassProbe();
		int budget = 70;
		NSMutableString *tree = [NSMutableString string];
		[tree appendString:@"\n=== 键盘视图树 ===\n"];
		MKDumpViewTree(self.view, 0, tree, &budget);

		NSString *report = [NSString stringWithFormat:
			@"进程: %@\n%@\n%@", bid, [e debugSummary], probe];

		// 剪贴板（键盘扩展需开启“允许完全访问”才写得进，尽力而为）
		@try { [UIPasteboard generalPasteboard].string = report; } @catch (NSException *x) { }

		// 落盘（尽力而为，Filza 里可看）
		for (NSString *p in @[@"/var/mobile/Library/Preferences/com.merged.keyboard.debug.txt",
		                      @"/var/mobile/com.merged.keyboard.debug.txt"]) {
			@try { [report writeToFile:p atomically:YES
			                      encoding:NSUTF8StringEncoding error:nil]; }
			@catch (NSException *x) { }
		}

		// 键盘顶部一行摘要（截图/肉眼可读）
		UILabel *old = (UILabel *)[self.view viewWithTag:99001];
		[old removeFromSuperview];
		NSString *wbMain = NSClassFromString(@"WBMainInputView") ? @"有" : @"无";
		NSString *wbKey  = NSClassFromString(@"WBKeyView")       ? @"有" : @"无";
		NSString *dock   = NSClassFromString(@"UIKeyboardDockView") ? @"有" : @"无";
		UILabel *lb = [[UILabel alloc] initWithFrame:
			CGRectMake(4, 2, self.view.bounds.size.width - 8, 15)];
		lb.tag = 99001;
		lb.font = [UIFont systemFontOfSize:9];
		lb.textColor = [UIColor yellowColor];
		lb.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
		lb.text = [NSString stringWithFormat:@"MK诊断| WBMain:%@ WBKey:%@ Dock:%@ 剪贴板已写入报告",
			wbMain, wbKey, dock];
		[self.view addSubview:lb];

		UIAlertController *ac = [UIAlertController
			alertControllerWithTitle:@"MergedKeyboard 诊断 1.0.9"
			                 message:@"报告已复制到剪贴板（若键盘开了“允许完全访问”）。\n粘贴发我即可。"
			          preferredStyle:UIAlertControllerStyleAlert];
		[ac addAction:[UIAlertAction actionWithTitle:@"好"
		                                       style:UIAlertActionStyleCancel
		                                     handler:nil]];
		[ac addAction:[UIAlertAction actionWithTitle:@"复制诊断信息"
		                                       style:UIAlertActionStyleDefault
		                                     handler:^(UIAlertAction *action) {
			[UIPasteboard generalPasteboard].string = report;
		}]];
		[self presentViewController:ac animated:YES completion:nil];
	} @catch (NSException *exception) { }
}
%end

%hook WBMainInputView
- (void)layoutSubviews {
	%orig;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e isEnabled]) return;
		if (![e hideSystemKeyBackground]) {
			self.backgroundColor = [e keyboardBackgroundColorForView:self];
		}
		MKApplyKeyDecoration(self);

		// 微信输入法：功能栏直接挂到主输入视图顶部
		if ([e toolbarEnabled] && [[MergedKBToolbar shared] shouldShowInCurrentApp]) {
			[[MergedKBToolbar shared] attachToDock:self];
		}
	} @catch (NSException *exception) { }
}
%end

%hook WBTopBar
- (void)layoutSubviews {
	%orig;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e isEnabled]) return;
		if (![e hideSystemKeyBackground]) {
			self.backgroundColor = [e keyboardBackgroundColorForView:self];
		}
	} @catch (NSException *exception) { }
}
%end

%hook WBFunctionToolBar
- (void)layoutSubviews {
	%orig;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e isEnabled]) return;
		if (![e hideSystemKeyBackground]) {
			self.backgroundColor = [e keyboardBackgroundColorForView:self];
		}
	} @catch (NSException *exception) { }
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

// 紧急开关：存在该文件时插件完全不生效（用于救砖，无需卸载）
static BOOL MKEmergencyDisabled(void) {
	static BOOL checked = NO;
	static BOOL disabled = NO;
	if (checked) return disabled;
	checked = YES;
	@try {
		NSArray *paths = @[
			@"/var/mobile/Library/Preferences/com.merged.keyboard.disabled",
			@"/var/mobile/com.merged.keyboard.disabled"
		];
		for (NSString *p in paths) {
			if ([[NSFileManager defaultManager] fileExistsAtPath:p]) { disabled = YES; break; }
		}
	} @catch (NSException *exception) { }
	return disabled;
}

%ctor {
	@autoreleasepool {
		// ===== 0) 紧急开关：手机进不去时，用 Filza/SSH 建一个空文件即可完全停用 =====
		if (MKEmergencyDisabled()) return;

		// ===== 1) 进程黑名单：绝不能在 SpringBoard 等系统进程里启用 =====
		// SpringBoard 开机/锁屏时会创建密码键盘（同样是键盘类），
		// 一旦在这里改动界面就可能把 SpringBoard 搞崩，导致无限重启黑屏。
		NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
		if (bid.length == 0) return;

		static NSSet *blacklist;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			blacklist = [NSSet setWithObjects:
				@"com.apple.springboard",          // 桌面（最危险）
				@"com.apple.Preferences",          // 设置 App
				@"com.apple.backboardd",
				@"com.apple.mediaserverd",
				@"com.apple.WebKit.WebContent",
				@"com.apple.WebKit.Networking",
				@"com.apple.TextInput.rdt",
				@"com.apple.assistant_service",
				@"com.apple.camera",               // 相机锁屏组件
				@"com.apple.Spotlight",
				@"com.apple.spotlight",
				nil];
		});
		if ([blacklist containsObject:bid]) return;
		// 兜底：只要包含 springboard 字样一律跳过（RootHide 下进程名可能被改写）
		if ([bid rangeOfString:@"springboard" options:NSCaseInsensitiveSearch].location != NSNotFound) return;

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

		// 诊断：装了 1.0.4 后打开微信，3 秒后会弹出插件实际读到的值
		MKShowDebugIfNeeded();
	}
}
