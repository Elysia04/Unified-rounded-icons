using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    internal sealed class MainForm : Form
    {
        private const string ScriptResourceName = "RoundedIcoApp.Converter.ps1";
        private const int RowHeight = 34;

        private readonly Settings settings = new Settings();

        private readonly CardPanel filesCard = new CardPanel();
        private readonly CardPanel optionsCard = new CardPanel();
        private readonly CardPanel outputCard = new CardPanel();
        private readonly CardPanel logCard = new CardPanel();

        private readonly FilesListBox fileList = new FilesListBox();
        private readonly Panel listHost = new Panel();
        private readonly DropHint emptyHint = new DropHint();
        private readonly IconTile iconTile = new IconTile();
        private readonly Label countLabel = new Label();
        private readonly Label statusLabel = new Label();
        private readonly NumberStepper radiusBox = new NumberStepper(0, 50, 28);
        private readonly NumberStepper paddingBox = new NumberStepper(0, 20, 0);
        private readonly CheckBox trimCheck = new CheckBox();
        private readonly FlatButton chooseButton = new FlatButton();
        private readonly FlatButton clearButton = new FlatButton();
        private readonly FlatButton browseButton = new FlatButton();
        private readonly FlatButton resetOutputButton = new FlatButton();
        private readonly FlatButton openOutputButton = new FlatButton();
        private readonly FlatButton convertButton = new FlatButton();
        private readonly FlatButton clearLogButton = new FlatButton();
        private readonly TextField outputField = new TextField();
        private readonly Label outputHintLabel = new Label();
        private readonly TextBox logBox = new TextBox();
        private readonly ThinProgressBar progressBar = new ThinProgressBar();
        private readonly BackgroundWorker worker = new BackgroundWorker();
        private readonly ToolTip tips = new ToolTip();
        private readonly HashSet<string> knownFiles =
            new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        private bool isBusy;
        private int doneCount;
        private int totalCount;

        public MainForm(string[] initialFiles)
        {
            settings.Load();
            BuildInterface();
            ApplySettings();
            WireEvents();
            UpdateCountLabel();

            AddFiles(initialFiles);
        }

        private string EffectiveOutputDirectory
        {
            get
            {
                string typed = outputField.Text.Trim();
                if (typed.Length == 0)
                {
                    return Settings.DefaultOutputDirectory;
                }
                try
                {
                    return Path.GetFullPath(typed);
                }
                catch (Exception)
                {
                    return typed;
                }
            }
        }

        private static Label MakeLabel(string text, Font font, Color color, Color back)
        {
            Label label = new Label();
            label.AutoSize = true;
            label.Text = text;
            label.Font = font;
            label.ForeColor = color;
            label.BackColor = back;
            label.Margin = new Padding(0);
            return label;
        }

        private void BuildInterface()
        {
            SuspendLayout();

            Text = "图片转圆角 ICO";
            BackColor = Theme.Background;
            Font = Theme.Body;
            ForeColor = Theme.Text;
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96F, 96F);
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(800, 700);
            MinimumSize = new Size(736, 620);
            DoubleBuffered = true;
            AllowDrop = true;

            try
            {
                Icon appIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (appIcon != null)
                {
                    Icon = appIcon;
                    iconTile.Picture = appIcon.ToBitmap();
                }
            }
            catch (Exception)
            {
            }

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.BackColor = Theme.Background;
            root.Padding = new Padding(16, 14, 16, 14);
            root.ColumnCount = 1;
            root.RowCount = 6;
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 46F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 54F));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(root);

            root.Controls.Add(BuildHeader(), 0, 0);
            root.Controls.Add(BuildFilesCard(), 0, 1);
            root.Controls.Add(BuildOptionsCard(), 0, 2);
            root.Controls.Add(BuildOutputCard(), 0, 3);
            root.Controls.Add(BuildLogCard(), 0, 4);
            root.Controls.Add(BuildFooter(), 0, 5);

            ResumeLayout(true);
        }
        private Control BuildHeader()
        {
            TableLayoutPanel header = new TableLayoutPanel();
            header.AutoSize = true;
            header.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            header.Dock = DockStyle.Fill;
            header.ColumnCount = 2;
            header.RowCount = 1;
            header.BackColor = Theme.Background;
            header.Margin = new Padding(2, 0, 2, 12);
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 50F));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            iconTile.Margin = new Padding(0, 2, 10, 0);

            TableLayoutPanel titles = new TableLayoutPanel();
            titles.AutoSize = true;
            titles.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            titles.ColumnCount = 1;
            titles.RowCount = 2;
            titles.BackColor = Theme.Background;
            titles.Margin = new Padding(0);
            titles.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            titles.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            Label title = MakeLabel("图片转圆角 ICO", Theme.Title, Theme.Text, Theme.Background);
            Label subtitle = MakeLabel(
                "把 PNG / JPG / JPEG 转成 16 - 256 共 7 种尺寸的圆角图标，支持拖放和批量转换",
                Theme.Small, Theme.Muted, Theme.Background);
            subtitle.Margin = new Padding(1, 6, 0, 0);

            titles.Controls.Add(title, 0, 0);
            titles.Controls.Add(subtitle, 0, 1);

            header.Controls.Add(iconTile, 0, 0);
            header.Controls.Add(titles, 1, 0);
            return header;
        }

        private Control BuildFilesCard()
        {
            filesCard.Dock = DockStyle.Fill;
            filesCard.Margin = new Padding(0, 0, 0, 10);
            filesCard.Padding = new Padding(14, 10, 14, 12);

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.BackColor = Theme.Card;
            layout.ColumnCount = 1;
            layout.RowCount = 3;
            layout.Margin = new Padding(0);
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            TableLayoutPanel head = new TableLayoutPanel();
            head.AutoSize = true;
            head.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            head.Dock = DockStyle.Fill;
            head.BackColor = Theme.Card;
            head.ColumnCount = 2;
            head.RowCount = 1;
            head.Margin = new Padding(0, 0, 0, 8);
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            Label caption = MakeLabel("待转换图片", Theme.Section, Theme.Text, Theme.Card);
            caption.Anchor = AnchorStyles.Left;

            countLabel.AutoSize = true;
            countLabel.Font = Theme.Small;
            countLabel.ForeColor = Theme.Muted;
            countLabel.BackColor = Theme.Card;
            countLabel.Margin = new Padding(0);
            countLabel.Anchor = AnchorStyles.Right;

            head.Controls.Add(caption, 0, 0);
            head.Controls.Add(countLabel, 1, 0);

            fileList.Dock = DockStyle.Fill;
            fileList.Margin = new Padding(0);
            fileList.AllowDrop = true;

            emptyHint.Dock = DockStyle.Fill;
            emptyHint.Margin = new Padding(0);
            emptyHint.AllowDrop = true;

            listHost.Dock = DockStyle.Fill;
            listHost.Margin = new Padding(0);
            listHost.BackColor = Theme.Card;
            listHost.AllowDrop = true;
            listHost.Controls.Add(fileList);
            listHost.Controls.Add(emptyHint);
            emptyHint.BringToFront();

            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.AutoSize = true;
            buttons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            buttons.WrapContents = false;
            buttons.FlowDirection = FlowDirection.LeftToRight;
            buttons.BackColor = Theme.Card;
            buttons.Margin = new Padding(0, 12, 0, 0);

            chooseButton.Text = "选择图片\u2026";
            chooseButton.Primary = true;
            chooseButton.Size = new Size(116, RowHeight);
            chooseButton.Margin = new Padding(0, 0, 8, 0);

            clearButton.Text = "清空列表";
            clearButton.Size = new Size(100, RowHeight);
            clearButton.Margin = new Padding(0);

            buttons.Controls.Add(chooseButton);
            buttons.Controls.Add(clearButton);

            layout.Controls.Add(head, 0, 0);
            layout.Controls.Add(listHost, 0, 1);
            layout.Controls.Add(buttons, 0, 2);

            filesCard.Controls.Add(layout);
            return filesCard;
        }
        private Control BuildOptionsCard()
        {
            optionsCard.Dock = DockStyle.Fill;
            optionsCard.Margin = new Padding(0, 0, 0, 10);
            optionsCard.Padding = new Padding(14, 10, 14, 10);
            optionsCard.AutoSize = true;
            optionsCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.AutoSize = true;
            layout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            layout.BackColor = Theme.Card;
            layout.ColumnCount = 8;
            layout.RowCount = 1;
            layout.Margin = new Padding(0);
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, RowHeight));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104F));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 26F));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104F));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));

            Label radiusLabel = MakeLabel("圆角", Theme.Body, Theme.Text, Theme.Card);
            radiusLabel.Anchor = AnchorStyles.Left;
            radiusLabel.Margin = new Padding(0, 0, 10, 0);

            radiusBox.Anchor = AnchorStyles.Left;
            radiusBox.Margin = new Padding(0);

            Label radiusSuffix = MakeLabel("%", Theme.Body, Theme.Muted, Theme.Card);
            radiusSuffix.Anchor = AnchorStyles.Left;
            radiusSuffix.Margin = new Padding(8, 0, 0, 0);

            Label paddingLabel = MakeLabel("透明边距", Theme.Body, Theme.Text, Theme.Card);
            paddingLabel.Anchor = AnchorStyles.Left;
            paddingLabel.Margin = new Padding(0, 0, 10, 0);

            paddingBox.Anchor = AnchorStyles.Left;
            paddingBox.Margin = new Padding(0);

            Label paddingSuffix = MakeLabel("%", Theme.Body, Theme.Muted, Theme.Card);
            paddingSuffix.Anchor = AnchorStyles.Left;
            paddingSuffix.Margin = new Padding(8, 0, 0, 0);

            trimCheck.Text = "自动裁掉四周空白边，让每个图标的图案大小一致";
            trimCheck.Font = Theme.Body;
            trimCheck.ForeColor = Theme.Text;
            trimCheck.BackColor = Theme.Card;
            trimCheck.AutoSize = false;
            trimCheck.Dock = DockStyle.Fill;
            trimCheck.Margin = new Padding(0);
            trimCheck.TextAlign = ContentAlignment.MiddleLeft;
            trimCheck.FlatStyle = FlatStyle.System;
            tips.SetToolTip(trimCheck,
                "打开后会先去掉图片四周多余的透明或纯色边，再按图案内容居中切正方形。\n"
                + "同一批图标放在一起时，图案大小看起来就一致了；纯色照片不受影响。");

            layout.Controls.Add(radiusLabel, 0, 0);
            layout.Controls.Add(radiusBox, 1, 0);
            layout.Controls.Add(radiusSuffix, 2, 0);
            layout.Controls.Add(paddingLabel, 4, 0);
            layout.Controls.Add(paddingBox, 5, 0);
            layout.Controls.Add(paddingSuffix, 6, 0);
            layout.Controls.Add(trimCheck, 7, 0);

            optionsCard.Controls.Add(layout);
            return optionsCard;
        }

        private Control BuildOutputCard()
        {
            outputCard.Dock = DockStyle.Fill;
            outputCard.Margin = new Padding(0, 0, 0, 10);
            outputCard.Padding = new Padding(14, 10, 14, 12);
            outputCard.AutoSize = true;
            outputCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.AutoSize = true;
            layout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            layout.BackColor = Theme.Card;
            layout.ColumnCount = 1;
            layout.RowCount = 2;
            layout.Margin = new Padding(0);
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, RowHeight));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            TableLayoutPanel row = new TableLayoutPanel();
            row.Dock = DockStyle.Fill;
            row.BackColor = Theme.Card;
            row.ColumnCount = 5;
            row.RowCount = 1;
            row.Margin = new Padding(0);
            row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96F));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112F));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104F));
            row.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            Label caption = MakeLabel("输出位置", Theme.Body, Theme.Text, Theme.Card);
            caption.Anchor = AnchorStyles.Left;
            caption.Margin = new Padding(0, 0, 10, 0);

            outputField.Dock = DockStyle.Fill;
            outputField.Margin = new Padding(0, 0, 10, 0);
            outputField.Placeholder = "留空则用默认位置：" + Settings.DefaultOutputDirectory;
            tips.SetToolTip(outputField, "生成的 .ico 会保存到这个文件夹，可以直接输入，也可以点浏览按钮选择。");
            outputField.Inner.TextChanged += delegate { UpdateOutputTooltip(); };

            browseButton.Text = "浏览\u2026";
            browseButton.Dock = DockStyle.Fill;
            browseButton.Margin = new Padding(0, 0, 8, 0);

            resetOutputButton.Text = "恢复默认";
            resetOutputButton.Dock = DockStyle.Fill;
            resetOutputButton.Margin = new Padding(0, 0, 8, 0);
            tips.SetToolTip(resetOutputButton, "改回默认输出目录：" + Settings.DefaultOutputDirectory);

            openOutputButton.Text = "打开文件夹";
            openOutputButton.Dock = DockStyle.Fill;
            openOutputButton.Margin = new Padding(0);

            row.Controls.Add(caption, 0, 0);
            row.Controls.Add(outputField, 1, 0);
            row.Controls.Add(browseButton, 2, 0);
            row.Controls.Add(resetOutputButton, 3, 0);
            row.Controls.Add(openOutputButton, 4, 0);

            outputHintLabel.AutoSize = true;
            outputHintLabel.Font = Theme.Small;
            outputHintLabel.ForeColor = Theme.Muted;
            outputHintLabel.BackColor = Theme.Card;
            outputHintLabel.Margin = new Padding(0, 8, 0, 0);
            outputHintLabel.Text = "输出位置会自动记住，下次打开还在原处。";

            layout.Controls.Add(row, 0, 0);
            layout.Controls.Add(outputHintLabel, 0, 1);

            outputCard.Controls.Add(layout);
            return outputCard;
        }
        private Control BuildLogCard()
        {
            logCard.Dock = DockStyle.Fill;
            logCard.Margin = new Padding(0, 0, 0, 10);
            logCard.Padding = new Padding(14, 10, 14, 12);

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.BackColor = Theme.Card;
            layout.ColumnCount = 1;
            layout.RowCount = 2;
            layout.Margin = new Padding(0);
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

            TableLayoutPanel head = new TableLayoutPanel();
            head.AutoSize = true;
            head.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            head.Dock = DockStyle.Fill;
            head.BackColor = Theme.Card;
            head.ColumnCount = 2;
            head.RowCount = 1;
            head.Margin = new Padding(0, 0, 0, 8);
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            Label caption = MakeLabel("运行日志", Theme.Section, Theme.Text, Theme.Card);
            caption.Anchor = AnchorStyles.Left;

            clearLogButton.Text = "清空日志";
            clearLogButton.Size = new Size(96, RowHeight);
            clearLogButton.Margin = new Padding(0);
            clearLogButton.Anchor = AnchorStyles.Right;

            head.Controls.Add(caption, 0, 0);
            head.Controls.Add(clearLogButton, 1, 0);

            logBox.Dock = DockStyle.Fill;
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.Vertical;
            logBox.BorderStyle = BorderStyle.None;
            logBox.BackColor = Theme.LogBackground;
            logBox.ForeColor = Theme.Text;
            logBox.Font = Theme.Body;
            logBox.WordWrap = true;

            logBox.Margin = new Padding(0);
            logBox.TabStop = false;

            layout.Controls.Add(head, 0, 0);
            layout.Controls.Add(logBox, 0, 1);

            logCard.Controls.Add(layout);
            return logCard;
        }

        private Control BuildFooter()
        {
            TableLayoutPanel footer = new TableLayoutPanel();
            footer.Dock = DockStyle.Fill;
            footer.AutoSize = true;
            footer.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            footer.BackColor = Theme.Background;
            footer.ColumnCount = 1;
            footer.RowCount = 2;
            footer.Margin = new Padding(0);
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            footer.RowStyles.Add(new RowStyle(SizeType.Absolute, 20F));
            footer.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            progressBar.Dock = DockStyle.Fill;
            progressBar.Margin = new Padding(0, 0, 0, 10);
            progressBar.Visible = false;

            TableLayoutPanel bar = new TableLayoutPanel();
            bar.Dock = DockStyle.Fill;
            bar.AutoSize = true;
            bar.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar.BackColor = Theme.Background;
            bar.ColumnCount = 2;
            bar.RowCount = 1;
            bar.Margin = new Padding(0);
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            bar.RowStyles.Add(new RowStyle(SizeType.Absolute, RowHeight));

            statusLabel.AutoSize = false;
            statusLabel.Dock = DockStyle.Fill;
            statusLabel.TextAlign = ContentAlignment.MiddleLeft;
            statusLabel.Font = Theme.Body;
            statusLabel.ForeColor = Theme.Muted;
            statusLabel.BackColor = Theme.Background;
            statusLabel.Margin = new Padding(2, 0, 12, 0);
            statusLabel.Text = "就绪";

            FlowLayoutPanel actions = new FlowLayoutPanel();
            actions.AutoSize = true;
            actions.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            actions.WrapContents = false;
            actions.BackColor = Theme.Background;
            actions.Margin = new Padding(0);
            actions.Anchor = AnchorStyles.Right;

            convertButton.Text = "开始转换";
            convertButton.Primary = true;
            convertButton.Size = new Size(124, RowHeight);
            convertButton.Margin = new Padding(0);

            actions.Controls.Add(convertButton);

            bar.Controls.Add(statusLabel, 0, 0);
            bar.Controls.Add(actions, 1, 0);

            footer.Controls.Add(progressBar, 0, 0);
            footer.Controls.Add(bar, 0, 1);
            return footer;
        }

        private void WireEvents()
        {
            DragEnter += OnDragEnter;
            DragDrop += OnDragDrop;
            DragLeave += OnDragLeave;
            fileList.DragEnter += OnDragEnter;
            fileList.DragDrop += OnDragDrop;
            filesCard.DragEnter += OnDragEnter;
            filesCard.DragDrop += OnDragDrop;
            filesCard.DragLeave += OnDragLeave;
            emptyHint.DragEnter += OnDragEnter;
            emptyHint.DragDrop += OnDragDrop;
            emptyHint.DragLeave += OnDragLeave;
            emptyHint.Click += ChooseFiles;

            chooseButton.Click += ChooseFiles;
            clearButton.Click += delegate { ClearFiles(); };
            clearLogButton.Click += delegate { logBox.Clear(); };
            browseButton.Click += BrowseOutputDirectory;
            resetOutputButton.Click += delegate { SetOutputDirectory(Settings.DefaultOutputDirectory); };
            openOutputButton.Click += delegate { OpenOutputDirectory(); };
            convertButton.Click += StartConversion;
            fileList.KeyDown += OnFileListKeyDown;
            FormClosing += OnFormClosing;

            worker.WorkerReportsProgress = true;
            worker.DoWork += ConvertFiles;
            worker.ProgressChanged += OnWorkerProgress;
            worker.RunWorkerCompleted += ConversionCompleted;
        }

        private void ApplySettings()
        {
            SetOutputDirectory(settings.OutputDirectory);
            radiusBox.Value = settings.RadiusPercent;
            paddingBox.Value = settings.PaddingPercent;
            trimCheck.Checked = settings.TrimBorder;
        }

        private void SetOutputDirectory(string directory)
        {
            if (String.IsNullOrEmpty(directory))
            {
                directory = Settings.DefaultOutputDirectory;
            }
            outputField.Text = directory;
            UpdateOutputTooltip();
        }

        private void UpdateOutputTooltip()
        {
            string text = outputField.Text.Trim();
            if (text.Length == 0)
            {
                text = "留空则保存到默认位置：" + Settings.DefaultOutputDirectory;
            }
            tips.SetToolTip(outputField, text);

            // 路径太长时输入框里只看得见开头，这里把文件夹名单独写一行，一眼能认出来。
            string folderName = Path.GetFileName(text.TrimEnd(Path.DirectorySeparatorChar));
            if (folderName.Length == 0)
            {
                folderName = text;
            }
            outputHintLabel.Text = "当前输出文件夹：" + folderName + "（位置会自动记住，下次打开还在原处）";
        }

        private void OnDragEnter(object sender, DragEventArgs e)
        {
            bool files = e.Data.GetDataPresent(DataFormats.FileDrop);
            e.Effect = files ? DragDropEffects.Copy : DragDropEffects.None;
            filesCard.Highlight = files;
            emptyHint.Hot = files;
        }

        private void OnDragLeave(object sender, EventArgs e)
        {
            filesCard.Highlight = false;
            emptyHint.Hot = false;
        }

        private void OnDragDrop(object sender, DragEventArgs e)
        {
            filesCard.Highlight = false;
            emptyHint.Hot = false;
            AddFiles(e.Data.GetData(DataFormats.FileDrop) as string[]);
        }

        private void ChooseFiles(object sender, EventArgs e)
        {
            using (OpenFileDialog dialog = new OpenFileDialog())
            {
                dialog.Title = "选择要转换的图片";
                dialog.Filter = "图片文件 (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg";
                dialog.Multiselect = true;
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    AddFiles(dialog.FileNames);
                }
            }
        }

        private void AddFiles(IEnumerable<string> paths)
        {
            if (paths == null)
            {
                return;
            }

            int added = 0;
            foreach (string path in paths)
            {
                if (String.IsNullOrWhiteSpace(path) || !IsImageFile(path))
                {
                    continue;
                }

                string fullPath = Path.GetFullPath(path);
                if (knownFiles.Add(fullPath))
                {
                    fileList.Items.Add(fullPath);
                    added++;
                }
            }

            if (added > 0)
            {
                statusLabel.Text = "已添加 " + added + " 张图片，可以开始转换了";
            }

            UpdateCountLabel();
        }

        private static bool IsSupported(string path)
        {
            string extension = Path.GetExtension(path);
            return extension.Equals(".png", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase)
                || extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsImageFile(string path)
        {
            try
            {
                return File.Exists(path) && IsSupported(path);
            }
            catch (Exception)
            {
                return false;
            }
        }

        private void UpdateCountLabel()
        {
            int count = fileList.Items.Count;
            countLabel.Text = count == 0 ? "尚未添加图片" : "共 " + count + " 张";
            emptyHint.Visible = count == 0;
        }

        private void OnFileListKeyDown(object sender, KeyEventArgs e)
        {
            if (isBusy || e.KeyCode != Keys.Delete)
            {
                return;
            }

            while (fileList.SelectedIndices.Count > 0)
            {
                int index = fileList.SelectedIndices[0];
                knownFiles.Remove(Convert.ToString(fileList.Items[index]));
                fileList.Items.RemoveAt(index);
            }
            UpdateCountLabel();
            e.Handled = true;
        }

        private void ClearFiles()
        {
            if (isBusy)
            {
                return;
            }

            knownFiles.Clear();
            fileList.Items.Clear();
            logBox.Clear();
            statusLabel.Text = "就绪";
            UpdateCountLabel();
        }
        private void BrowseOutputDirectory(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择 .ico 文件的保存位置";
                dialog.ShowNewFolderButton = true;
                string current = EffectiveOutputDirectory;
                if (Directory.Exists(current))
                {
                    dialog.SelectedPath = current;
                }
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    SetOutputDirectory(dialog.SelectedPath);
                    SaveSettings();
                }
            }
        }

        private void OpenOutputDirectory()
        {
            string directory = EffectiveOutputDirectory;
            try
            {
                Directory.CreateDirectory(directory);
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = "\"" + directory + "\"",
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, Text,
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void StartConversion(object sender, EventArgs e)
        {
            List<string> files = new List<string>();
            foreach (object item in fileList.Items)
            {
                string path = Convert.ToString(item);
                if (IsImageFile(path))
                {
                    files.Add(path);
                }
            }

            if (files.Count == 0)
            {
                MessageBox.Show(this, "请先拖入或选择至少一张 PNG / JPG / JPEG 图片。",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string directory = EffectiveOutputDirectory;
            try
            {
                Directory.CreateDirectory(directory);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this,
                    "无法创建输出文件夹：\r\n" + directory + "\r\n\r\n" + ex.Message
                    + "\r\n\r\n请换一个位置，或把程序放到有写入权限的文件夹后再运行。",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            ConversionRequest request = new ConversionRequest();
            request.Files = files;
            request.OutputDirectory = directory;
            request.RadiusPercent = radiusBox.Value;
            request.PaddingPercent = paddingBox.Value;
            request.TrimBorder = trimCheck.Checked;

            SaveSettings();

            doneCount = 0;
            totalCount = files.Count;
            progressBar.Maximum = totalCount;
            progressBar.Value = 0;

            SetBusy(true);
            logBox.Clear();
            AppendLog("开始转换 " + totalCount + " 张图片");
            AppendLog("输出位置：" + directory);
            worker.RunWorkerAsync(request);
        }

        private void ConvertFiles(object sender, DoWorkEventArgs e)
        {
            ConversionRequest request = (ConversionRequest)e.Argument;
            string temporaryDirectory = Path.Combine(
                Path.GetTempPath(), "RoundedIcoApp-" + Guid.NewGuid().ToString("N"));
            string scriptPath = Path.Combine(temporaryDirectory, "converter.ps1");

            try
            {
                Directory.CreateDirectory(temporaryDirectory);
                ExtractScript(scriptPath);

                string command = BuildPowerShellCommand(scriptPath, request);
                string encodedCommand = Convert.ToBase64String(
                    Encoding.Unicode.GetBytes(command));

                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe");
                startInfo.Arguments =
                    "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand "
                    + encodedCommand;
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.RedirectStandardOutput = true;
                startInfo.RedirectStandardError = true;
                startInfo.StandardOutputEncoding = Encoding.UTF8;
                startInfo.StandardErrorEncoding = Encoding.UTF8;
                startInfo.WorkingDirectory = Application.StartupPath;

                using (Process process = new Process())
                {
                    process.StartInfo = startInfo;
                    process.OutputDataReceived += delegate(object outputSender, DataReceivedEventArgs outputArgs)
                    {
                        if (!String.IsNullOrEmpty(outputArgs.Data) && !IsPowerShellNoise(outputArgs.Data))
                        {
                            worker.ReportProgress(0, outputArgs.Data);
                        }
                    };
                    process.ErrorDataReceived += delegate(object errorSender, DataReceivedEventArgs errorArgs)
                    {
                        if (!String.IsNullOrEmpty(errorArgs.Data) && !IsPowerShellNoise(errorArgs.Data))
                        {
                            worker.ReportProgress(0, "错误：" + errorArgs.Data);
                        }
                    };

                    if (!process.Start())
                    {
                        throw new InvalidOperationException("无法启动 Windows PowerShell。");
                    }

                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();
                    process.WaitForExit();
                    e.Result = process.ExitCode;
                }
            }
            finally
            {
                try
                {
                    if (Directory.Exists(temporaryDirectory))
                    {
                        Directory.Delete(temporaryDirectory, true);
                    }
                }
                catch (Exception)
                {
                }
            }
        }

        // PowerShell 在标准输出被重定向时会把进度记录序列化成一大坨 CLIXML
        // 丢到标准错误里，这里直接无视，免得日志里全是乱码。
        private static bool IsPowerShellNoise(string line)
        {
            return line.StartsWith("#< CLIXML", StringComparison.Ordinal)
                || line.StartsWith("<Objs", StringComparison.Ordinal);
        }

        private static string BuildPowerShellCommand(string scriptPath, ConversionRequest request)
        {
            StringBuilder command = new StringBuilder();
            command.Append("[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false);");
            command.Append("$OutputEncoding=[Console]::OutputEncoding;");
            command.Append("& ").Append(PowerShellQuote(scriptPath));
            command.Append(" -OutputDir ").Append(PowerShellQuote(request.OutputDirectory));
            command.Append(" -RadiusPercent ").Append(request.RadiusPercent);
            command.Append(" -PaddingPercent ").Append(request.PaddingPercent);
            if (request.TrimBorder)
            {
                command.Append(" -TrimBorder");
            }
            command.Append(" -NoOpenDialog -InputPath @(");

            for (int i = 0; i < request.Files.Count; i++)
            {
                if (i > 0)
                {
                    command.Append(",");
                }
                command.Append(PowerShellQuote(request.Files[i]));
            }

            command.Append(")");
            return command.ToString();
        }

        private static string PowerShellQuote(string value)
        {
            return "'" + value.Replace("'", "''") + "'";
        }

        private static void ExtractScript(string targetPath)
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream source = assembly.GetManifestResourceStream(ScriptResourceName))
            {
                if (source == null)
                {
                    throw new InvalidOperationException("EXE 内没有找到转换引擎。");
                }

                using (FileStream target = File.Create(targetPath))
                {
                    source.CopyTo(target);
                }
            }
        }

        private void OnWorkerProgress(object sender, ProgressChangedEventArgs e)
        {
            string line = Convert.ToString(e.UserState);
            if (line.Length == 0)
            {
                return;
            }

            if (line.StartsWith("已生成", StringComparison.Ordinal))
            {
                doneCount++;
                if (doneCount > progressBar.Maximum)
                {
                    progressBar.Maximum = doneCount;
                }
                progressBar.Value = doneCount;
                statusLabel.Text = "正在转换 " + doneCount + " / " + totalCount;
            }
            else if (line.StartsWith("正在处理", StringComparison.Ordinal))
            {
                statusLabel.Text = line;
            }

            AppendLog(line);
        }

        private void ConversionCompleted(object sender, RunWorkerCompletedEventArgs e)
        {
            SetBusy(false);

            if (e.Error != null)
            {
                AppendLog("转换未完成：" + e.Error.Message);
                statusLabel.Text = "转换失败";
                MessageBox.Show(this, e.Error.Message, Text,
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            int exitCode = (int)e.Result;
            if (exitCode == 0)
            {
                AppendLog("全部完成，共生成 " + doneCount + " 个 .ico 文件。");
                statusLabel.Text = "转换完成，已生成 " + doneCount + " 个 .ico 文件";
            }
            else
            {
                AppendLog("转换程序返回错误代码：" + exitCode);
                statusLabel.Text = "转换失败，请查看运行日志";
                MessageBox.Show(this, "转换失败，请查看窗口中的运行日志。",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void SetBusy(bool busy)
        {
            isBusy = busy;
            chooseButton.Enabled = !busy;
            clearButton.Enabled = !busy;
            convertButton.Enabled = !busy;
            browseButton.Enabled = !busy;
            resetOutputButton.Enabled = !busy;
            openOutputButton.Enabled = !busy;
            radiusBox.Enabled = !busy;
            paddingBox.Enabled = !busy;
            trimCheck.Enabled = !busy;
            outputField.Enabled = !busy;
            fileList.Enabled = !busy;
            AllowDrop = !busy;
            progressBar.Visible = busy;
            UseWaitCursor = busy;
        }

        private void SaveSettings()
        {
            settings.OutputDirectory = EffectiveOutputDirectory;
            settings.RadiusPercent = radiusBox.Value;
            settings.PaddingPercent = paddingBox.Value;
            settings.TrimBorder = trimCheck.Checked;
            settings.Save();
        }

        private void AppendLog(string text)
        {
            if (logBox.TextLength > 0)
            {
                logBox.AppendText(Environment.NewLine);
            }
            logBox.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + text);
            logBox.SelectionStart = logBox.TextLength;
            logBox.ScrollToCaret();
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            ActiveControl = chooseButton;
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (isBusy)
            {
                e.Cancel = true;
                MessageBox.Show(this, "图片仍在转换，请等转换完成后再关闭。",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            SaveSettings();
        }

        private sealed class ConversionRequest
        {
            public List<string> Files;
            public string OutputDirectory;
            public int RadiusPercent;
            public int PaddingPercent;
            public bool TrimBorder;
        }
    }
}
