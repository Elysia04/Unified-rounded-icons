# 图片转圆角 ICO

Windows 图形工具：把 PNG、JPG、JPEG 图片转换成带圆角的多尺寸 ICO 图标。

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
└─ README.md
```

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

EXE 会把转换引擎嵌入程序集，因此生成后可以单独使用。

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

仓库只保留源码和构建素材。编译生成的 EXE、转换结果和运行日志已由
`.gitignore` 排除，建议把 EXE 作为 GitHub Release 附件发布。

本仓库暂未附带开源许可证；公开发布前请根据你的授权意愿选择并添加许可证。
