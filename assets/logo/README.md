# EchoType Logo 资源说明

本目录包含 EchoType 应用的初版 Logo 设计稿。

- `echotype-logo-primary.svg`：主视觉彩色 Logo
- `echotype-logo-monochrome.svg`：兜底使用的单色 Logo
- `AppIcon.icns`：用于发布打包的 macOS 应用图标

## 建议用法

- 产品/文档/网站：`echotype-logo-primary.svg`
- 简化图标场景（小尺寸、高对比需求）：`echotype-logo-monochrome.svg`

## 导出 App Icon

可直接从 SVG 生成 `.icns`：

```bash
scripts/generate_app_icon.sh
```

如果需要手动导出，可使用任意矢量工具（Figma、Sketch、Illustrator、Inkscape、Affinity Designer）导出以下尺寸 PNG：

- `1024x1024`（基础尺寸）
- `512x512`
- `256x256`
- `128x128`
- `64x64`
- `32x32`
- `16x16`

然后基于完整的 `AppIcon.appiconset` 或 `iconset` 目录生成最终 `.icns`。
