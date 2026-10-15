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
// 完整诊断报告（剪贴板/文件）只写一次
static BOOL MKReportWritten = NO;

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

// 判断一个视图是否可能是「键帽」（按尺寸区间，不再要求背景不透明）
static BOOL MKLooksLikeKeycap(UIView *v) {
	CGFloat w = v.bounds.size.width, h = v.bounds.size.height;
	if (w <= 0 || h <= 0) return NO;
	if (w < 14 || h < 14) return NO;
	if (w > 240 || h > 96) return NO;
	if (v.subviews.count > 2) return NO;
	if (v.tag == 99001) return NO;              // 我们自己的诊断标签
	if ([v isKindOfClass:[UIScrollView class]]) return NO; // 别碰功能栏
	return YES;
}

// 键帽启发式：深度遍历，符合尺寸的就套装饰，绝不动大容器
static void MKApplyKeycapHeuristic(UIView *v, int depth) {
	if (!v || depth > 6) return;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		BOOL wantDeco = [e enableCornerRadius] || [e enableKeyBorder] || [e enableKeyShadow];
		if (wantDeco && MKLooksLikeKeycap(v)) MKApplyKeyDecoration(v);
		for (UIView *c in v.subviews) MKApplyKeycapHeuristic(c, depth + 1);
	} @catch (NSException *exception) { }
}

/*
 * 1.1.0：发现 UIInputViewController 的 viewDidAppear: 在微信输入法里很可能被子类
 * 重写且没有调用 [super]，导致整套 hook 一次都不触发。
 * 这里改用 UIView 的 didMoveToWindow —— 所有视图必然走到、且必然调 super，
 * 是最可靠的「键盘已经显示出来了」信号。
 */
static CFTimeInterval MKLastHandleRun = -1.0;
// 键盘根视图（供定时器复用）
static __weak UIView *MKKeyboardRoot = nil;
// 前置声明：把诊断报告直接打进文本框
static void MKInsertDiagnosticText(void);

/*
 * 1.1.2：键帽是键盘出现之后才动态创建的，只在 didMoveToWindow 里装饰一次的话，
 * 那些后建的按键根本没被处理过 —— 表现就是「打开了阴影/圆角，但键帽毫无变化」。
 * 所以这里再起一个 0.6 秒的重复任务循环套用，代价很低（只是遍历视图树）。
 */
static dispatch_source_t MKThemeTimer = NULL;

static void MKStartThemeTimer(void) {
	if (MKThemeTimer) return;
	MKThemeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
	                                      dispatch_get_main_queue());
	if (!MKThemeTimer) return;
	dispatch_source_set_timer(MKThemeTimer, DISPATCH_TIME_NOW,
	                          (uint64_t)(0.6 * NSEC_PER_SEC),
	                          (uint64_t)(0.2 * NSEC_PER_SEC));
	dispatch_source_set_event_handler(MKThemeTimer, ^{
		@try {
			KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
			if (![e isEnabled]) return;
			UIView *root = MKKeyboardRoot;
			if (!root || !root.window) return;
			if (![e hideSystemKeyBackground]) {
				root.backgroundColor = [e keyboardBackgroundColorForView:root];
			}
			MKApplyKeycapHeuristic(root, 0);
			if ([e toolbarEnabled] && [[MergedKBToolbar shared] shouldShowInCurrentApp]) {
				[[MergedKBToolbar shared] attachToDock:root];
			}
		} @catch (NSException *exception) { }
	});
	dispatch_resume(MKThemeTimer);
}

static void MKHandleKeyboardRoot(UIView *root) {
	if (!root) return;
	@try {
		CFTimeInterval now = CACurrentMediaTime();
		if (MKLastHandleRun > 0 && now - MKLastHandleRun < 1.0) return;
		MKLastHandleRun = now;

		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
		BOOL target = [bid hasPrefix:@"com.tencent.wetype"] ||
		              [bid isEqualToString:@"com.tencent.xin"];
		if (!target) return;
		MKKeyboardRoot = root;

		if ([e isEnabled]) {
			if (![e hideSystemKeyBackground]) {
				root.backgroundColor = [e keyboardBackgroundColorForView:root];
			}
			MKApplyKeycapHeuristic(root, 0);
			if ([e toolbarEnabled] && [[MergedKBToolbar shared] shouldShowInCurrentApp]) {
				[[MergedKBToolbar shared] attachToDock:root];
			}
		}

		// 状态行：无条件显示，不依赖任何开关，保证永远有反馈
		[[root viewWithTag:99001] removeFromSuperview];
		UILabel *lb = [[UILabel alloc] initWithFrame:
			CGRectMake(4, 2, root.bounds.size.width - 8, 15)];
		lb.tag = 99001;
		lb.font = [UIFont systemFontOfSize:9];
		lb.textColor = [UIColor yellowColor];
		lb.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
		lb.text = [NSString stringWithFormat:
			@"MK已加载✅ enabled=%@ prefs=%@ WBMain=%@ WBKey=%@ Dock=%@",
			[e isEnabled] ? @"1" : @"0",
			[[e prefsSource] substringToIndex:MIN(6u, [e prefsSource].length)],
			NSClassFromString(@"WBMainInputView") ? @"1" : @"0",
			NSClassFromString(@"WBKeyView") ? @"1" : @"0",
			NSClassFromString(@"UIKeyboardDockView") ? @"1" : @"0"];
		[root addSubview:lb];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });

		// 把诊断报告直接打进正在编辑的文本框（唯一不依赖完全访问的文本通道）
		MKInsertDiagnosticText();

		if (![e debugEnabled] || MKReportWritten) return;
		MKReportWritten = YES;

		NSString *probe = MKClassProbe();
		int budget = 70;
		NSMutableString *tree = [NSMutableString string];
		[tree appendString:@"\n=== 键盘视图树 ===\n"];
		MKDumpViewTree(root, 0, tree, &budget);

		NSString *report = [NSString stringWithFormat:
			@"进程: %@\n%@\n%@\n%@", bid, [e debugSummary], probe, tree];

		@try { [UIPasteboard generalPasteboard].string = report; } @catch (NSException *x) { }
		for (NSString *p in @[@"/var/mobile/Library/Preferences/com.merged.keyboard.debug.txt",
		                      @"/var/mobile/com.merged.keyboard.debug.txt"]) {
			@try { [report writeToFile:p atomically:YES
			                      encoding:NSUTF8StringEncoding error:nil]; }
			@catch (NSException *x) { }
		}
	} @catch (NSException *exception) { }
}

/*
 * 1.1.3：剪贴板写不进去（键盘没开「完全访问」）、Filza 也不是人人有。
 * 唯一 100% 可用的文本通道就是 textDocumentProxy 的 insertText: —— 键盘永远有权限
 * 往正在编辑的文本框里插字。诊断开关打开后，弹出键盘会把报告直接打进文本框。
 */
static void MKInsertDiagnosticText(void) {
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e debugEnabled]) return;
		if (MKReportWritten) return;

		UIView *root = MKKeyboardRoot;
		if (!root) return;
		UIResponder *r = [root nextResponder];
		id proxy = nil;
		int guard = 0;
		while (r && guard++ < 8) {
			if ([r isKindOfClass:[UIInputViewController class]]) {
				proxy = [(UIInputViewController *)r textDocumentProxy];
				break;
			}
			r = [r nextResponder];
		}
		if (!proxy) { MKReportWritten = YES; return; }
		MKReportWritten = YES;

		NSMutableString *out = [NSMutableString string];
		[out appendString:@"===MK诊断开始===\n"];
		[out appendFormat:@"enabled=%d 圆角=%d 边框=%d 阴影=%d 候选=%d 工具栏=%d\n",
			[e isEnabled] ? 1 : 0,
			[e enableCornerRadius] ? 1 : 0,
			[e enableKeyBorder] ? 1 : 0,
			[e enableKeyShadow] ? 1 : 0,
			[e enableCandidateColor] ? 1 : 0,
			[e toolbarEnabled] ? 1 : 0];
		[out appendFormat:@"深色=%@ 浅色=%@\n",
			[e keyboardBackgroundColorForView:nil] ? @"有值" : @"空",
			MKViewIsDarkMode(root) ? @"(当前深色)" : @"(当前浅色)"];

		// 视图树：紧凑一行一个节点，最多 22 个
		int budget = 22;
		NSMutableString *tree = [NSMutableString string];
		MKDumpViewTree(root, 0, tree, &budget);
		[out appendString:@"---视图树---\n"];
		[out appendString:tree];
		[out appendString:@"===MK诊断结束===\n"];

		[proxy insertText:out];
	} @catch (NSException *exception) { }
}

// 判断某个视图是否位于键盘视图树内部（含根视图本身）
static BOOL MKIsInKeyboardTree(UIView *v) {
	UIView *root = MKKeyboardRoot;
	if (!root || !v) return NO;
	if (v == root) return YES;
	UIView *x = v;
	int guard = 0;
	while (x.superview && guard++ < 10) {
		x = x.superview;
		if (x == root) return YES;
	}
	return NO;
}

%hook UIView
/*
 * 1.2.0 —— 照原版 keyboardhook 的做法：hook setBackgroundColor:
 * 原版 dylib 里就带着 setBackgroundColor 这个方法名，说明它是在「对方设置背景的瞬间」
 * 把颜色替换掉的。我们之前一直是事后补色，每次都被微信下一帧改成原值，所以永远看不见。
 */
- (void)setBackgroundColor:(UIColor *)color {
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if ([e isEnabled] && ![e hideSystemKeyBackground] && MKIsInKeyboardTree(self)) {
			CGFloat w = self.bounds.size.width;
			// 只替换「面板」级别的背景（整行/整块），不去碰单个键帽，
			// 否则键帽会被糊成一片分不出来。
			if (w >= 150.0) {
				%orig([e keyboardBackgroundColorForView:self]);
				return;
			}
		}
	} @catch (NSException *exception) { }
	%orig;
}

/*
 * 1.1.3：光靠定时器还不够 —— 微信输入法在自己的 layout 里会重新设置 layer 属性，
 * 0.6 秒后再补也没用。这里直接在每次布局结束的瞬间补一次，紧跟对方后面执行。
 */
- (void)layoutSubviews {
	%orig;
	@try {
		KeyboardThemeEngine *e = [KeyboardThemeEngine shared];
		if (![e isEnabled]) return;
		BOOL wantDeco = [e enableCornerRadius] || [e enableKeyBorder] || [e enableKeyShadow];
		if (!wantDeco) return;
		if (!MKLooksLikeKeycap(self)) return;
		MKApplyKeyDecoration(self);
	} @catch (NSException *exception) { }
}

- (void)didMoveToWindow {
	%orig;
	@try {
		if (self.window == nil) return;

		// 沿响应者链向上找 UIInputViewController（不能只查一层：
		// 深层子视图的 nextResponder 先是它的 superview，不是控制器）
		UIResponder *r = [self nextResponder];
		int guard = 0;
		while (r && guard++ < 12) {
			if ([r isKindOfClass:[UIInputViewController class]]) {
				MKHandleKeyboardRoot([(UIInputViewController *)r view]);
				return;
			}
			r = [r nextResponder];
		}
		// 兜底：从 superview 链爬到根视图再看它的控制器
		UIView *v = self;
		int g2 = 0;
		while (v.superview && g2++ < 12) v = v.superview;
		UIResponder *rr = [v nextResponder];
		if ([rr isKindOfClass:[UIInputViewController class]]) {
			MKHandleKeyboardRoot([(UIInputViewController *)rr view]);
		}
	} @catch (NSException *exception) { }
}
%end

%hook UIWindow
- (void)didAddSubview:(UIView *)subview {
	%orig;
	@try {
		UIViewController *vc = self.rootViewController;
		if ([vc isKindOfClass:[UIInputViewController class]]) {
			MKHandleKeyboardRoot(vc.view);
		}
	} @catch (NSException *exception) { }
}
%end

%hook UIInputViewController
- (void)viewDidAppear:(BOOL)animated {
	%orig;
	@try {
		MKHandleKeyboardRoot(self.view);
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
		// 键帽动态创建，只有周期重扫才能覆盖到后建的按键
		MKStartThemeTimer();

		// 1.1.1：无条件的「加载证明」，排掉一切开关因素。
		// 只要文件出现，就说明 dylib 确实被加载了；不出现就是加载/注入层面的问题。
		@try {
			NSString *line = [NSString stringWithFormat:
				@"MergedKeyboard loaded. bid=%@ pid=%d date=%@\n",
				bid, (int)getpid(), [NSDate date]];
			for (NSString *p in @[@"/var/mobile/Library/Preferences/com.merged.keyboard.loaded.txt",
			                      @"/var/mobile/com.merged.keyboard.loaded.txt"]) {
				[line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
			}
		} @catch (NSException *exception) { }

		// 诊断：装了 1.0.4 后打开微信，3 秒后会弹出插件实际读到的值
		MKShowDebugIfNeeded();
	}
}
