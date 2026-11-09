// EasySslInstaller.exe: EasySslInstaller.ps1'i gömülü kaynak olarak taşır ve kendi PowerShell çalışma alanında (STA) çalıştırır.
using System;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("Easy SSL Installer for IIS")]
[assembly: AssemblyProduct("Easy SSL Installer for IIS")]
[assembly: AssemblyDescription("Install SSL certificates and update HTTPS bindings on IIS")]
[assembly: AssemblyCompany("Softviser Yazılım")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Softviser Yazılım. MIT License.")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

static class Program
{
    [STAThread]
    static void Main()
    {
        string script;
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("EasySslInstaller.ps1"))
        using (var r = new StreamReader(s)) script = r.ReadToEnd();
        try
        {
            using (var rs = RunspaceFactory.CreateRunspace())
            {
                rs.ApartmentState = ApartmentState.STA;   // OpenFileDialog STA ister
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(script).Invoke();
                    foreach (var e in ps.Streams.Error)
                        MessageBox.Show(e.ToString(), "Easy SSL Installer for IIS", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Easy SSL Installer for IIS", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
