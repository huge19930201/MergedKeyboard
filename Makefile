# MergedKeyboard — 合并版键盘增强插件
# 功能：微信输入法键盘主题（背景/圆角/边框/阴影/候选栏配色/深浅色）
#      + 微信输入法顶部功能栏（来自 WXKBToolbar）
#
# 构建环境：Theos + iOS SDK。打包方案（rootless / roothide）由 CI 传入。
#
# 本工程为全新重写的开源实现，不含任何付费授权 / 激活校验逻辑。
#
# ⚠️ 只产出一个 dylib，只注入微信输入法键盘扩展（com.tencent.wetype.keyboard）。
# 微信输入法本身就是系统级输入法，任何 App 里弹出的都是它，
# 所以只需要注入它一个进程，就能在所有 App 里生效，
# 同时彻底避开「注入所有 UIKit 进程」带来的黑屏风险。

TARGET := iphone:clang:latest:14.0
ARCHS := arm64e arm64

INSTALL_TARGET := root
TWEAK_NAME = MergedKeyboard

MergedKeyboard_FILES = Tweak.xm KeyboardThemeEngine.m MergedKBToolbar.m
MergedKeyboard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MergedKeyboard_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# 安装后重启 SpringBoard / 相关进程让键盘重新加载
after-install::
	@echo "重新加载 SpringBoard 以生效..."
	@if [ -x "$(THEOS)/bin/restart" ]; then $(THEOS)/bin/restart; \
	 else killall -9 SpringBoard 2>/dev/null || true; fi

# 清理
clean::
	rm -rf .theos

.SHELLFLAGS = -ec
