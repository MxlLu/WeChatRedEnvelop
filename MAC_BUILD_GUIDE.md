# Mac 电脑编译与打包完整指南

本指南专为在 macOS 电脑上编译打包本项目编写。

---

## 一、Mac 基础环境准备（仅首次需要，2分钟）

### 1. 确保安装了 Xcode 命令行工具
打开 Mac 的【终端】（Terminal），运行：
```bash
xcode-select --install
```
*如果提示已安装则忽略。*

### 2. 一键安装 Theos 构建框架
在 Mac 终端执行官方脚本一键安装：
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```
或者手动克隆并配置环境变量：
```bash
git clone --recursive https://github.com/theos/theos.git ~/theos
echo 'export THEOS=~/theos' >> ~/.zshrc
source ~/.zshrc
```

*(可选) 如需打包 deb 格式，推荐通过 Homebrew 安装打包依赖：*
```bash
brew install ldid dpkg
```

---

## 二、进入项目目录

将解压后的源码目录拖入终端，或者：
```bash
cd /path/to/WeChatRedEnvelop
```

---

## 三、三种环境打包编译命令

### 1. 无根越狱包（Dopamine / Palera1n / iOS 15+）
在终端中执行：
```bash
THEOS_PACKAGE_SCHEME=rootless make clean package FINALPACKAGE=1
```
- **输出产物**：`packages/com.swiftyper.wechatredenvelop_2.0.0_iphoneos-arm64.deb`
- **用途**：通过 Sileo / Zebra 安装到无根越狱手机上。

---

### 2. 传统有根越狱包（unc0ver / Checkra1n / iOS 14 及以下）
在终端中执行：
```bash
make clean package FINALPACKAGE=1
```
- **输出产物**：`packages/com.swiftyper.wechatredenvelop_2.0.0_iphoneos-arm.deb`
- **用途**：通过 Cydia / Zebra 安装到传统有根越狱手机上。

---

### 3. 巨魔 TrollStore / 免越狱注入（.dylib + .bundle）
如果要在非越狱手机（使用 TrollStore / 证书签名注入）上使用：
```bash
make clean all FINALPACKAGE=1
```
- **输出产物**：
  - 动态链接库文件：`.theos/obj/WeChatRedEnvelop.dylib`
  - 资源包：`Resources/com.swiftyper.wechatredenvelop.bundle`
- **用途**：使用 Sideloadly、Azule 或 TrollStore 直接将 `.dylib` 和 `.bundle` 注入到脱壳后的微信 `.ipa` 中。

---

## 四、常见问题

1. **提示 `Theos directory not found`**：
   确保执行了 `export THEOS=~/theos`，或者检查 `ls ~/theos` 是否存在。
2. **提示缺少 `iPhoneOS.sdk`**：
   现代 Xcode 默认自带最新 iOS SDK。如果 Theos 提示缺少特定版本 SDK，可从 [theos/sdks](https://github.com/theos/sdks) 下载对应的 `iPhoneOSXX.X.sdk` 放入 `~/theos/sdks/` 目录。
