//
//  KeyboardThemeEngine.h
//  MergedKeyboard
//
//  键盘主题引擎（全新实现，对应原 Keyboardhook 的视觉定制能力）。
//  集中管理偏好读取与各类配色 / 边框 / 阴影 / 圆角逻辑，避免在各个 %hook 中重复代码。
//

#import <UIKit/UIKit.h>

@interface KeyboardThemeEngine : NSObject

+ (instancetype)shared;

/// 从 CFPreferences 重新读取所有设置（收到 Darwin 通知时调用）
- (void)reloadPrefs;

#pragma mark - 总开关
- (BOOL)isEnabled;

#pragma mark - 背景色（深浅色双值，根据视图当前的 userInterfaceStyle 选择）
/// 键盘整体背景色（UIKeyboardDockView / UIInputView / UIKBBackdropView 等）
- (UIColor *)keyboardBackgroundColorForView:(UIView *)view;
/// 是否隐藏系统键盘背景（把 UIKBBackdropView 设为透明）
- (BOOL)hideSystemKeyBackground;

#pragma mark - 候选栏
- (BOOL)enableCandidateColor;
- (UIColor *)candidateTextColorForView:(UIView *)view;
- (BOOL)enableCandidateGradientColor;
/// 候选栏背景（线性渐变层用到的两个颜色）
- (UIColor *)candidateGradientColorForView:(UIView *)view;
- (BOOL)hideSeparatorLine;

#pragma mark - 圆角
- (BOOL)enableCornerRadius;
- (CGFloat)cornerRadius;
- (BOOL)enableSystemKeyboardCorner;
- (CGFloat)systemKeyboardCornerRadius;

#pragma mark - 中/英切换键
- (BOOL)hideChineseEnglish;

#pragma mark - 键帽边框
- (BOOL)enableKeyBorder;
- (UIColor *)keyBorderColorForView:(UIView *)view;
- (CGFloat)keyBorderOpacity;
- (CGFloat)keyBorderWidth;

#pragma mark - 键帽阴影
- (BOOL)enableKeyShadow;
- (CGFloat)keyShadowOpacity;
- (CGFloat)keyShadowOffsetX;
- (CGFloat)keyShadowOffsetY;
- (CGFloat)keyShadowRadius;

#pragma mark - 微信功能栏开关
- (BOOL)toolbarEnabled;

#pragma mark - 诊断（1.0.4 新增）
/// 设置里的「显示诊断信息」开关；打开后宿主 App 启动 3 秒会弹窗显示插件实际读到的值
- (BOOL)debugEnabled;

/// 偏好是从哪读到的（CFPreferences / 兜底文件），诊断用
- (NSString *)prefsSource;
/// 诊断文本：进程 / 偏好来源 / 各项实际值 / 微信私有类是否存在
- (NSString *)debugSummary;

@end

/*
 * ⚠️ 这两个函数是纯 C 符号，定义在 KeyboardThemeEngine.m（C 链接）里，
 * 而 Tweak.xm 是 Logos 源文件、会按 ObjC++ 编译 —— 不包 extern "C" 的话
 * C++ 端会去找 __Z16MKViewIsDarkModeP6UIView 这种修饰名，链接必然失败
 * （报错：ld: symbol(s) not found for architecture arm64e）。
 */
#ifdef __cplusplus
extern "C" {
#endif

/// 工具函数：把 "#RRGGBB" / "#RRGGBBAA" 解析成 UIColor（支持带 # 或不带）
UIColor *MKColorFromHex(NSString *hex);
/// 判断某个视图当前是否处于深色模式
BOOL MKViewIsDarkMode(UIView *view);

#ifdef __cplusplus
}
#endif
