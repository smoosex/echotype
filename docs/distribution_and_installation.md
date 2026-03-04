# 分发与安装说明

本文档说明如何将 EchoType 作为可下载的 macOS 应用发布，以及如何通过 Homebrew 安装。

## 1. 用户安装路径（GitHub Release）

每次发布时，请在 GitHub 上传以下产物：

- `EchoType-<version>.dmg`（推荐）
- `EchoType-<version>.macos.zip`（兜底）
- `EchoType-<version>.checksums.txt`

终端用户安装步骤：

1. 在 Releases 页面下载 `EchoType-<version>.dmg`。
2. 打开 dmg，将 `EchoType.app` 拖入 `Applications` 快捷入口。
3. 在 Applications 中启动 `EchoType.app`。
4. 按提示授予麦克风权限。

## 2. 维护者打包命令

在仓库根目录运行：

```bash
scripts/package.sh \
  --version 1.0.0 \
  --app-name EchoType \
  --binary-name echotype \
  --bundle-id com.smoose.echotype
```

输出目录：`dist/`
发布包默认不内置 Runtime。
用户需要在应用设置中安装 Runtime 与模型。

## 3. 本地上传到 GitHub Release（当前推荐）

为避免云端构建环境与本机 UI/SDK 观感不一致，发布流程改为“本地打包 + 本地上传”。

先本地打包：

```bash
scripts/package.sh \
  --version 1.0.0 \
  --app-name EchoType \
  --binary-name echotype \
  --bundle-id com.smoose.echotype
```

再上传到 GitHub Release：

```bash
scripts/release.sh \
  --version 1.0.0 \
  --repo smoosex/echo-type \
  --tap-repo smoosex/homebrew-tap
```

脚本行为：

- 从本地 `dist/` 读取 `dmg/zip/checksums`
- 自动计算本地 `dmg` 的 SHA256 并生成 `dist/echotype.rb`
- 将上述文件上传到 `v<version>` 对应的 GitHub Release
- 如提供 `--tap-repo`，同步更新 tap 仓库 `Casks/echotype.rb`
- tap 同步使用 SSH 地址 `git@github.com:<owner>/<repo>.git`，需提前配置 GitHub SSH key

## 4. Homebrew 安装

`scripts/release.sh` 会自动生成 `dist/echotype.rb`，并在提供 `--tap-repo` 时同步到 tap 仓库。

推荐仓库结构：

- 单独创建 tap 仓库：`homebrew-tap`
- 将 cask 文件放到 `Casks/echotype.rb`

用户安装命令：

```bash
brew tap smoosex/tap
brew install --cask echotype
```

或单行安装：

```bash
brew install --cask smoosex/tap/echotype
```

## 5. 已知限制

当前脚本产物默认使用 ad-hoc 签名。
若希望终端用户首次启动体验更平滑，后续发布加固需增加 Developer ID 签名与 notarization。

## 6. 完整卸载

仓库提供完整清理脚本：

```bash
scripts/uninstall.sh
```

常用参数：

```bash
scripts/uninstall.sh --dry-run
scripts/uninstall.sh --yes
```

脚本会删除应用二进制、应用数据、偏好设置、兜底 Runtime 和临时 EchoType 文件。
