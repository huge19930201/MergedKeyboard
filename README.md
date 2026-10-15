# MergedKeyboard — 合并版键盘增强插件（全新重写）

把两个插件的**功能**合并进一个全新编写的 Theos 插件里：

| 来源插件 | 原名 | 功能 | 本次实现 |
| --- | --- | --- | --- |
| 微信输入法工具栏_骚强版 | `WXKBToolbar` | 微信键盘顶部功能栏 | `MergedKBToolbar`（Tweak.xm 中挂载） |
| Keyboardhook 2.1 | `com.baiy.keyboardhook` | 全键盘主题（背景/圆角/边框/阴影/候选栏/深浅色） | `KeyboardThemeEngine` + `Tweak.xm` 中一组 `%hook` |

> ⚠️ 原 Keyboardhook 内含 198 元付费授权 / 激活校验（SwitchAuthHelper、AuthorizationAlert）。
> **本次为全新开源重写，不复制任何授权 / DRM 逻辑，所有功能默认免费开放。**

---

## 功能清单

### 一、微信键盘功能栏（`toolbarEnabled`）
- 在微信（`com.tencent.xin`）键盘 Dock 顶部插入一条可横向滚动的按钮栏
- 默认按钮：换行 / 粘贴 / 清空 / 收到 / 好的 / 在的 / 马上处理 / 哈哈哈
- 操作作用于当前第一响应者输入框（通过 `UIKeyInput` / `UITextInput`）
- 按钮集合在 `MergedKBToolbar.m` 的 `items` 数组里自行增删即可

### 二、键盘主题引擎（`enabled` 总开关）
- 键盘背景色（深色 `darkColor` / 浅色 `lightColor`，随系统深浅色自动切换）
- 候选栏配色（文字/高亮色、渐变背景、隐藏分隔线）
- 键帽圆角（`cornerRadius`）、整块键盘圆角（`systemKeyboardCornerRadius`）
- 隐藏中/英切换键（微信安全键盘 `WBSecKeyboardKeyView`）
- 键帽边框（深色/浅色色值、不透明度、宽度）
- 键帽阴影（不透明度、偏移 X/Y、模糊半径）
- 隐藏系统键盘背景（透明化 `UIKBBackdropView` / `UIKBRenderConfig`）

所有开关在 **设置 → MergedKeyboard** 中配置，保存即通过 Darwin 通知 `com.merged.keyboard/ReloadPrefs` 实时生效（无需重启 App）。

---

## 文件结构

```
MergedKeyboard/
├── Makefile                       # Theos 构建脚本（rootless 布局，arm64/arm64e）
├── control                        # deb 包描述
├── MergedKeyboard.plist           # Substrate 注入过滤器（所有 UIKit 进程）
├── Tweak.xm                       # 主逻辑：所有 %hook + 通知监听 + %ctor
├── KeyboardThemeEngine.h/.m       # 主题引擎：偏好读取 + 配色/边框/阴影计算
├── MergedKBToolbar.h/.m           # 微信键盘功能栏
├── layout/
│   └── Library/PreferenceLoader/
│       └── Preferences/
│           └── com.merged.keyboard.plist   # 设置面板（PreferenceLoader spec）
└── README.md
```

---

## 构建与安装

需要：**macOS + 已配置好的 Theos + 新版 iOS SDK（rootless）**。

```bash
# 1. 把本目录放到 $THEOS/.. 或任意位置，cd 进入
cd MergedKeyboard

# 2. 构建 deb 包
make clean
make package

# 3. 安装到已连接 / 同一局域网的设备
make install          # 需要 THEOS_DEVICE_IP / THEOS_DEVICE_PORT
```

构建产物为 rootless 格式的 `.deb`，安装后 **重启 SpringBoard**（Makefile 的 `after-install` 会自动 killall）。

> 没有 macOS / Theos 环境时无法在本机编译（需 iOS SDK 与 clang）。本工程已写成可直接 `make` 的完整源码；如需我帮你调整按钮、配色默认值或支持更多 App，告诉我即可。

---

## 在 GitHub Actions 上自动编译（arm64e，无需 Mac）

工程已内置 `.github/workflows/build.yml`，借助 [Randomblock1/theos-action](https://github.com/Randomblock1/theos-action) 在 Linux runner 上自动装好 Theos + iOS SDK 并编译。

步骤：
1. 把本仓库推到 GitHub（见下方「推送到 GitHub」）。
2. 在 GitHub 仓库 **Actions** 页点 **Build MergedKeyboard (arm64e)** → **Run workflow**（或推送到 `main`/`master` 自动触发）。
3. 跑完后在 **Artifacts** 里下载 `MergedKeyboard-arm64e-rootless`（里面是 `packages/*.deb`）。
4. 想发正式版：打一个 tag（`git tag 1.0.0 && git push --tags`），workflow 会把 `.deb` 自动上传到 Release。

成品为 **rootless** 格式的 `iphoneos-arm64.deb`，内含 `arm64e` + `arm64` 两个架构（control 的 `Architecture: iphoneos-arm64` 同时覆盖两者），适配 Dopamine / palera1n rootless 等现代越狱。

> 若要出 **roothide** 版本，把 workflow 里的 `THEOS_PACKAGE_SCHEME=rootless` 改成 `THEOS_PACKAGE_SCHEME=roothide` 即可（或加一个 matrix job 同时出两种）。

---

## 推送到 GitHub

本机没有 `gh` 也没有你的 GitHub 凭证，仓库已在本地 `git init` 并提交。请执行以下命令把它推到你的 GitHub（把 `<你的用户名>` 换成实际用户名）：

```bash
cd MergedKeyboard
# 若还没在 GitHub 建仓库：先去 https://github.com/new 建一个名为 MergedKeyboard 的空仓库（不要勾 README）
git remote add origin https://github.com/<你的用户名>/MergedKeyboard.git
git branch -M main
git push -u origin main
```

之后每次 `git push` 都会自动触发编译。若已配置 SSH key，可把 `origin` 换成 `git@github.com:<你的用户名>/MergedKeyboard.git`。

---

## 与原插件的对应关系（便于对照）

| 原插件行为 | 现实现位置 |
| --- | --- |
| `UIKeyboardDockView` 注入顶部栏 | `MergedKBToolbar` + `Tweak.xm` 中 `UIKeyboardDockView layoutSubviews` |
| `enabled` / `darkColor` / `lightColor` 等 CFPreferences 读取 | `KeyboardThemeEngine -reloadPrefs` |
| `UIKBBackdropView` / `UIKBKeyBackgroundView` 背景与边框 | `Tweak.xm` 对应 `%hook` + `MKApplyKeyDecoration` |
| `UIKeyboardCandidateViewStyle` 候选栏配色 | `Tweak.xm` 中 `UIKeyboardCandidateViewStyle` 一组 getter 覆写 |
| `UIKBRenderConfig` / `UIKBRenderGeometry` 圆角 | `Tweak.xm` 中对应 `%hook` |
| `WBSecKeyboardKeyView` / `WBKeyView` / `WBConfigManager` 微信定制 | `Tweak.xm` 中对应 `%hook` |
| 付费授权系统 | **已移除（不实现）** |
