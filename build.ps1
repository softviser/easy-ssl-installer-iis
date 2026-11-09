# EasySslInstaller.ps1 + Host.cs -> EasySslInstaller.exe
# Windows'taki hazır .NET Framework C# derleyicisini kullanır; ek kurulum/indirme gerekmez.
param([string]$Script = "$PSScriptRoot\EasySslInstaller.ps1", [string]$Out = "$PSScriptRoot\EasySslInstaller.exe", [switch]$NoAdmin)
$csc = "$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
$sma = [PSObject].Assembly.Location   # System.Management.Automation.dll (çalışan PowerShell'inki)
$cscArgs = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize', "/out:$Out",
             "/resource:$Script,EasySslInstaller.ps1", "/reference:$sma", '/reference:System.Windows.Forms.dll', "$PSScriptRoot\Host.cs")
if (-not $NoAdmin) { $cscArgs += "/win32manifest:$PSScriptRoot\app.manifest" }   # -NoAdmin yalnızca test içindir
if (-not (Test-Path "$PSScriptRoot\EasySslInstaller.ico")) { & "$PSScriptRoot\make-icon.ps1" | Out-Null }
$cscArgs += "/win32icon:$PSScriptRoot\EasySslInstaller.ico"
& $csc @cscArgs
if ($LASTEXITCODE) { throw "csc başarısız ($LASTEXITCODE)" }
Get-Item $Out | Select-Object Name, Length
