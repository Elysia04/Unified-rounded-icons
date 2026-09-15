# PNG/JPG to Rounded‑Corner ICO
This is a Windows small utility that requires neither Python nor ImageMagick. It will:
‑ Crop a square from the center of PNG, JPG, JPEG images;
‑ Generate rounded‑corner transparent edges with 8× supersampling to reduce jagged edges on desktop icons;
‑ Automatically fill transparent black corners around icons using neighboring peripheral colors to avoid dark vignetting after scaling;
‑ Write 7 pieces of 32‑bit PNG layers: 16, 24, 32, 48, 64, 128, 256;
‑ Automatically read EXIF orientation information commonly seen in mobile‑phone photos.

## Simplest Usage
Drag image files onto `ConvertPNG‑JPG‑to‑ICO.cmd`. Generated `.ico` files will be placed in:
`C:\Users\Administrator\Desktop\ChatGPT\ConvertICO and Icon Rounding\Modified Icon Output`

You can also double‑click the `.cmd` file, then select one or more images in the pop‑up window.

> **Only drag files onto `ConvertPNG‑JPG‑to‑ICO.cmd`.**
> Do not drag onto the `.ps1` inside `_engine`: Windows will not treat `.ps1` as an executable program. Dragging files there will only trigger an error ("not a valid Win32 application") and no conversion will happen.

## Directory Description
| File | Purpose |
| --- | --- |
| `ConvertPNG‑JPG‑to‑ICO.cmd` | The only file you need to operate; supports drag‑and‑drop and double‑click |
| `_engine\png‑jpg‑to‑ico.ps1` | The actual working script stored in subfolder; do not modify it |
| `_engine\last‑run.log` | Records generated after each run, see next section |
| `Modified Icon Output` | Output directory, all generated `.ico` files are stored here |

## What to check if window flashes and closes instantly
The `.cmd` file is designed to **always pause at the end** with prompt "Press any key to continue", so normally error messages will not disappear.

If the window still closes immediately, the `.cmd` has not been executed at all (e.g. dragged onto other files). Check `_engine\last‑run.log`:
‑ Contains `launcher started` → `.cmd` has launched, the problem lies within the script itself;
‑ File does not exist, or timestamp does not match this run → `.cmd` was not executed.

## Command‑Line
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_engine\png-jpg-to-ico.ps1 .\logo.png