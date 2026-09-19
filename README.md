# 图片转圆角 ICO

[English](README.en.md) | 中文

这是一个把 PNG、JPG、JPEG 图片转换成带圆角、多尺寸 ICO 文件的 Windows 工具。

推荐先在 Android 手机上使用应用图标提取工具（例如 **Apk Extractor**）
导出原始应用图标，再用本工具制作 ICO。本工具会提取图片边缘颜色来填充圆角区域，
并生成统一的圆角和透明边缘，让不同来源的图标在 Windows 桌面上更加整齐、美观。

当前版本为 **2.0.0**，完整源码包括：

- C# / Windows Forms 图形界面；
- PowerShell 图片转换引擎；
- 应用图标、清单与本地构建脚本；
- 拖放式 CMD 入口。

## 功能

- 支持拖放、批量选择图片；
- 中心裁剪为正方形；
- 可选自动裁掉透明或纯色空白边；
- 可调圆角（0%～50%）和透明边距（0%～20%）；
- 8 倍超采样生成平滑透明边缘；
- 自动处理 EXIF 方向；
- 输出 16、24、32、48、64、128、256 七个 32 位 PNG 图层；
- 自动修正透明黑边导致的暗角；
- 记忆输出目录和界面设置。

## 目录

```text
.
├─ _app/                         C# 界面源码、图标和构建脚本
├─ _engine/
│  └─ png-jpg-to-ico.ps1        图片转换引擎
├─ 转换PNG-JPG到ICO.cmd          拖放式命令行入口
├─ README.md                     中文说明
└─ README.en.md                  English documentation
```

## 独立运行版

可在 GitHub Releases 下载并运行：[下载最新 EXE](https://github.com/Elysia04/Unify-Icon-Rounded-Corners/releases/latest)

EXE 已经把 PowerShell 转换引擎嵌入程序，运行时不需要旁边的 `_app`、
`_engine` 或 Python、ImageMagick。把 EXE 复制到任意可写目录即可使用。

默认输出目录是 EXE 旁边的 `修改图标存放`。如果 EXE 放在
`C:\Program Files` 等无写权限目录，请在界面中选择一个有写权限的输出目录。

## 运行环境

- Windows 10 或 Windows 11；
- .NET Framework 4.x（Windows 10/11 通常已预装）；
- Windows PowerShell 5.1；
- 可写的临时目录和输出目录；
- 不需要 Python、ImageMagick 或网络连接。

本程序是 Windows Forms 桌面程序，不能直接运行在 macOS、Linux 或 Windows
Server Core 等没有桌面组件的环境。

## 构建 EXE

要求：

- Windows 10 或 Windows 11；
- 系统自带的 .NET Framework 4.x C# 编译器；
- Windows PowerShell 5.1。

在仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_app\build.ps1
```

生成文件：

```text
.\图片转圆角ICO.exe
```

EXE 会把转换引擎嵌入程序集，因此生成后可以单独使用。构建出的 EXE
可作为 GitHub Release 的附件上传。

如需重新生成应用图标：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_app\make-icon.ps1
```

## 使用

### 图形界面

1. 构建并打开 `图片转圆角ICO.exe`；
2. 拖入图片或点击“选择图片”；
3. 调整圆角、透明边距和自动裁边；
4. 选择输出目录并开始转换。

### PowerShell

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\_engine\png-jpg-to-ico.ps1 `
  .\logo.png `
  -RadiusPercent 28 `
  -PaddingPercent 0 `
  -TrimBorder
```

### CMD 拖放

把一张或多张图片拖到 `转换PNG-JPG到ICO.cmd` 上。输出默认位于
`修改图标存放` 文件夹。

## 设置位置

图形界面设置保存在：

```text
%APPDATA%\图片转圆角ICO\settings.ini
```

删除该文件即可恢复默认设置。

## 发布到 GitHub

源码位于 `_app/` 和 `_engine/`，可独立运行的 EXE 发布在 GitHub Releases
的 Assets 中。转换结果和运行日志仍由 `.gitignore` 排除。

本仓库暂未附带开源许可证；公开发布前请根据你的授权意愿选择并添加许可证。
