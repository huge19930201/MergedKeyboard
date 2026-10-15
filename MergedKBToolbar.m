//
//  MergedKBToolbar.m
//  MergedKeyboard
//
//  微信键盘功能栏实现。
//

#import "MergedKBToolbar.h"

// 微信主 Bundle ID（如需扩展到其它 App，在此处修改判定即可）
static NSString *const kWXBundleID = @"com.tencent.xin";

// 功能栏固定高度
static const CGFloat kBarHeight = 38.0;

@interface MergedKBToolbar ()
@property (nonatomic, strong) UIScrollView *bar;
@property (nonatomic, weak)   UIView *currentDock;
@end

#pragma mark - 获取当前第一响应者（文本输入）的分类
@interface UIResponder (MKFirstResponder)
+ (id)mk_currentFirstResponder;
@end
@implementation UIResponder (MKFirstResponder)
static __weak id mk_fr = nil;
+ (id)mk_currentFirstResponder {
	mk_fr = nil;
	// 向响应者链发送一个大家都响应的私有 action，由第一响应者捕获自身
	[[UIApplication sharedApplication] sendAction:@selector(mk_captureFirstResponder)
											   to:nil
											 from:nil
										 forEvent:nil];
	return mk_fr;
}
- (void)mk_captureFirstResponder { mk_fr = self; }
@end

@implementation MergedKBToolbar

+ (instancetype)shared {
	static MergedKBToolbar *inst = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		inst = [[MergedKBToolbar alloc] init];
	});
	return inst;
}

#pragma mark - 显示判定

- (BOOL)shouldShowInCurrentApp {
	NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
	if (bid.length == 0) return NO;
	return [bid isEqualToString:kWXBundleID];
}

#pragma mark - 挂载 / 卸载

- (void)attachToDock:(UIView *)dockView {
	if (!dockView) return;
	if (![self shouldShowInCurrentApp]) {
		[self detach];
		return;
	}
	if (self.currentDock == dockView && self.bar.superview == dockView) {
		[self _layoutBar];
		return;
	}
	[self.bar removeFromSuperview];
	self.currentDock = dockView;
	[dockView addSubview:self.bar];
	[dockView bringSubviewToFront:self.bar];
	[self _layoutBar];
}

- (void)detach {
	[self.bar removeFromSuperview];
	self.currentDock = nil;
}

#pragma mark - 布局

- (void)_layoutBar {
	if (!self.bar.superview) return;
	CGRect dockBounds = self.bar.superview.bounds;
	CGFloat w = CGRectGetWidth(dockBounds);
	CGFloat h = CGRectGetHeight(dockBounds);
	// 贴着 Dock 顶部放一条横栏
	CGRect frame = CGRectMake(0, 0, w, kBarHeight);
	// 若 Dock 高度太小则贴顶即可
	if (h < kBarHeight) frame.origin.y = 0;
	self.bar.frame = frame;

	// 计算按钮总宽度并允许横向滚动
	CGFloat x = 8;
	CGFloat btnH = kBarHeight - 12;
	CGFloat y = 6;
	for (UIView *v in self.bar.subviews) {
		if (![v isKindOfClass:[UIButton class]]) continue;
		CGSize sz = [v sizeThatFits:CGSizeMake(CGFLOAT_MAX, btnH)];
		CGFloat bw = MAX(sz.width + 24, 44);
		v.frame = CGRectMake(x, y, bw, btnH);
		x += bw + 8;
	}
	self.bar.contentSize = CGSizeMake(x, kBarHeight);
}

#pragma mark - 懒加载功能栏

- (UIScrollView *)bar {
	if (!_bar) {
		UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectZero];
		sv.backgroundColor = [UIColor secondarySystemBackgroundColor];
		sv.showsHorizontalScrollIndicator = NO;
		sv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		sv.layer.zPosition = 1000; // 确保在最上层
		// 默认按钮集合：快捷操作 + 常用短语
		NSArray<NSDictionary *> *items = @[
			@{@"t":@"换行",  @"a":@"newline"},
			@{@"t":@"粘贴",  @"a":@"paste"},
			@{@"t":@"清空",  @"a":@"clear"},
			@{@"t":@"收到",  @"a":@"收到"},
			@{@"t":@"好的",  @"a":@"好的"},
			@{@"t":@"在的",  @"a":@"在的"},
			@{@"t":@"马上处理", @"a":@"马上处理"},
			@{@"t":@"哈哈哈", @"a":@"哈哈哈"},
		];
		for (NSDictionary *it in items) {
			[sv addSubview:[self _makeButton:it[@"t"] action:it[@"a"]]];
		}
		_bar = sv;
	}
	return _bar;
}

- (UIButton *)_makeButton:(NSString *)title action:(NSString *)action {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	[b setTitle:title forState:UIControlStateNormal];
	b.titleLabel.font = [UIFont systemFontOfSize:14];
	b.backgroundColor = [UIColor systemFillColor];
	b.layer.cornerRadius = 8;
	b.tag = [self _tagForAction:action];
	[b addTarget:self action:@selector(_onTap:) forControlEvents:UIControlEventTouchUpInside];
	return b;
}

- (NSInteger)_tagForAction:(NSString *)action {
	// 用 tag 携带动作类型，避免额外成员变量
	if ([action isEqualToString:@"newline"]) return 1;
	if ([action isEqualToString:@"paste"])   return 2;
	if ([action isEqualToString:@"clear"])   return 3;
	return 100; // 直接插入该文本（文本即 action）
}

#pragma mark - 按钮事件

- (void)_onTap:(UIButton *)sender {
	NSString *title = [sender titleForState:UIControlStateNormal];
	NSInteger tag = sender.tag;
	if (tag == 1) {
		[self _insertText:@"\n"];
	} else if (tag == 2) {
		UIPasteboard *pb = [UIPasteboard generalPasteboard];
		if (pb.string.length) [self _insertText:pb.string];
	} else if (tag == 3) {
		[self _clearText];
	} else {
		// 短语：直接插入按钮标题
		[self _insertText:title];
	}
}

#pragma mark - 操作当前输入框

/// 找到当前第一响应者（文本输入）
- (id)_currentTextInput {
	return [UIResponder mk_currentFirstResponder];
}

- (void)_insertText:(NSString *)text {
	id input = [self _currentTextInput];
	if ([input respondsToSelector:@selector(insertText:)]) {
		[input insertText:text];
	}
}

- (void)_clearText {
	id input = [self _currentTextInput];
	if ([input respondsToSelector:@selector(selectAll:)] &&
		[input respondsToSelector:@selector(replaceRange:withText:)]) {
		[input selectAll:nil];
		UITextRange *range = [input selectedTextRange];
		if (range) [input replaceRange:range withText:@""];
	}
}

@end
