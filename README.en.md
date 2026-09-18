# Rounded-Corner ICO Converter

[中文](README.md) | English

A Windows desktop utility that converts PNG, JPG, and JPEG images into
multi-size ICO files with rounded corners.

Version **2.0.0** includes:

- A C# / Windows Forms graphical interface;
- A PowerShell image conversion engine;
- Application icon, manifest, and local build scripts;
- A drag-and-drop CMD entry point;
- A standalone EXE published under `release/`.

## Features

- Drag-and-drop and batch image selection;
- Center crop to a square;
- Optional trimming of transparent or solid-color borders;
- Adjustable corner radius (0%–50%) and transparent padding (0%–20%);
- 8× supersampling for smooth transparent edges;
- Automatic EXIF orientation handling;
- Seven 32-bit PNG layers: 16, 24, 32, 48, 64, 128, and 256 pixels;
- Dark-rim correction for transparent black borders;
- Remembered output directory and UI settings.

## Standalone EXE

Download and run: [图片转圆角ICO.exe](release/图片转圆角ICO.exe)

The EXE embeds the PowerShell conversion engine. It does not need the adjacent
`_app` or `_engine` folders, Python, ImageMagick, or an Internet connection.
Copy the EXE to any writable folder and run it.

By default, output is written to a `修改图标存放` folder next to the EXE. If
the EXE is placed under a protected location such as `C:\Program Files`, choose
a writable output folder in the application.

## Runtime Environment

- Windows 10 or Windows 11;
- .NET Framework 4.x (normally preinstalled on Windows 10/11);
- Windows PowerShell 5.1;
- A writable temporary directory and output directory;
- No Python, ImageMagick, or network access required.

This is a Windows Forms desktop application. It is not intended for macOS,
Linux, or Windows Server Core without desktop components.

## Repository Layout

```text
.
├─ _app/                         C# UI source, icon, and build scripts
├─ _engine/
│  └─ png-jpg-to-ico.ps1        Image conversion engine
├─ release/
│  └─ 图片转圆角ICO.exe          Standalone release build
├─ 转换PNG-JPG到ICO.cmd          Drag-and-drop command entry point
├─ README.md                     Chinese documentation
└─ README.en.md                  English documentation
```

## Build

Requirements:

- Windows 10 or Windows 11;
- The .NET Framework 4.x C# compiler;
- Windows PowerShell 5.1.

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_app\build.ps1
```

The generated file is:

```text
.\图片转圆角ICO.exe
```

The build script embeds the conversion engine in the EXE. Copy the result to
`release/` when preparing a new standalone release.

To regenerate the application icon:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_app\make-icon.ps1
```

## Usage

### Graphical interface

1. Open `图片转圆角ICO.exe`;
2. Drop images into the window or click the file selection button;
3. Adjust radius, padding, and border trimming;
4. Select an output folder and start the conversion.

### PowerShell

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\_engine\png-jpg-to-ico.ps1 `
  .\logo.png `
  -RadiusPercent 28 `
  -PaddingPercent 0 `
  -TrimBorder
```

### CMD drag-and-drop

Drop one or more images onto `转换PNG-JPG到ICO.cmd`. Output is written to
`修改图标存放` by default.

## Settings

The graphical interface stores settings at:

```text
%APPDATA%\图片转圆角ICO\settings.ini
```

Delete that file to restore the defaults.

## License

No open-source license is included yet. Add the license that matches your
intended redistribution terms before publishing a public release.
