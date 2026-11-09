#Requires -Version 5.1
# Easy SSL Installer for IIS - tek dosya PowerShell/WinForms uygulaması
# https://github.com/softviser/easy-ssl-installer-iis
# Yapar: https binding'leri ve LocalMachine\My sertifikalarını listeler; PFX, PEM bundle (crt + key + ca-bundle)
#        veya sertifika sağlayıcısından gelen ZIP'i yükler; yükleme sonrası alan adı uyan binding'lere atamayı önerir;
#        seçili binding'lere sertifika atar, kullanılmayan sertifikayı siler.
#        Her işlem ekrandaki kayıt paneline ve uygulamanın yanındaki EasySslInstaller.log dosyasına yazılır.
$ErrorActionPreference = 'Stop'
$appName = 'Easy SSL Installer for IIS'; $appVersion = '1.3.0'
$repoUrl = 'https://github.com/softviser/easy-ssl-installer-iis'; $siteUrl = 'https://www.softviser.com.tr'

# Exe olarak derlenince $PSCommandPath boş gelir; o zaman kendi exe yolumuzu kullanırız.
$selfPath = if ($PSCommandPath) { $PSCommandPath } else { [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$selfPath`"" }
    else { Start-Process $selfPath -Verb RunAs }
    exit
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try { Import-Module WebAdministration } catch {
    [Windows.Forms.MessageBox]::Show("WebAdministration modülü yok. Bu makinede IIS kurulu mu?", $appName) | Out-Null; exit 1
}

# ---------- log ----------
$logFile = Join-Path (Split-Path $selfPath) 'EasySslInstaller.log'   # shortcut: klasör yazılamazsa dosya logu sessizce atlanır
$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'; $logBox.Dock = 'Bottom'; $logBox.Height = 140
$logBox.Font = New-Object Drawing.Font('Consolas', 9)
function Write-Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    $logBox.AppendText($line + "`r`n")
    try { Add-Content -Path $logFile -Value $line -Encoding UTF8 } catch { }
}
function Show-Error($msg) { Write-Log "HATA  $msg"; [Windows.Forms.MessageBox]::Show($msg, $appName, 'OK', 'Error') | Out-Null }
function Invoke-Safe($sb) { try { & $sb } catch { Show-Error $_.Exception.Message } }

# ---------- veri ----------
function Days-Left([datetime]$d) { [int][Math]::Floor(($d - (Get-Date)).TotalDays) }

function Get-Certs {
    Get-ChildItem Cert:\LocalMachine\My | Sort-Object NotAfter -Descending | ForEach-Object {
        [pscustomobject]@{
            Konu       = $_.Subject
            SAN        = (($_.DnsNameList | ForEach-Object Unicode) -join ', ')
            Bitis      = $_.NotAfter.ToString('yyyy-MM-dd')
            Kalan      = Days-Left $_.NotAfter
            Anahtar    = if ($_.HasPrivateKey) { 'var' } else { 'YOK' }
            Thumbprint = $_.Thumbprint
        }
    }
}

function Cert-Name($c) { if ($c.Subject -match 'CN=([^,]+)') { $Matches[1] } else { $c.Subject } }
function Cert-Names($c) { @($c.DnsNameList | ForEach-Object Unicode) }
# Depodaki, alan adına uyan, süresi geçmemiş ve özel anahtarı olan en uzun ömürlü sertifika.
function Best-Cert($certs, $h) {
    if (-not $h) { return $null }
    $certs | Where-Object { (Days-Left $_.NotAfter) -ge 0 -and (Match-Host (Cert-Names $_) $h) } | Sort-Object NotAfter -Descending | Select-Object -First 1
}

# IIS'teki her site ve alan adı (http + https binding) ile SSL durumu ve depodan önerilen sertifika.
function Get-Domains {
    $certs = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object HasPrivateKey)
    foreach ($s in Get-Website) {
        foreach ($b in ($s.Bindings.Collection | Where-Object { $_.protocol -in 'http', 'https' })) {
            $https = $b.protocol -eq 'https'; $h = ($b.bindingInformation -split ':')[2]
            $c = $null
            if ($https -and $b.certificateHash) {
                $store = if ($b.certificateStoreName) { $b.certificateStoreName } else { 'My' }
                $c = Get-Item "Cert:\LocalMachine\$store\$($b.certificateHash)" -ErrorAction SilentlyContinue
            }
            $days = if ($c) { Days-Left $c.NotAfter } else { '' }
            $status = if (-not $https) { 'HTTPS yok' }
                      elseif (-not $c) { 'Sertifika yok' }
                      elseif ($days -lt 0) { 'Süresi dolmuş' }
                      elseif ($h -and -not (Match-Host (Cert-Names $c) $h)) { 'Alan adı uyuşmuyor' }
                      elseif ($days -lt 30) { "$days gün kaldı" }
                      else { 'Geçerli' }
            $best = Best-Cert $certs $h
            if ($best -and $c -and $best.Thumbprint -eq $c.Thumbprint) { $best = $null }   # zaten takılı olanı önerme
            [pscustomobject]@{
                Site       = $s.Name
                Durum      = if ($s.State -eq 'Started') { 'çalışıyor' } else { "$($s.State)".ToLower() }
                AlanAdi    = $h
                Protokol   = $b.protocol
                Binding    = $b.bindingInformation
                SNI        = if ($https -and ($b.sslFlags -band 1)) { 'evet' } else { '' }
                Sertifika  = if ($c) { Cert-Name $c } else { '' }
                Bitis      = if ($c) { $c.NotAfter.ToString('yyyy-MM-dd') } else { '' }
                Kalan      = $days
                SSL        = $status
                Onerilen   = if ($best) { "$(Cert-Name $best) ($($best.NotAfter.ToString('yyyy-MM-dd')))" } else { '' }
                Canli      = ''
                Thumbprint = if ($https) { "$($b.certificateHash)" } else { '' }
                Oneri      = if ($best) { $best.Thumbprint } else { '' }
            }
        }
    }
}
function Get-Bindings { Get-Domains | Where-Object Protokol -eq 'https' }

# Binding'e gerçekten bağlanıp sunulan sertifikanın thumbprint'ini okur (SNI ile); hata metni döner.
# shortcut: IPv6 binding ve TLS 1.3 denenmez, 3 sn bağlantı zaman aşımı
function Probe-Ssl($bindingInfo) {
    $ip, $port, $h = $bindingInfo -split ':'
    $target = if ($ip -and $ip -ne '*') { $ip } else { '127.0.0.1' }
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        if (-not $tcp.ConnectAsync($target, [int]$port).Wait(3000)) { return 'bağlantı yok' }
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($(if ($h) { $h } else { $target }), $null, [Security.Authentication.SslProtocols]'Tls12, Tls11, Tls', $false)
        (New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate).Thumbprint
    } catch { "hata: $($_.Exception.GetBaseException().Message)" } finally { $tcp.Close() }
}
function Probe-All {
    $form.Cursor = 'WaitCursor'
    try {
        $n = 0
        foreach ($r in $gridB.Rows) {
            if ($r.Cells['Protokol'].Value -ne 'https') { continue }
            $got = Probe-Ssl $r.Cells['Binding'].Value; $n++
            $r.Cells['Canli'].Value = if ($got -eq $r.Cells['Thumbprint'].Value) { 'OK, aynı sertifika' } elseif ($got -match '^[0-9A-F]{40}$') { "FARKLI: $($got.Substring(0,8))..." } else { $got }
            Write-Log "CANLI  $($r.Cells['Site'].Value) [$($r.Cells['Binding'].Value)]  $($r.Cells['Canli'].Value)"
        }
        Write-Log "CANLI  $n binding sorgulandı"
    } finally { $form.Cursor = 'Default' }
}

# http binding'i olan alan adına https binding açıp sertifikayı takar.
function Add-HttpsBinding($site, $ip, $h, $thumb) {
    $info = "$($ip):443:$h"
    if (Get-WebBinding -Name $site -Protocol https | Where-Object bindingInformation -eq $info) { throw "$site için $info binding'i zaten var." }
    $p = @{ Name = $site; Protocol = 'https'; Port = 443; HostHeader = $h; SslFlags = 1 }
    if ($ip -and $ip -ne '*') { $p.IPAddress = $ip }
    New-WebBinding @p
    Write-Log "BINDING  $site  https $info eklendi (SNI)"
    Set-BindingCert $site $info '' $thumb
}

function Set-BindingCert($site, $bindingInfo, $oldThumb, $thumb) {
    $b = Get-WebBinding -Name $site -Protocol https | Where-Object bindingInformation -eq $bindingInfo
    try { $b.RemoveSslCertificate() } catch { }   # boş binding'de hata verir, önemsiz
    $b.AddSslCertificate($thumb, 'My')
    Write-Log "ATAMA  $site [$bindingInfo]  $oldThumb -> $thumb"
}

function Import-Pfx($path, $pass) {
    $sec = if ($pass) { ConvertTo-SecureString $pass -AsPlainText -Force } else { New-Object Security.SecureString }
    $c = Import-PfxCertificate -FilePath $path -CertStoreLocation Cert:\LocalMachine\My -Password $sec -Exportable
    Write-Log "YÜKLEME  $path -> LocalMachine\My  $($c.Subject)  $($c.Thumbprint)  bitiş $($c.NotAfter.ToString('yyyy-MM-dd'))"
    $c
}

# PEM cert + key -> PFX dönüşümü certutil ile (OpenSSL gerekmez), CA bundle doğrudan Intermediate CA deposuna.
# shortcut: şifreli .key desteklenmez, gerekirse certutil -p "keypass,pfxpass" ile genişlet
function Import-PemBundle($crt, $key, $ca) {
    $tmp = Join-Path $env:TEMP ("EasySsl_" + [guid]::NewGuid())
    New-Item -ItemType Directory $tmp | Out-Null
    try {
        Copy-Item $crt "$tmp\cert.cer"; Copy-Item $key "$tmp\cert.key"
        $out = certutil -f -p ',EasySslTmp' -MergePFX "$tmp\cert.cer" "$tmp\cert.pfx" 2>&1
        if ($LASTEXITCODE) { throw "certutil -MergePFX başarısız (anahtar şifreli veya sertifikayla eşleşmiyor olabilir):`n$out" }
        Write-Log "DÖNÜŞÜM  $crt + $key -> PFX"
        $cert = Import-Pfx "$tmp\cert.pfx" 'EasySslTmp'
        if ($ca) { certutil -f -addstore CA $ca | Out-Null; Write-Log "CA  $ca -> LocalMachine\CA (Intermediate)" }
        $cert
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# Sağlayıcıdan gelen ZIP: içinde PFX varsa onu, yoksa sunucu sertifikası + anahtar + CA dosyalarını içeriğine bakarak ayırır.
# shortcut: DER (ikili) sertifika ve anahtarla sertifikayı aynı dosyada taşıyan PEM tanınmaz, gerekirse elle PEM alanlarını kullanın
function Import-Zip($zip, $pass, $keyFallback) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = Join-Path $env:TEMP ("EasySslZip_" + [guid]::NewGuid())
    New-Item -ItemType Directory $tmp | Out-Null
    try {
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try { foreach ($e in $z.Entries) { if ($e.Name) { [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $tmp $e.Name), $true) } } } finally { $z.Dispose() }
        $files = @(Get-ChildItem $tmp -File)
        Write-Log "ZIP  $zip  ->  $($files.Name -join ', ')"
        $pfx = $files | Where-Object { $_.Extension -in '.pfx', '.p12' } | Select-Object -First 1
        if ($pfx) { return Import-Pfx $pfx.FullName $pass }
        $key = $null; $leaf = $null; $ca = @()
        foreach ($f in $files) {
            $txt = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($txt -match 'PRIVATE KEY-----') { if (-not $key) { $key = $f.FullName }; continue }
            $n = ([regex]::Matches([string]$txt, '-----BEGIN CERTIFICATE-----')).Count
            if ($n -eq 0) { continue }
            if ($n -eq 1 -and -not $leaf) {
                $c = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $f.FullName
                $isCa = @($c.Extensions | Where-Object { $_ -is [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension] -and $_.CertificateAuthority }).Count
                if (-not $isCa) { $leaf = $f.FullName; continue }
            }
            $ca += $f.FullName
        }
        if (-not $key) { $key = $keyFallback }
        if (-not $leaf) { throw 'ZIP içinde sunucu sertifikası (PEM) veya PFX bulunamadı.' }
        if (-not $key) { throw "ZIP içinde özel anahtar yok. 'Anahtar (.key)' alanına anahtar dosyasını verip tekrar deneyin." }
        $caFile = $null
        if ($ca) { $caFile = Join-Path $tmp 'ca-bundle.crt'; (($ca | ForEach-Object { (Get-Content $_ -Raw).Trim() }) -join "`n") | Set-Content $caFile -Encoding Ascii }
        Import-PemBundle $leaf $key $caFile
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# Alan adı sertifikanın SAN listesine uyar mı (joker tek seviye)?
function Match-Host($names, $h) {
    if (-not $h) { return $false }
    foreach ($n in $names) {
        if ($h -eq $n) { return $true }
        if ($n.StartsWith('*.') -and $h -like $n -and $h.Split('.').Count -eq $n.Split('.').Count) { return $true }
    }
    $false
}
# Yeni sertifikaya uyan binding'ler: alan adı SAN'da olan ya da aynı alan adları için verilmiş eski sertifikayı kullanan (yenileme).
function Find-MatchingBindings($cert) {
    $names = @($cert.DnsNameList | ForEach-Object Unicode)
    foreach ($r in @(Get-Bindings)) {
        if ($r.Thumbprint -eq $cert.Thumbprint) { continue }
        $old = if ($r.Thumbprint) { Get-Item "Cert:\LocalMachine\My\$($r.Thumbprint)" -ErrorAction SilentlyContinue }
        $renew = $old -and @($old.DnsNameList | ForEach-Object Unicode | Where-Object { $names -contains $_ }).Count
        if ($renew -or (Match-Host $names ($r.Binding -split ':')[2])) { $r }
    }
}
function Auto-Assign($cert) {
    $hits = @(Find-MatchingBindings $cert)
    if (-not $hits) { Write-Log 'OTOMATİK ATAMA  uyan binding yok'; return }
    $lines = $hits | ForEach-Object { "$($_.Site) [$($_.Binding)]" + $(if ($_.Sertifika) { "  (şu an: $($_.Sertifika), bitiş $($_.Bitis))" } else { '  (sertifikasız)' }) }
    $q = "Yeni sertifika şu binding'lere uyuyor:`n`n$($lines -join "`n")`n`n-> $($cert.Subject)`n   bitiş $($cert.NotAfter.ToString('yyyy-MM-dd'))`n`nHepsine atansın mı?"
    if ([Windows.Forms.MessageBox]::Show($q, 'Otomatik atama', 'YesNo', 'Question') -ne 'Yes') { Write-Log 'OTOMATİK ATAMA  kullanıcı iptal etti'; return }
    foreach ($r in $hits) { Set-BindingCert $r.Site $r.Binding $r.Thumbprint $cert.Thumbprint }
    Refresh-All
}

function Remove-Cert($thumb, $subject) {
    Remove-Item "Cert:\LocalMachine\My\$thumb" -DeleteKey
    Write-Log "SİLME  $subject  $thumb  (özel anahtarla birlikte)"
}

# DataGridView PSCustomObject'e bağlanamaz, DataTable'a çeviriyoruz.
function ConvertTo-Table($rows) {
    $t = New-Object Data.DataTable
    $rows = @($rows)
    if (-not $rows) { return ,$t }
    foreach ($p in $rows[0].PSObject.Properties) { [void]$t.Columns.Add($p.Name) }
    foreach ($r in $rows) { [void]$t.Rows.Add(@($r.PSObject.Properties | ForEach-Object { "$($_.Value)" })) }
    ,$t   # virgül şart: PowerShell DataTable'ı satırlarına açar
}

# ---------- GUI yardımcıları ----------
function New-Grid {
    $g = New-Object Windows.Forms.DataGridView
    $g.Dock = 'Fill'; $g.ReadOnly = $true; $g.AllowUserToAddRows = $false
    $g.SelectionMode = 'FullRowSelect'; $g.AutoSizeColumnsMode = 'Fill'; $g.RowHeadersVisible = $false
    # sağ tık da satırı seçsin
    $g.Add_CellMouseDown({ param($s, $e) if ($e.Button -eq 'Right' -and $e.RowIndex -ge 0) { $s.ClearSelection(); $s.Rows[$e.RowIndex].Selected = $true } })
    $g
}
function Color-Expiry($g) {
    foreach ($r in $g.Rows) {
        $k = $r.Cells['Kalan'].Value
        if ($k -eq '') { continue }
        if ([int]$k -lt 0) { $r.DefaultCellStyle.BackColor = 'MistyRose' } elseif ([int]$k -lt 30) { $r.DefaultCellStyle.BackColor = 'LemonChiffon' }
    }
}
function Fit-Columns($g) {
    foreach ($c in $g.Columns) {
        switch ($c.Name) {
            'Konu'       { $c.FillWeight = 180 }
            'SAN'        { $c.FillWeight = 150 }
            'Site'       { $c.FillWeight = 110 }
            'Durum'      { $c.FillWeight = 55 }
            'AlanAdi'    { $c.FillWeight = 120; $c.HeaderText = 'Alan adı' }
            'Protokol'   { $c.FillWeight = 45; $c.HeaderText = 'Prot.' }
            'Binding'    { $c.FillWeight = 100 }
            'Sertifika'  { $c.FillWeight = 120 }
            'SSL'        { $c.FillWeight = 95; $c.HeaderText = 'SSL durumu' }
            'Onerilen'   { $c.FillWeight = 130; $c.HeaderText = 'Önerilen sertifika' }
            'Canli'      { $c.FillWeight = 110; $c.HeaderText = 'Canlı sorgu' }
            'Thumbprint' { $c.FillWeight = 120 }
            'Oneri'      { $c.Visible = $false }
            'Bitis'      { $c.FillWeight = 60; $c.HeaderText = 'Bitiş' }
            'Kalan'      { $c.FillWeight = 40; $c.HeaderText = 'Gün'; $c.DefaultCellStyle.Alignment = 'MiddleRight' }
            'SNI'        { $c.FillWeight = 35 }
            'Anahtar'    { $c.FillWeight = 50 }
        }
    }
}
function Color-Status($g) {
    foreach ($r in $g.Rows) {
        $cell = $r.Cells['SSL']; $s = "$($cell.Value)"
        $cell.Style.BackColor = switch -Wildcard ($s) { 'Geçerli' { 'Honeydew' } 'HTTPS yok' { 'WhiteSmoke' } '*gün kaldı' { 'LemonChiffon' } default { 'MistyRose' } }
        if ($r.Cells['Onerilen'].Value) { $r.Cells['Onerilen'].Style.ForeColor = 'DarkGreen' }
    }
}
function New-Button($text, $x, $y, $w, $onClick) {
    $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = "$x,$y"; $b.Size = "$w,24"
    $b.Tag = $onClick; $b.Add_Click({ Invoke-Safe $this.Tag })
    $b
}
function Add-MenuItem($parent, $text, $onClick, $shortcut) {
    $i = New-Object Windows.Forms.ToolStripMenuItem $text
    $i.Tag = $onClick; $i.Add_Click({ Invoke-Safe $this.Tag })
    if ($shortcut) { $i.ShortcutKeys = $shortcut }
    # koleksiyonu değişkene almayın: PowerShell boş koleksiyonu açıp $null yapar
    if ($parent -is [Windows.Forms.ToolStripMenuItem]) { [void]$parent.DropDownItems.Add($i) } else { [void]$parent.Items.Add($i) }
    $i
}
# Etiket + metin kutusu + Gözat düğmesi satırı; metin kutusunu döndürür.
function Add-FileRow($panel, $y, $label, $filter) {
    $l = New-Object Windows.Forms.Label; $l.Text = $label; $l.Location = "10,$($y + 4)"; $l.Width = 110
    $t = New-Object Windows.Forms.TextBox; $t.Location = "120,$y"; $t.Width = 520; $t.Anchor = 'Top,Left,Right'
    $t.AllowDrop = $true
    $t.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent('FileDrop')) { $e.Effect = 'Copy' } })
    $t.Add_DragDrop({ param($s, $e) $s.Text = @($e.Data.GetData('FileDrop'))[0] })
    $g = New-Button 'Gözat...' 648 ($y - 1) 70 { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = $filter; if ($d.ShowDialog() -eq 'OK') { $t.Text = $d.FileName } }.GetNewClosure()
    $g.Anchor = 'Top,Right'
    $panel.Controls.AddRange(@($l, $t, $g)); $t
}
function Selected-Cert {
    if ($gridC.SelectedRows.Count -ne 1) { throw 'Alt listeden bir sertifika seçin.' }
    $gridC.SelectedRows[0]
}
function Select-Cert($thumb) {
    foreach ($r in $gridC.Rows) {
        if ($r.Cells['Thumbprint'].Value -eq $thumb) { $gridC.ClearSelection(); $r.Selected = $true; $gridC.FirstDisplayedScrollingRowIndex = $r.Index; return }
    }
}
# Her yüklemeden sonra: alanları temizle, listeyi yenile, yeni sertifikayı seç, uyan binding'lere atamayı öner.
function After-Import($cert, $boxes) {
    foreach ($b in $boxes) { $b.Text = '' }
    Refresh-All; Select-Cert $cert.Thumbprint; Auto-Assign $cert
}
function Show-About {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Hakkında'; $f.ClientSize = '420,260'; $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false; $f.Icon = $form.Icon
    $pic = New-Object Windows.Forms.PictureBox; $pic.Location = '20,20'; $pic.Size = '48,48'; $pic.SizeMode = 'StretchImage'
    if ($form.Icon) { $pic.Image = (New-Object Drawing.Icon $form.Icon, 48, 48).ToBitmap() }
    $t = New-Object Windows.Forms.Label; $t.Text = $appName; $t.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold); $t.Location = '80,18'; $t.AutoSize = $true
    $v = New-Object Windows.Forms.Label; $v.Text = "Sürüm $appVersion  -  MIT lisansı, açık kaynak"; $v.Location = '82,50'; $v.AutoSize = $true
    $d = New-Object Windows.Forms.Label; $d.Location = '20,85'; $d.Size = '380,40'
    $d.Text = "IIS için SSL sertifikası yükleme ve binding güncelleme aracı. PFX, PEM bundle (crt + key + ca-bundle) ve sağlayıcı ZIP'i destekler."
    $en = New-Object Windows.Forms.Label; $en.Location = '20,128'; $en.Size = '380,32'; $en.ForeColor = 'DimGray'
    $en.Text = "Open source software released under the MIT License.`nDeveloped by Softviser Yazılım, Turkey."
    $by = New-Object Windows.Forms.Label; $by.Text = 'Softviser Yazılım'; $by.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold); $by.Location = '20,165'; $by.AutoSize = $true
    $l1 = New-Object Windows.Forms.LinkLabel; $l1.Text = 'www.softviser.com.tr'; $l1.Location = '20,185'; $l1.AutoSize = $true; $l1.Tag = $siteUrl
    $l2 = New-Object Windows.Forms.LinkLabel; $l2.Text = 'github.com/softviser/easy-ssl-installer-iis'; $l2.Location = '20,205'; $l2.AutoSize = $true; $l2.Tag = $repoUrl
    foreach ($l in $l1, $l2) { $l.Add_LinkClicked({ Start-Process $this.Tag }) }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Tamam'; $ok.Location = '320,222'; $ok.Size = '80,26'; $ok.DialogResult = 'OK'
    $f.Controls.AddRange(@($pic, $t, $v, $d, $en, $by, $l1, $l2, $ok)); $f.AcceptButton = $ok; $f.CancelButton = $ok
    [void]$f.ShowDialog($form)
}

# ---------- form ----------
$form = New-Object Windows.Forms.Form
$form.Text = "$appName - $env:COMPUTERNAME"; $form.Size = '1180,900'; $form.StartPosition = 'CenterScreen'; $form.MinimumSize = '960,640'
$ico = Join-Path (Split-Path $selfPath) 'EasySslInstaller.ico'
if (-not $PSCommandPath) { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon($selfPath) } elseif (Test-Path $ico) { $form.Icon = New-Object Drawing.Icon $ico }
$tip = New-Object Windows.Forms.ToolTip

# menü
$menu = New-Object Windows.Forms.MenuStrip
$mFile = $menu.Items.Add('Dosya'); $mHelp = $menu.Items.Add('Yardım')
[void](Add-MenuItem $mFile 'Yenile' { Refresh-All } ([Windows.Forms.Keys]::F5))
[void](Add-MenuItem $mFile 'Kayıt dosyasını aç' { if (Test-Path $logFile) { Start-Process notepad $logFile } else { throw 'Henüz kayıt dosyası oluşmadı.' } })
[void](Add-MenuItem $mFile 'Sertifika deposunu aç (certlm.msc)' { Start-Process certlm.msc })
[void]$mFile.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $mFile 'Çıkış' { $form.Close() })
[void](Add-MenuItem $mHelp 'GitHub sayfası' { Start-Process $repoUrl })
[void](Add-MenuItem $mHelp 'Softviser Yazılım' { Start-Process $siteUrl })
[void]$mHelp.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $mHelp 'Hakkında' { Show-About })
$form.MainMenuStrip = $menu

# yükleme paneli
$load = New-Object Windows.Forms.GroupBox; $load.Text = 'Sertifika yükle (PFX, PEM dosyaları veya sağlayıcıdan gelen ZIP; dosyaları sürükleyip bırakabilirsiniz)'; $load.Dock = 'Top'
$load.Size = "$($form.ClientSize.Width),180"   # anchor'lar doğru hesaplansın diye çocuklardan önce genişlik verilir
$txtPfx = Add-FileRow $load 22  'PFX dosyası:'      'PFX|*.pfx;*.p12|Tümü|*.*'
$txtPw  = New-Object Windows.Forms.TextBox; $txtPw.UseSystemPasswordChar = $true; $txtPw.Location = '790,22'; $txtPw.Width = 90; $txtPw.Anchor = 'Top,Right'
$lblPw  = New-Object Windows.Forms.Label; $lblPw.Text = 'Şifre:'; $lblPw.Location = '745,26'; $lblPw.Width = 45; $lblPw.Anchor = 'Top,Right'
$btnPfx = New-Button 'PFX Yükle' 886 21 95 {
    if (-not $txtPfx.Text) { throw 'PFX dosyası seçin.' }
    $c = Import-Pfx $txtPfx.Text $txtPw.Text; After-Import $c @($txtPfx, $txtPw)
}
$btnPfx.Anchor = 'Top,Right'; $tip.SetToolTip($btnPfx, 'PFX/P12 dosyasını özel anahtarıyla birlikte LocalMachine\My deposuna alır')
$txtCrt = Add-FileRow $load 55  'Sertifika (.crt):' 'Sertifika|*.crt;*.cer;*.pem|Tümü|*.*'
$txtKey = Add-FileRow $load 85  'Anahtar (.key):'   'Anahtar|*.key;*.pem|Tümü|*.*'
$txtCa  = Add-FileRow $load 115 'CA bundle (ops.):' 'CA bundle|*.ca-bundle;*.crt;*.cer;*.pem|Tümü|*.*'
$btnPem = New-Button 'PEM Bundle Yükle' 745 114 236 {
    if (-not $txtCrt.Text -or -not $txtKey.Text) { throw 'Sertifika (.crt) ve anahtar (.key) dosyalarını seçin.' }
    $c = Import-PemBundle $txtCrt.Text $txtKey.Text $txtCa.Text; After-Import $c @($txtCrt, $txtKey, $txtCa)
}
$btnPem.Anchor = 'Top,Right'; $tip.SetToolTip($btnPem, 'crt + key dosyasını certutil ile PFX''e çevirip yükler; CA bundle Intermediate CA deposuna gider')
$txtZip = Add-FileRow $load 145 'ZIP bundle:'       'ZIP|*.zip|Tümü|*.*'
$btnZip = New-Button 'ZIP Yükle' 745 144 236 {
    if (-not $txtZip.Text) { throw 'ZIP dosyası seçin.' }
    $c = Import-Zip $txtZip.Text $txtPw.Text $txtKey.Text; After-Import $c @($txtZip, $txtPw, $txtKey)
}
$btnZip.Anchor = 'Top,Right'; $tip.SetToolTip($btnZip, 'Sağlayıcının gönderdiği ZIP''i açar: içindeki PFX''i (şifre alanıyla) ya da crt + key + CA dosyalarını kendisi bulup yükler. ZIP''te anahtar yoksa Anahtar (.key) alanı kullanılır')
$load.Controls.AddRange(@($lblPw, $txtPw, $btnPfx, $btnPem, $btnZip))

# listeler
$split = New-Object Windows.Forms.SplitContainer; $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'
$lblB = New-Object Windows.Forms.Label; $lblB.Text = "IIS siteleri ve alan adları (http + https)   yeşil: geçerli, sarı: 30 günden az, kırmızı: sorun, gri: HTTPS yok   sağ tık: öneriyi uygula / HTTPS ekle"; $lblB.Dock = 'Top'; $lblB.Height = 18
$lblC = New-Object Windows.Forms.Label; $lblC.Text = 'Sertifikalar (LocalMachine\My)   sarı: 30 günden az kaldı, kırmızı: süresi doldu   sağ tık: kopyala / sil'; $lblC.Dock = 'Top'; $lblC.Height = 18
$gridB = New-Grid; $gridC = New-Grid; $gridC.MultiSelect = $false
$split.Panel1.Controls.AddRange(@($gridB, $lblB)); $split.Panel2.Controls.AddRange(@($gridC, $lblC))
$status = New-Object Windows.Forms.StatusStrip; $stLbl = New-Object Windows.Forms.ToolStripStatusLabel; $stLbl.Spring = $true; $stLbl.TextAlign = 'MiddleLeft'
$stLink = New-Object Windows.Forms.ToolStripStatusLabel 'Softviser Yazılım - www.softviser.com.tr'; $stLink.IsLink = $true; $stLink.Add_Click({ Start-Process $siteUrl })
[void]$status.Items.AddRange(@($stLbl, $stLink))

function Refresh-All {
    $rows = @(Get-Domains)
    $gridB.DataSource = ConvertTo-Table $rows; Fit-Columns $gridB; Apply-Filter
    $gridC.DataSource = ConvertTo-Table (Get-Certs); Fit-Columns $gridC; Color-Expiry $gridC
    $https = @($rows | Where-Object Protokol -eq 'https'); $bad = @($https | Where-Object { $_.SSL -ne 'Geçerli' })
    $httpsHosts = @($https | ForEach-Object AlanAdi); $noSsl = @($rows | Where-Object { $_.Protokol -eq 'http' -and $_.AlanAdi -and $_.AlanAdi -notin $httpsHosts })
    $stLbl.Text = "$(@($rows | Select-Object -ExpandProperty Site -Unique).Count) site, $(@($rows | Where-Object AlanAdi | Select-Object -ExpandProperty AlanAdi -Unique).Count) alan adı, $($https.Count) HTTPS binding ($($bad.Count) sorunlu), $($noSsl.Count) alan adında HTTPS yok, $($gridC.Rows.Count) sertifika"
    Write-Log "LİSTE  $($stLbl.Text)"
}
function Apply-Filter {
    $t = $gridB.DataSource; if (-not $t) { return }
    $q = $txtFilter.Text.Replace("'", "''").Replace('[', '[[]').Replace('%', '[%]')
    $t.DefaultView.RowFilter = if ($q) { "Site LIKE '%$q%' OR AlanAdi LIKE '%$q%' OR Sertifika LIKE '%$q%' OR SSL LIKE '%$q%'" } else { '' }
    Color-Expiry $gridB; Color-Status $gridB   # süzgeç satırları yeniden kurar, renkler burada verilir
}
function Selected-Domain {
    if ($gridB.SelectedRows.Count -ne 1) { throw 'Üst listeden bir satır seçin.' }
    $gridB.SelectedRows[0]
}

# sertifika sağ tık menüsü
$ctx = New-Object Windows.Forms.ContextMenuStrip
[void](Add-MenuItem $ctx "Thumbprint'i kopyala" { [Windows.Forms.Clipboard]::SetText((Selected-Cert).Cells['Thumbprint'].Value) })
[void](Add-MenuItem $ctx 'Konuyu kopyala' { [Windows.Forms.Clipboard]::SetText((Selected-Cert).Cells['Konu'].Value) })
[void]$ctx.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $ctx 'Sertifikayı sil...' {
    $row = Selected-Cert; $thumb = $row.Cells['Thumbprint'].Value; $subject = $row.Cells['Konu'].Value
    $used = @($gridB.Rows | Where-Object { $_.Cells['Thumbprint'].Value -eq $thumb })
    if ($used) { throw "Bu sertifika $($used.Count) binding'de kullanılıyor. Önce o binding'lere başka sertifika atayın." }
    $q = "$subject`n$thumb`n`nSertifika ve özel anahtarı depodan silinecek, geri alınamaz. Silinsin mi?"
    if ([Windows.Forms.MessageBox]::Show($q, 'Sertifikayı sil', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
    Remove-Cert $thumb $subject; Refresh-All
})
$gridC.ContextMenuStrip = $ctx

# işlem çubuğu
$bar = New-Object Windows.Forms.Panel; $bar.Dock = 'Top'; $bar.Height = 34
$bar.Controls.Add((New-Button 'Yenile (F5)' 10 5 90 { Refresh-All }))
$btnAssign = New-Button "Seçili binding'lere seçili sertifikayı ata" 110 5 260 {
    $sel = @($gridB.SelectedRows | Where-Object { $_.Cells['Protokol'].Value -eq 'https' })
    if (-not $sel) { throw "Üst listeden en az bir https satırı seçin (http satırlarına sağ tık: HTTPS binding ekle)." }
    $cert = Selected-Cert
    if ($cert.Cells['Anahtar'].Value -ne 'var') { throw "Bu sertifikanın özel anahtarı yok, binding'e atanamaz." }
    $targets = @($sel | ForEach-Object { "$($_.Cells['Site'].Value) [$($_.Cells['Binding'].Value)]" })
    $q = "$($targets -join "`n")`n`n-> $($cert.Cells['Konu'].Value)`n   bitiş $($cert.Cells['Bitis'].Value) ($($cert.Cells['Kalan'].Value) gün)`n`nAtansın mı?"
    if ([Windows.Forms.MessageBox]::Show($q, 'Onay', 'YesNo', 'Question') -ne 'Yes') { Write-Log 'ATAMA  kullanıcı iptal etti'; return }
    foreach ($r in $sel) { Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $cert.Cells['Thumbprint'].Value }
    Refresh-All
}
$tip.SetToolTip($btnAssign, 'Yenilemede: eski sertifikaya bağlı tüm binding''leri seçin, alttan yeni sertifikayı seçin, atayın')
$bar.Controls.Add($btnAssign)
$btnProbe = New-Button 'SSL''i canlı sorgula' 380 5 130 { Probe-All }
$tip.SetToolTip($btnProbe, 'Her https binding''e bu makineden bağlanır ve sunulan sertifikanın IIS''teki ile aynı olup olmadığını "Canlı sorgu" sütununa yazar')
$bar.Controls.Add($btnProbe)
$btnApplyAll = New-Button 'Tüm önerileri uygula' 520 5 140 {
    $rows = @($gridB.Rows | Where-Object { $_.Cells['Oneri'].Value -and $_.Cells['Protokol'].Value -eq 'https' })
    if (-not $rows) { throw 'Önerilen sertifikası olan https binding yok.' }
    $q = ($rows | ForEach-Object { "$($_.Cells['Site'].Value) [$($_.Cells['Binding'].Value)]  ->  $($_.Cells['Onerilen'].Value)" }) -join "`n"
    if ([Windows.Forms.MessageBox]::Show("$q`n`nHepsi atansın mı?", 'Önerileri uygula', 'YesNo', 'Question') -ne 'Yes') { Write-Log 'ATAMA  kullanıcı iptal etti'; return }
    foreach ($r in $rows) { Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $r.Cells['Oneri'].Value }
    Refresh-All
}
$tip.SetToolTip($btnApplyAll, 'Her https binding''e, alan adına uyan en uzun ömürlü sertifikayı (Önerilen sütunu) atar')
$bar.Controls.Add($btnApplyAll)
$lblFilter = New-Object Windows.Forms.Label; $lblFilter.Text = 'Süz:'; $lblFilter.Location = '680,9'; $lblFilter.Width = 32
$txtFilter = New-Object Windows.Forms.TextBox; $txtFilter.Location = '712,7'; $txtFilter.Width = 200; $txtFilter.Add_TextChanged({ Apply-Filter })
$tip.SetToolTip($txtFilter, 'Site, alan adı, sertifika veya SSL durumuna göre üst listeyi süzer')
$bar.Controls.AddRange(@($lblFilter, $txtFilter))

# alan adı sağ tık menüsü
$ctxB = New-Object Windows.Forms.ContextMenuStrip
[void](Add-MenuItem $ctxB 'Önerilen sertifikayı bu binding''e ata' {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'https') { throw "Bu bir http binding'i; 'HTTPS binding ekle' seçeneğini kullanın." }
    if (-not $r.Cells['Oneri'].Value) { throw 'Bu alan adı için depoda uygun sertifika yok. Önce sertifikayı yükleyin.' }
    $q = "$($r.Cells['Site'].Value) [$($r.Cells['Binding'].Value)]`n`n-> $($r.Cells['Onerilen'].Value)`n`nAtansın mı?"
    if ([Windows.Forms.MessageBox]::Show($q, 'Onay', 'YesNo', 'Question') -ne 'Yes') { return }
    Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $r.Cells['Oneri'].Value; Refresh-All
})
[void](Add-MenuItem $ctxB 'HTTPS binding ekle (önerilen sertifikayla)...' {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'http') { throw 'Bu satır zaten https.' }
    if (-not $r.Cells['AlanAdi'].Value) { throw 'Alan adı olmayan binding için HTTPS eklenmez; IIS''te elle ekleyin.' }
    if (-not $r.Cells['Oneri'].Value) { throw 'Bu alan adı için depoda uygun sertifika yok. Önce sertifikayı yükleyin.' }
    $ip = ($r.Cells['Binding'].Value -split ':')[0]
    $q = "$($r.Cells['Site'].Value) sitesine ${ip}:443:$($r.Cells['AlanAdi'].Value) (SNI) binding'i eklenecek`n`n-> $($r.Cells['Onerilen'].Value)`n`nEklensin mi?"
    if ([Windows.Forms.MessageBox]::Show($q, 'HTTPS binding ekle', 'YesNo', 'Question') -ne 'Yes') { return }
    Add-HttpsBinding $r.Cells['Site'].Value $ip $r.Cells['AlanAdi'].Value $r.Cells['Oneri'].Value; Refresh-All
})
[void]$ctxB.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $ctxB 'Bu binding''i canlı sorgula' {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'https') { throw 'Yalnızca https binding sorgulanır.' }
    $got = Probe-Ssl $r.Cells['Binding'].Value
    $r.Cells['Canli'].Value = if ($got -eq $r.Cells['Thumbprint'].Value) { 'OK, aynı sertifika' } elseif ($got -match '^[0-9A-F]{40}$') { "FARKLI: $($got.Substring(0,8))..." } else { $got }
    Write-Log "CANLI  $($r.Cells['Site'].Value) [$($r.Cells['Binding'].Value)]  $($r.Cells['Canli'].Value)"
})
[void](Add-MenuItem $ctxB 'Sertifikayı alt listede göster' { $t = (Selected-Domain).Cells['Thumbprint'].Value; if (-not $t) { throw 'Bu binding''de sertifika yok.' }; Select-Cert $t })
[void](Add-MenuItem $ctxB 'Alan adını kopyala' { [Windows.Forms.Clipboard]::SetText("$((Selected-Domain).Cells['AlanAdi'].Value)") })
$gridB.ContextMenuStrip = $ctxB
$lblLog = New-Object Windows.Forms.Label; $lblLog.Text = "Kayıt ($logFile)"; $lblLog.Dock = 'Bottom'; $lblLog.Height = 18

$form.Controls.AddRange(@($split, $bar, $load, $menu, $lblLog, $logBox, $status))
$form.Add_Shown({ try { $split.SplitterDistance = [int]($split.Height * 0.5); Write-Log "BAŞLADI  $appName $appVersion  $env:USERNAME@$env:COMPUTERNAME"; Refresh-All } catch { Show-Error $_.Exception.Message } })
[void]$form.ShowDialog()
