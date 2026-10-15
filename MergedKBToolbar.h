//
//  MergedKBToolbar.h
//  MergedKeyboard
//
//  微信键盘功能栏（全新实现，对应原 WXKBToolbar）。
//  在键盘 Dock 上方插入一条可横向滚动的功能按钮栏，提供常用快捷操作。
//  默认仅在微信中显示，可通过 shouldShowInCurrentApp 调整判定逻辑。
//

#import <UIKit/UIKit.h>

@interface MergedKBToolbar : NSObject

+ (instancetype)shared;

/// 当前前台 App 是否应显示功能栏（默认：微信 com.tencent.xin）
- (BOOL)shouldShowInCurrentApp;

/// 把功能栏挂到键盘 Dock 上（在 UIKeyboardDockView layoutSubviews 中调用）
- (void)attachToDock:(UIView *)dockView;

/// 从 Dock 上移除（App 切换 / 键盘收起时）
- (void)detach;

@end
