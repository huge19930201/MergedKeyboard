# MergedKeyboard — 合并版键盘增强插件
# 功能：微信键盘功能栏（来自 WXKBToolbar）+ 键盘主题引擎（来自 Keyboardhook）
# 构建环境：macOS + Theos + 新版 iOS SDK（rootless 布局）
#
# 注意：本工程为全新重写的开源实现，不含任何付费授权 / 激活校验逻辑。

# 目标 SDK 取 theos/sdks 中最新的（当前 16.5），最小部署版本 14.0
TARGET := iphone:clang:latest:14.0
# 主推 arm64e，同时保留 arm64 以兼容老设备 / 旧越狱
ARCHS := arm64e arm64

INSTALL_TARGET := root
THEOS_PACKAGE_SCHEME := rootless
TWEAK_NAME := MergedKeyboard

# ---- 源文件 ----
MergedKeyboard_FILES = Tweak.xm \
                       KeyboardThemeEngine.m \
                       MergedKBToolbar.m

# 用 ARC 简化内存管理
MergedKeyboard_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# 键盘相关私有类在 UIKit 内，不需要额外私有框架链接（运行时通过 NSClassFromString / %hook 获取）
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
