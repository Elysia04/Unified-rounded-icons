using System;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("图片转圆角 ICO")]
[assembly: System.Reflection.AssemblyDescription("把 PNG / JPG / JPEG 图片转换成多尺寸圆角 ICO 图标")]
[assembly: System.Reflection.AssemblyProduct("图片转圆角 ICO")]
[assembly: System.Reflection.AssemblyCopyright("")]
[assembly: System.Reflection.AssemblyVersion("2.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.0.0.0")]

namespace RoundedIcoApp
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                Application.Run(new MainForm(args));
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "图片转圆角 ICO",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}