using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    /// <summary>配色、字体和绘制小工具，界面里所有控件共用。</summary>
    internal static class Theme
    {
        public static readonly Color Background    = Color.FromArgb(0xF1, 0xF3, 0xF7);
        public static readonly Color Card          = Color.White;
        public static readonly Color CardBorder    = Color.FromArgb(0xE1, 0xE5, 0xEB);
        public static readonly Color Text          = Color.FromArgb(0x1E, 0x24, 0x2F);
        public static readonly Color Muted         = Color.FromArgb(0x76, 0x7E, 0x8B);
        public static readonly Color Faint         = Color.FromArgb(0x9E, 0xA6, 0xB3);
        public static readonly Color Accent        = Color.FromArgb(0x2E, 0x7C, 0xF6);
        public static readonly Color AccentHover   = Color.FromArgb(0x1F, 0x6B, 0xE0);
        public static readonly Color AccentDown    = Color.FromArgb(0x17, 0x57, 0xBE);
        public static readonly Color AccentSoft    = Color.FromArgb(0xD6, 0xE4, 0xFD);
        public static readonly Color ButtonHover   = Color.FromArgb(0xF3, 0xF6, 0xFC);
        public static readonly Color ButtonDown    = Color.FromArgb(0xE5, 0xEC, 0xF8);
        public static readonly Color ButtonBorder  = Color.FromArgb(0xD3, 0xDA, 0xE4);
        public static readonly Color LogBackground = Color.FromArgb(0xFA, 0xFB, 0xFD);
        public static readonly Color Selection     = Color.FromArgb(0xE7, 0xF0, 0xFE);
        public static readonly Color SelectionEdge = Color.FromArgb(0xC9, 0xDE, 0xFC);
        public static readonly Color Disabled      = Color.FromArgb(0xB8, 0xBF, 0xCA);

        public const string Family = "Microsoft YaHei UI";

        public static readonly Font Body     = new Font(Family, 9F);
        public static readonly Font BodyBold = new Font(Family, 9F, FontStyle.Bold);
        public static readonly Font Title    = new Font(Family, 14F, FontStyle.Bold);
        public static readonly Font Small    = new Font(Family, 8.25F);
        public static readonly Font Section  = new Font(Family, 9F, FontStyle.Bold);
        public static readonly Font Stepper  = new Font(Family, 9.75F);
        public static readonly Font StepperGlyph = new Font(Family, 11F);
        public static readonly Color StepperGlyphColor = Color.FromArgb(0x46, 0x51, 0x62);

        public static GraphicsPath RoundRect(Rectangle bounds, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            if (radius <= 0 || bounds.Width <= 1 || bounds.Height <= 1)
            {
                path.AddRectangle(bounds);
                return path;
            }

            int d = radius * 2;
            if (d > bounds.Width) { d = bounds.Width; }
            if (d > bounds.Height) { d = bounds.Height; }
            path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}