# EchoType

EchoType 是一个 macOS 原生离线语音转文字 menubar 应用。

它支持全局热键触发录音，将语音转写为文本后写入剪贴板，并可在已授权场景下自动粘贴到当前输入框。

## 功能概览

- 全局热键一键开始/结束录音（默认 `⌥ ⌘ Space`，支持在设置中直接按键录入）
- 本地离线转写，支持 `Whisper` 与 `Qwen3-ASR (Local CLI)`
- 文本注入支持两种模式：仅剪贴板、剪贴板+自动粘贴（失败自动回退）
- 设置页支持热键编辑、权限引导、运行时安装/检测、模型安装/删除
- 默认不保留临时录音文件（可在设置中开启保留）

## 系统要求

- macOS 13+
- 麦克风权限（录音必需）
- 辅助功能权限（自动粘贴可选，未授权时仍可复制）

## 安装（普通用户）

### 方式 A：Homebrew（推荐）

```bash
brew tap smoosex/tap
brew install --cask echotype
```

或单行安装：

```bash
brew install --cask smoosex/tap/echotype
```

### 方式 B：GitHub Releases（DMG）

1. 下载 `EchoType-<version>.dmg`
2. 打开后拖拽 `EchoType.app` 到 `Applications`
3. 首次启动按提示授予权限

说明：当前公开产物默认是 ad-hoc 签名。若遇到系统阻止启动，可在 Finder 中右键应用选择“打开”，或在系统“隐私与安全性”中允许。

## 首次使用

1. 首次启动会自动弹出 Welcome Guide，按引导完成麦克风/辅助功能权限，并阅读使用说明
2. 可勾选 `Don't show this guide again`，后续启动不再自动显示（仍可从菜单 `Welcome Guide` 手动打开）
3. 点击 `Start Using EchoType` 会自动进入 Settings 页面
4. 在 `General` 标签页点击热键录制框，直接按键设置快捷键（注册失败会提示原因并自动回退默认 `⌥⌘Space`）
5. 在 `Engine` 标签页安装或检测运行时，安装模型
6. 回到主界面按热键开始录音，再按一次结束并等待转写

## 运行时与模型

### Whisper

- Runtime：建议通过 Homebrew 安装 `whisper.cpp`
- 在设置中可点击 `Detect` 自动检测可执行文件
- 模型支持应用内安装、暂停/继续、取消、删除

### Qwen3-ASR

- 通过本地 `qwen-asr-cli` 执行转写（不再依赖应用内本地服务）
- 在设置中可点击 `Detect` 自动检测 `qwen-asr`
- Runtime 安装入口提供命令提示：
  - `brew install qwen-asr-cli`
  - 或 `python -m pip install qwen-asr-cli`
- 模型支持应用内安装、删除

## 本地开发

```bash
swift build
swift run
```

## 发布打包（维护者）

手动打包：

```bash
scripts/package.sh \
  --version 1.0.0 \
  --app-name EchoType \
  --binary-name echotype \
  --bundle-id com.smoose.echotype
```

本地上传到 GitHub Release（推荐，避免云端构建环境差异）：

```bash
scripts/release.sh \
  --version 1.0.0 \
  --repo smoosex/echo-type \
  --tap-repo smoosex/homebrew-tap
```

说明：
- 该脚本会读取本地 `dist/` 产物并上传到对应 tag 的 GitHub Release。
- 会基于本地 dmg 自动生成 `dist/echotype.rb` 并上传。
- `--tap-repo` 可选；不传则只上传 Release 资产，不同步 Homebrew tap。
- 若传 `--tap-repo`，脚本会通过 SSH (`git@github.com:<owner>/<repo>.git`) 同步，请先配置 GitHub SSH key。

更多分发细节见：`docs/distribution_and_installation.md`。

## 维护者测试环境

当前发布流程以维护者本机环境打包验证为准。已验证环境：

- macOS Tahoe 26.3
- Apple Silicon（arm64）
- Xcode Command Line Tools（Swift 6.2.x）
- Homebrew（用于安装/验证 cask）

## 完整卸载

```bash
scripts/uninstall.sh
```

常用参数：

```bash
scripts/uninstall.sh --dry-run
scripts/uninstall.sh --yes
```

## 隐私说明

- 默认不上传音频或转写文本到外部服务
- 默认不持久化原始录音文件
- 日志用于诊断，不记录原始音频内容
