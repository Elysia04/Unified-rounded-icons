using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    /// <summary>白色圆角卡片容器。</summary>
    internal class CardPanel : Panel
    {
        private bool highlight;

        public CardPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Background;
            Padding = new Padding(14, 10, 14, 12);
        }

        public bool Highlight
        {
            get { return highlight; }
            set { if (highlight != value) { highlight = value; Invalidate(); } }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Theme.RoundRect(r, 10))
            {
                using (SolidBrush back = new SolidBrush(Theme.Card))
                {
                    g.FillPath(back, path);
                }
                using (Pen pen = new Pen(highlight ? Theme.Accent : Theme.CardBorder, highlight ? 1.6f : 1f))
                {
                    pen.Alignment = PenAlignment.Inset;
                    g.DrawPath(pen, path);
                }
            }
        }
    }

    /// <summary>扁平风格按钮：主按钮为实心主题色，次按钮为白底描边。</summary>
    internal class FlatButton : Button
    {
        private bool primary;
        private bool hovered;
        private bool pressed;

        public FlatButton()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            BackColor = Theme.Card;
            ForeColor = Theme.Text;
            Font = Theme.Body;
            Cursor = Cursors.Hand;
            Size = new Size(104, 34);
            UseVisualStyleBackColor = false;
        }

        public bool Primary
        {
            get { return primary; }
            set { primary = value; Invalidate(); }
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(Parent == null ? Theme.Card : Parent.BackColor);
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hovered = false;
            pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                pressed = true;
                Invalidate();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            pressed = false;
            Invalidate();
            base.OnMouseUp(e);
        }

        protected override void OnEnabledChanged(EventArgs e)
        {
            Invalidate();
            base.OnEnabledChanged(e);
        }

        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            Color back;
            Color edge;
            Color fore;

            if (primary)
            {
                back = !Enabled
                    ? Color.FromArgb(0xC4, 0xD7, 0xF7)
                    : (pressed ? Theme.AccentDown : (hovered ? Theme.AccentHover : Theme.Accent));
                edge = back;
                fore = Color.White;
            }
            else
            {
                back = !Enabled
                    ? Color.FromArgb(0xF7, 0xF8, 0xFA)
                    : (pressed ? Theme.ButtonDown : (hovered ? Theme.ButtonHover : Theme.Card));
                edge = Enabled ? (Focused ? Theme.Accent : Theme.ButtonBorder) : Color.FromArgb(0xE8, 0xEB, 0xF0);
                fore = Enabled ? Theme.Text : Theme.Disabled;
            }

            using (GraphicsPath path = Theme.RoundRect(r, 6))
            {
                using (SolidBrush brush = new SolidBrush(back))
                {
                    g.FillPath(brush, path);
                }
                using (Pen pen = new Pen(edge))
                {
                    pen.Alignment = PenAlignment.Inset;
                    g.DrawPath(pen, path);
                }
            }

            TextRenderer.DrawText(
                g,
                Text,
                Font,
                r,
                fore,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
                    | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
        }
    }

    /// <summary>数字输入框（- 数值 +），四个角都是圆角，高度固定 34 像素。</summary>
    internal class NumberStepper : Panel
    {
        private readonly TextBox edit = new TextBox();
        private readonly int minimum;
        private readonly int maximum;
        private int value;
        private int hotZone;
        private bool updating;

        public event EventHandler ValueChanged;

        public NumberStepper(int minimumValue, int maximumValue, int initialValue)
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            minimum = minimumValue;
            maximum = maximumValue;
            BackColor = Color.White;
            Size = new Size(100, 34);

            edit.BorderStyle = BorderStyle.None;
            edit.BackColor = Color.White;
            edit.ForeColor = Theme.Text;
            edit.Font = Theme.Stepper;
            edit.TextAlign = HorizontalAlignment.Center;
            edit.Multiline = true;
            edit.WordWrap = false;
            edit.ScrollBars = ScrollBars.None;
            edit.ShortcutsEnabled = true;
            Controls.Add(edit);
            edit.KeyPress += OnEditKeyPress;
            edit.KeyDown += OnEditKeyDown;
            edit.LostFocus += OnEditLeave;
            edit.MouseWheel += OnWheel;
            MouseWheel += OnWheel;
            edit.GotFocus += OnChildFocusChanged;
            edit.LostFocus += OnChildFocusChanged;

            Value = initialValue;
        }

        public int Value
        {
            get { return value; }
            set
            {
                int clamped = value;
                if (clamped < minimum) { clamped = minimum; }
                if (clamped > maximum) { clamped = maximum; }
                if (this.value == clamped)
                {
                    if (!updating && edit.Text != clamped.ToString())
                    {
                        SyncText(clamped);
                    }
                    return;
                }
                this.value = clamped;
                SyncText(clamped);
                Invalidate();
                if (ValueChanged != null)
                {
                    ValueChanged(this, EventArgs.Empty);
                }
            }
        }

        private void SyncText(int number)
        {
            updating = true;
            edit.Text = number.ToString();
            edit.SelectionStart = edit.TextLength;
            updating = false;
        }

        protected override void OnFontChanged(EventArgs e)
        {
            base.OnFontChanged(e);
            LayoutChildren();
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            LayoutChildren();
        }

        // 自动缩放（AutoScale）有可能把子控件的边框缩放两次，
        // 让文本框悄悄盖住右边的加号。布局结束后重新摆一次就稳了。
        protected override void OnLayout(LayoutEventArgs levent)
        {
            base.OnLayout(levent);
            LayoutChildren();
        }

        private void LayoutChildren()
        {
            int side = 26;
            int height = edit.PreferredHeight;
            if (height > Height - 8) { height = Height - 8; }
            edit.SetBounds(side, (Height - height) / 2, Math.Max(20, Width - 2 * side), height);
        }

        private void OnChildFocusChanged(object sender, EventArgs e)
        {
            Invalidate();
        }

        private void OnEditKeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar))
            {
                e.Handled = true;
            }
        }

        private void OnEditKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Up)
            {
                Value = value + 1;
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Down)
            {
                Value = value - 1;
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Enter)
            {
                CommitEdit();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        private void OnEditLeave(object sender, EventArgs e)
        {
            CommitEdit();
        }

        private void CommitEdit()
        {
            int parsed;
            if (int.TryParse(edit.Text.Trim(), out parsed))
            {
                Value = parsed;
            }
            else
            {
                edit.Text = value.ToString();
            }
        }

        private void OnWheel(object sender, MouseEventArgs e)
        {
            Value = value + (e.Delta > 0 ? 1 : -1);
            ((HandledMouseEventArgs)e).Handled = true;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int zone = ZoneAt(e.X);
            if (zone != hotZone)
            {
                hotZone = zone;
                Cursor = zone == 0 ? Cursors.Default : Cursors.Hand;
                Invalidate();
            }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (hotZone != 0)
            {
                hotZone = 0;
                Cursor = Cursors.Default;
                Invalidate();
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            int zone = ZoneAt(e.X);
            if (zone == 1)
            {
                Value = value - 1;
                edit.Focus();
            }
            else if (zone == 2)
            {
                Value = value + 1;
                edit.Focus();
            }
        }

        private int ZoneAt(int x)
        {
            if (x < 24) { return 1; }
            if (x > Width - 25) { return 2; }
            return 0;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);

            using (GraphicsPath path = Theme.RoundRect(r, 6))
            {
                using (Pen pen = new Pen(edit.Focused || Focused ? Theme.Accent : Theme.ButtonBorder))
                {
                    pen.Alignment = PenAlignment.Inset;
                    g.DrawPath(pen, path);
                }
            }

            // 用真正的减号字符（U+2212），ASCII 连字符在雅黑里太短太淡。
            DrawZone(g, 1, 4, 20, ((char)0x2212).ToString(), hotZone == 1);
            DrawZone(g, Width - 24, 4, 20, "+", hotZone == 2);
        }

        private void DrawZone(Graphics g, int x, int y, int width, string glyph, bool hot)
        {
            Rectangle r = new Rectangle(x, y, width, Height - 2 * y);
            if (hot)
            {
                using (GraphicsPath path = Theme.RoundRect(r, 4))
                {
                    using (SolidBrush brush = new SolidBrush(Theme.ButtonHover))
                    {
                        g.FillPath(brush, path);
                    }
                }
            }
            TextRenderer.DrawText(
                g, glyph, Theme.StepperGlyph, r, hot ? Theme.Accent : Theme.StepperGlyphColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
                    | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
        }
    }

    /// <summary>带圆角边框的输入框，高度固定 34 像素。</summary>
    internal class TextField : Panel
    {
        private readonly TextBox box = new TextBox();
        private string placeholder = string.Empty;

        public TextField()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Color.White;
            Size = new Size(200, 34);

            box.BorderStyle = BorderStyle.None;
            box.BackColor = Color.White;
            box.ForeColor = Theme.Text;
            box.Font = Theme.Body;
            box.Multiline = true;
            box.WordWrap = false;
            box.ScrollBars = ScrollBars.None;
            box.ShortcutsEnabled = true;
            Controls.Add(box);
            box.TextChanged += OnBoxTextChanged;
            box.GotFocus += OnBoxFocus;
            box.LostFocus += OnBoxFocus;
            box.KeyDown += OnBoxKeyDown;
        }

        public TextBox Inner { get { return box; } }

        public string Placeholder
        {
            get { return placeholder; }
            set { placeholder = value ?? string.Empty; Invalidate(); }
        }

        public override string Text
        {
            get { return box.Text; }
            set { box.Text = value ?? string.Empty; }
        }

        private void OnBoxTextChanged(object sender, EventArgs e)
        {
            Invalidate();
        }

        private void OnBoxFocus(object sender, EventArgs e)
        {
            Invalidate();
        }

        private void OnBoxKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            LayoutChildren();
        }

        protected override void OnLayout(LayoutEventArgs levent)
        {
            base.OnLayout(levent);
            LayoutChildren();
        }

        private void LayoutChildren()
        {
            int height = box.PreferredHeight;
            if (height > Height - 10) { height = Height - 10; }
            box.SetBounds(11, (Height - height) / 2, Math.Max(20, Width - 22), height);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            bool hot = box.Focused;
            using (GraphicsPath path = Theme.RoundRect(r, 6))
            {
                using (Pen pen = new Pen(hot ? Theme.Accent : Theme.ButtonBorder))
                {
                    pen.Alignment = PenAlignment.Inset;
                    g.DrawPath(pen, path);
                }
            }
            if (box.TextLength == 0 && !hot && placeholder.Length > 0)
            {
                Rectangle text = new Rectangle(12, 0, Width - 24, Height);
                TextRenderer.DrawText(
                    g, placeholder, Theme.Body, text, Theme.Faint,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                        | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }

    /// <summary>文件列表：自绘条目（文件名 + 灰色目录），空列表时显示提示文字。</summary>
    internal class FilesListBox : ListBox
    {
        private string emptyText = string.Empty;
        private int hotIndex = -1;

        public FilesListBox()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
            DrawMode = DrawMode.OwnerDrawFixed;
            ItemHeight = 26;
            BorderStyle = BorderStyle.None;
            BackColor = Color.White;
            ForeColor = Theme.Text;
            Font = Theme.Body;
            IntegralHeight = false;
            SelectionMode = SelectionMode.MultiExtended;
            HorizontalScrollbar = false;
        }

        public string EmptyText
        {
            get { return emptyText; }
            set { emptyText = value ?? string.Empty; Invalidate(); }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int index = IndexFromPoint(e.Location);
            if (index != hotIndex)
            {
                hotIndex = index;
                Invalidate();
            }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            hotIndex = -1;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Items.Count == 0 && emptyText.Length > 0)
            {
                Rectangle r = new Rectangle(20, 0, Math.Max(40, ClientSize.Width - 40), ClientSize.Height);
                TextRenderer.DrawText(
                    e.Graphics, emptyText, Theme.Body, r, Theme.Faint,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
                        | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            }
        }

        protected override void OnDrawItem(DrawItemEventArgs e)
        {
            if (e.Index < 0 || e.Index >= Items.Count)
            {
                return;
            }

            Graphics g = e.Graphics;
            Rectangle row = new Rectangle(0, e.Bounds.Y, ClientSize.Width, e.Bounds.Height);
            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;

            using (SolidBrush back = new SolidBrush(selected ? Theme.Selection : Color.White))
            {
                g.FillRectangle(back, row);
            }

            string path = Convert.ToString(Items[e.Index]);
            string name = Path.GetFileName(path);
            string folder = Path.GetDirectoryName(path);
            if (name.Length == 0) { name = path; }

            int left = row.X + 10;
            Size nameSize = TextRenderer.MeasureText(
                g, name, Theme.Body, new Size(int.MaxValue, row.Height), TextFormatFlags.NoPadding);
            int nameWidth = Math.Min(nameSize.Width + 2, Math.Max(20, row.Width - left - 16));

            Rectangle nameRect = new Rectangle(left, row.Y, nameWidth, row.Height);
            TextRenderer.DrawText(
                g, name, Theme.Body, nameRect,
                selected ? Theme.AccentDown : Theme.Text,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                    | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);

            if (folder != null && folder.Length > 0 && left + nameWidth + 12 < row.Right - 12)
            {
                Rectangle folderRect = new Rectangle(
                    left + nameWidth + 10, row.Y, row.Right - (left + nameWidth + 10) - 12, row.Height);
                TextRenderer.DrawText(
                    g, folder, Theme.Small, folderRect, Theme.Faint,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter
                        | TextFormatFlags.SingleLine | TextFormatFlags.PathEllipsis | TextFormatFlags.NoPadding);
            }
        }
    }

    /// <summary>窗口标题旁边的小图标。</summary>
    internal class IconTile : Control
    {
        private Image picture;

        public IconTile()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Background;
            Size = new Size(40, 40);
        }

        public Image Picture
        {
            get { return picture; }
            set { picture = value; Invalidate(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            if (picture != null)
            {
                g.DrawImage(picture, r);
            }
            else
            {
                using (GraphicsPath path = Theme.RoundRect(r, 9))
                {
                    using (LinearGradientBrush brush = new LinearGradientBrush(
                        r, Theme.Accent, Theme.AccentDown, 90f))
                    {
                        g.FillPath(brush, path);
                    }
                }
            }
        }
    }
}