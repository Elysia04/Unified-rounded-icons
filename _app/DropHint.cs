using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    /// <summary>
    /// 列表为空时盖在列表上面的拖放提示：一圈虚线 + 两行说明。
    /// 之前把提示画在 ListBox 自己的 Paint 里，原生 ListBox 不触发那个事件，
    /// 结果空列表就是一片白，看着像坏了，所以改成单独一层控件。
    /// </summary>
    internal class DropHint : Control
    {
        private bool hot;

        public DropHint()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            SetStyle(ControlStyles.Selectable, false);
            BackColor = Theme.Card;
            Cursor = Cursors.Hand;
        }

        /// <summary>拖动经过时高亮虚线框。</summary>
        public bool Hot
        {
            get { return hot; }
            set
            {
                if (hot != value)
                {
                    hot = value;
                    Invalidate();
                }
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Theme.Card);
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle frame = new Rectangle(4, 4, Width - 9, Height - 9);
            if (frame.Width > 20 && frame.Height > 20)
            {
                using (GraphicsPath path = Theme.RoundRect(frame, 8))
                {
                    using (Pen pen = new Pen(hot ? Theme.Accent : Color.FromArgb(0xC6, 0xD4, 0xEA), hot ? 2F : 1.4F))
                    {
                        pen.DashStyle = DashStyle.Custom;
                        pen.DashPattern = new float[] { 5F, 4F };
                        pen.Alignment = PenAlignment.Inset;
                        g.DrawPath(pen, path);
                    }
                }
            }

            const string Title = "把 PNG / JPG / JPEG 图片拖到这里";
            const string Subtitle = "也可以点这里选择图片，支持多选";

            Size titleSize = TextRenderer.MeasureText(
                Title, Theme.Body, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
            Size subtitleSize = TextRenderer.MeasureText(
                Subtitle, Theme.Small, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
            int blockHeight = titleSize.Height + 8 + subtitleSize.Height;
            int top = (Height - blockHeight) / 2;
            if (top < 6)
            {
                top = 6;
            }

            TextRenderer.DrawText(
                g, Title, Theme.Body, new Rectangle(10, top, Width - 20, titleSize.Height),
                hot ? Theme.Accent : Theme.Muted,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.Top
                    | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);

            TextRenderer.DrawText(
                g, Subtitle, Theme.Small,
                new Rectangle(10, top + titleSize.Height + 8, Width - 20, subtitleSize.Height),
                Theme.Faint,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.Top
                    | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
        }
    }
}