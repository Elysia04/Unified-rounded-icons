using System;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace RoundedIcoApp
{
    /// <summary>界面设置，存在 %APPDATA%\图片转圆角ICO\settings.ini。</summary>
    internal sealed class Settings
    {
        public string OutputDirectory = DefaultOutputDirectory;
        public int RadiusPercent = 28;
        public int PaddingPercent = 0;
        public bool TrimBorder = true;

        public static string DefaultOutputDirectory
        {
            get { return Path.Combine(Application.StartupPath, "修改图标存放"); }
        }

        public static string StoragePath
        {
            get
            {
                string folder = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "图片转圆角ICO");
                return Path.Combine(folder, "settings.ini");
            }
        }

        public void Load()
        {
            try
            {
                string path = StoragePath;
                if (!File.Exists(path))
                {
                    return;
                }

                foreach (string raw in File.ReadAllLines(path, Encoding.UTF8))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#"))
                    {
                        continue;
                    }

                    int split = line.IndexOf('=');
                    if (split <= 0)
                    {
                        continue;
                    }

                    string key = line.Substring(0, split).Trim();
                    string text = line.Substring(split + 1).Trim();
                    int number;

                    if (key.Equals("OutputDirectory", StringComparison.OrdinalIgnoreCase))
                    {
                        if (text.Length > 0)
                        {
                            OutputDirectory = text;
                        }
                    }
                    else if (key.Equals("RadiusPercent", StringComparison.OrdinalIgnoreCase)
                        && int.TryParse(text, out number))
                    {
                        RadiusPercent = number;
                    }
                    else if (key.Equals("PaddingPercent", StringComparison.OrdinalIgnoreCase)
                        && int.TryParse(text, out number))
                    {
                        PaddingPercent = number;
                    }
                    else if (key.Equals("TrimBorder", StringComparison.OrdinalIgnoreCase))
                    {
                        TrimBorder = text == "1" || text.Equals("true", StringComparison.OrdinalIgnoreCase);
                    }
                }
            }
            catch (Exception)
            {
            }
        }

        public void Save()
        {
            try
            {
                string path = StoragePath;
                string folder = Path.GetDirectoryName(path);
                if (!String.IsNullOrEmpty(folder) && !Directory.Exists(folder))
                {
                    Directory.CreateDirectory(folder);
                }

                StringBuilder text = new StringBuilder();
                text.AppendLine("# 图片转圆角 ICO 的设置，删掉本文件即可恢复默认。");
                text.AppendLine("OutputDirectory=" + OutputDirectory);
                text.AppendLine("RadiusPercent=" + RadiusPercent);
                text.AppendLine("PaddingPercent=" + PaddingPercent);
                text.AppendLine("TrimBorder=" + (TrimBorder ? "1" : "0"));
                File.WriteAllText(path, text.ToString(), new UTF8Encoding(true));
            }
            catch (Exception)
            {
            }
        }
    }
}