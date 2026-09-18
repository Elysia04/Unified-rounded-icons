using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    /// <summary>细进度条，配色跟着主题走。</summary>
    internal class ThinProgressBar : Control
    {
        private int maximum = 1;
        private int current;

        public ThinProgressBar()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Background;
            Height = 8;
        }

        public int Maximum
        {
            get { return maximum; }
            set
            {
                maximum = value < 1 ? 1 : value;
                if (current > maximum) { current = maximum; }
                Invalidate();
            }
        }

        public int Value
        {
            get { return current; }
            set
            {
                int clamped = value;
                if (clamped < 0) { clamped = 0; }
                if (clamped > maximum) { clamped = maximum; }
                current = clamped;
                Invalidate();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent == null ? Theme.Background : Parent.BackColor);

            Rectangle track = new Rectangle(0, 0, Width, Height);
            int radius = Math.Max(1, Height / 2);
            using (GraphicsPath path = Theme.RoundRect(track, radius))
            {
                using (SolidBrush brush = new SolidBrush(Color.FromArgb(0xE2, 0xE7, 0xEF)))
                {
                    g.FillPath(brush, path);
                }
            }

            if (current > 0)
            {
                int width = (int)Math.Round((double)Width * current / maximum);
                if (width < Height) { width = Math.Min(Width, Height); }
                Rectangle fill = new Rectangle(0, 0, width, Height);
                using (GraphicsPath path = Theme.RoundRect(fill, radius))
                {
                    using (SolidBrush brush = new SolidBrush(Theme.Accent))
                    {
                        g.FillPath(brush, path);
                    }
                }
            }
        }
    }
}