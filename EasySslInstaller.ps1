#Requires -Version 5.1
# Easy SSL Installer for IIS - tek dosya PowerShell/WinForms uygulaması
# https://github.com/softviser/easy-ssl-installer-iis
# Yapar: https binding'leri ve LocalMachine\My sertifikalarını listeler; PFX, PEM bundle (crt + key + ca-bundle)
#        veya sertifika sağlayıcısından gelen ZIP'i yükler; yükleme sonrası alan adı uyan binding'lere atamayı önerir;
#        seçili binding'lere sertifika atar, kullanılmayan sertifikayı siler.
#        Her işlem ekrandaki kayıt paneline ve uygulamanın yanındaki EasySslInstaller.log dosyasına yazılır.
#        Arayüz dili açılışta seçilir: İngilizce (varsayılan) veya Türkçe; tüm metinler $Lang sözlüğünde.
$ErrorActionPreference = 'Stop'
$appName = 'Easy SSL Installer for IIS'; $appVersion = '1.4.0'
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
$ico = Join-Path (Split-Path $selfPath) 'EasySslInstaller.ico'
$appIcon = if (-not $PSCommandPath) { [Drawing.Icon]::ExtractAssociatedIcon($selfPath) } elseif (Test-Path $ico) { New-Object Drawing.Icon $ico }

# ---------- metinler ----------
$Lang = @{
    en = @{
        noIis       = 'WebAdministration module not found. Is IIS installed on this machine?'
        col         = @{ Konu = 'Subject'; Durum = 'State'; AlanAdi = 'Host name'; Protokol = 'Prot.'; Sertifika = 'Certificate'; SSL = 'SSL status'
                         Onerilen = 'Suggested certificate'; Canli = 'Live check'; Bitis = 'Expires'; Kalan = 'Days'; Anahtar = 'Key' }
        keyYes      = 'yes'; keyNo = 'NONE'; yes = 'yes'; running = 'running'
        stNoHttps   = 'no HTTPS'; stNoCert = 'no certificate'; stExpired = 'expired'; stMismatch = 'host name mismatch'; stDays = '{0} days left'; stOk = 'valid'
        noConn      = 'no connection'; err = 'error: {0}'; liveSame = 'OK, same certificate'; liveDiff = 'DIFFERENT: {0}...'
        logError    = 'ERROR'; logLive = 'LIVE'; logLiveDone = '{0} bindings checked'; logAssign = 'ASSIGN'; logImport = 'IMPORT'; logConvert = 'CONVERT'
        logAuto     = 'AUTO ASSIGN'; logDelete = 'DELETE'; logList = 'LIST'; logStart = 'STARTED'
        bindExists  = 'Binding {1} already exists on {0}.'; logBinding = 'BINDING  {0}  https {1} added (SNI)'
        expires     = 'expires'; withKey = '(with private key)'
        mergeFail   = "certutil -MergePFX failed (the key may be encrypted or may not match the certificate):`n{0}"
        zipNoLeaf   = 'No server certificate (PEM) or PFX found in the ZIP.'
        zipNoKey    = "The ZIP has no private key. Put the key file in the 'Key (.key)' field and try again."
        autoNone    = 'no matching binding'; cancelled = 'cancelled by user'; autoNow = '  (now: {0}, expires {1})'; autoNoCert = '  (no certificate)'
        autoQ       = "The new certificate matches these bindings:`n`n{0}`n`n-> {1}`n   expires {2}`n`nAssign it to all of them?"; autoTitle = 'Automatic assignment'
        browse      = 'Browse...'; all = 'All'; ok = 'OK'; confirm = 'Confirm'
        selCert     = 'Select a certificate in the lower list.'; selRow = 'Select a row in the upper list.'
        aboutTitle  = 'About'; version = 'Version {0}  -  MIT license, open source'
        aboutDesc   = 'Installs SSL certificates into IIS and updates https bindings. Supports PFX, PEM bundles (crt + key + ca-bundle) and provider ZIP files.'
        mFile       = 'File'; mHelp = 'Help'; refresh = 'Refresh'; openLog = 'Open log file'; noLog = 'No log file yet.'
        openStore   = 'Open certificate store (certlm.msc)'; exit = 'Exit'; github = 'GitHub page'
        loadTitle   = 'Import certificate (PFX, PEM files or the ZIP from your provider; you can drag and drop files)'
        pfxFile     = 'PFX file:'; password = 'Password:'; btnPfx = 'Import PFX'; selPfx = 'Select a PFX file.'
        tipPfx      = 'Imports the PFX/P12 file with its private key into the LocalMachine\My store'
        crtFile     = 'Certificate (.crt):'; fltCrt = 'Certificate'; keyFile = 'Key (.key):'; fltKey = 'Key'; caFile = 'CA bundle (opt.):'
        btnPem      = 'Import PEM bundle'; selPem = 'Select the certificate (.crt) and key (.key) files.'
        tipPem      = 'Converts crt + key to PFX with certutil and imports it; the CA bundle goes to the Intermediate CA store'
        zipFile     = 'ZIP bundle:'; btnZip = 'Import ZIP'; selZip = 'Select a ZIP file.'
        tipZip      = 'Opens the ZIP from your provider: imports the PFX inside (with the password field) or finds the crt + key + CA files itself. If the ZIP has no key, the Key (.key) field is used'
        lblB        = 'IIS sites and host names (http + https)   green: valid, yellow: under 30 days, red: problem, gray: no HTTPS   right-click: apply suggestion / add HTTPS'
        lblC        = 'Certificates (LocalMachine\My)   yellow: under 30 days left, red: expired   right-click: copy / delete'
        summary     = '{0} sites, {1} host names, {2} HTTPS bindings ({3} with problems), {4} host names without HTTPS, {5} certificates'
        copyThumb   = 'Copy thumbprint'; copySubject = 'Copy subject'; delCert = 'Delete certificate...'
        certInUse   = 'This certificate is used by {0} binding(s). Assign another certificate to them first.'
        delQ        = "{0}`n{1}`n`nThe certificate and its private key will be removed from the store; this cannot be undone. Delete?"; delTitle = 'Delete certificate'
        btnRefresh  = 'Refresh (F5)'; btnAssign = 'Assign selected certificate to selected bindings'
        selHttps    = 'Select at least one https row in the upper list (right-click an http row: add HTTPS binding).'
        noKey       = 'This certificate has no private key; it cannot be assigned to a binding.'
        assignQ     = "{0}`n`n-> {1}`n   expires {2} ({3} days)`n`nAssign?"
        tipAssign   = 'For a renewal: select every binding that uses the old certificate, select the new one below, assign'
        btnProbe    = 'Live SSL check'
        tipProbe    = 'Connects to each https binding from this machine and writes whether the served certificate matches the one in IIS to the "Live check" column'
        btnApplyAll = 'Apply all suggestions'; noSuggest = 'No https binding has a suggested certificate.'
        applyAllQ   = "{0}`n`nAssign all?"; applyAllTitle = 'Apply suggestions'
        tipApplyAll = 'Assigns the longest-lived certificate matching the host name (Suggested column) to every https binding'
        filter      = 'Filter:'; tipFilter = 'Filters the upper list by site, host name, certificate or SSL status'
        assignOne   = 'Assign suggested certificate to this binding'; isHttp = "This is an http binding; use 'Add HTTPS binding'."
        noMatch     = 'No suitable certificate in the store for this host name. Import the certificate first.'
        assignOneQ  = "{0} [{1}]`n`n-> {2}`n`nAssign?"
        addHttps    = 'Add HTTPS binding (with suggested certificate)...'; alreadyHttps = 'This row is already https.'
        noHost      = 'HTTPS is not added for a binding without a host name; add it in IIS by hand.'
        addQ        = "Binding {1}:443:{2} (SNI) will be added to site {0}`n`n-> {3}`n`nAdd?"; addTitle = 'Add HTTPS binding'
        probeOne    = 'Live check this binding'; httpsOnly = 'Only https bindings can be checked.'
        showCert    = 'Show certificate in lower list'; noCertHere = 'This binding has no certificate.'; copyHost = 'Copy host name'
        lblLog      = 'Log ({0})'
    }
    tr = @{
        noIis       = 'WebAdministration modülü yok. Bu makinede IIS kurulu mu?'
        col         = @{ Konu = 'Konu'; Durum = 'Durum'; AlanAdi = 'Alan adı'; Protokol = 'Prot.'; Sertifika = 'Sertifika'; SSL = 'SSL durumu'
                         Onerilen = 'Önerilen sertifika'; Canli = 'Canlı sorgu'; Bitis = 'Bitiş'; Kalan = 'Gün'; Anahtar = 'Anahtar' }
        keyYes      = 'var'; keyNo = 'YOK'; yes = 'evet'; running = 'çalışıyor'
        stNoHttps   = 'HTTPS yok'; stNoCert = 'Sertifika yok'; stExpired = 'Süresi dolmuş'; stMismatch = 'Alan adı uyuşmuyor'; stDays = '{0} gün kaldı'; stOk = 'Geçerli'
        noConn      = 'bağlantı yok'; err = 'hata: {0}'; liveSame = 'OK, aynı sertifika'; liveDiff = 'FARKLI: {0}...'
        logError    = 'HATA'; logLive = 'CANLI'; logLiveDone = '{0} binding sorgulandı'; logAssign = 'ATAMA'; logImport = 'YÜKLEME'; logConvert = 'DÖNÜŞÜM'
        logAuto     = 'OTOMATİK ATAMA'; logDelete = 'SİLME'; logList = 'LİSTE'; logStart = 'BAŞLADI'
        bindExists  = "{0} için {1} binding'i zaten var."; logBinding = 'BINDING  {0}  https {1} eklendi (SNI)'
        expires     = 'bitiş'; withKey = '(özel anahtarla birlikte)'
        mergeFail   = "certutil -MergePFX başarısız (anahtar şifreli veya sertifikayla eşleşmiyor olabilir):`n{0}"
        zipNoLeaf   = 'ZIP içinde sunucu sertifikası (PEM) veya PFX bulunamadı.'
        zipNoKey    = "ZIP içinde özel anahtar yok. 'Anahtar (.key)' alanına anahtar dosyasını verip tekrar deneyin."
        autoNone    = 'uyan binding yok'; cancelled = 'kullanıcı iptal etti'; autoNow = '  (şu an: {0}, bitiş {1})'; autoNoCert = '  (sertifikasız)'
        autoQ       = "Yeni sertifika şu binding'lere uyuyor:`n`n{0}`n`n-> {1}`n   bitiş {2}`n`nHepsine atansın mı?"; autoTitle = 'Otomatik atama'
        browse      = 'Gözat...'; all = 'Tümü'; ok = 'Tamam'; confirm = 'Onay'
        selCert     = 'Alt listeden bir sertifika seçin.'; selRow = 'Üst listeden bir satır seçin.'
        aboutTitle  = 'Hakkında'; version = 'Sürüm {0}  -  MIT lisansı, açık kaynak'
        aboutDesc   = "IIS için SSL sertifikası yükleme ve binding güncelleme aracı. PFX, PEM bundle (crt + key + ca-bundle) ve sağlayıcı ZIP'i destekler."
        mFile       = 'Dosya'; mHelp = 'Yardım'; refresh = 'Yenile'; openLog = 'Kayıt dosyasını aç'; noLog = 'Henüz kayıt dosyası oluşmadı.'
        openStore   = 'Sertifika deposunu aç (certlm.msc)'; exit = 'Çıkış'; github = 'GitHub sayfası'
        loadTitle   = 'Sertifika yükle (PFX, PEM dosyaları veya sağlayıcıdan gelen ZIP; dosyaları sürükleyip bırakabilirsiniz)'
        pfxFile     = 'PFX dosyası:'; password = 'Şifre:'; btnPfx = 'PFX Yükle'; selPfx = 'PFX dosyası seçin.'
        tipPfx      = 'PFX/P12 dosyasını özel anahtarıyla birlikte LocalMachine\My deposuna alır'
        crtFile     = 'Sertifika (.crt):'; fltCrt = 'Sertifika'; keyFile = 'Anahtar (.key):'; fltKey = 'Anahtar'; caFile = 'CA bundle (ops.):'
        btnPem      = 'PEM Bundle Yükle'; selPem = 'Sertifika (.crt) ve anahtar (.key) dosyalarını seçin.'
        tipPem      = "crt + key dosyasını certutil ile PFX'e çevirip yükler; CA bundle Intermediate CA deposuna gider"
        zipFile     = 'ZIP bundle:'; btnZip = 'ZIP Yükle'; selZip = 'ZIP dosyası seçin.'
        tipZip      = "Sağlayıcının gönderdiği ZIP'i açar: içindeki PFX'i (şifre alanıyla) ya da crt + key + CA dosyalarını kendisi bulup yükler. ZIP'te anahtar yoksa Anahtar (.key) alanı kullanılır"
        lblB        = 'IIS siteleri ve alan adları (http + https)   yeşil: geçerli, sarı: 30 günden az, kırmızı: sorun, gri: HTTPS yok   sağ tık: öneriyi uygula / HTTPS ekle'
        lblC        = 'Sertifikalar (LocalMachine\My)   sarı: 30 günden az kaldı, kırmızı: süresi doldu   sağ tık: kopyala / sil'
        summary     = '{0} site, {1} alan adı, {2} HTTPS binding ({3} sorunlu), {4} alan adında HTTPS yok, {5} sertifika'
        copyThumb   = "Thumbprint'i kopyala"; copySubject = 'Konuyu kopyala'; delCert = 'Sertifikayı sil...'
        certInUse   = "Bu sertifika {0} binding'de kullanılıyor. Önce o binding'lere başka sertifika atayın."
        delQ        = "{0}`n{1}`n`nSertifika ve özel anahtarı depodan silinecek, geri alınamaz. Silinsin mi?"; delTitle = 'Sertifikayı sil'
        btnRefresh  = 'Yenile (F5)'; btnAssign = "Seçili binding'lere seçili sertifikayı ata"
        selHttps    = 'Üst listeden en az bir https satırı seçin (http satırlarına sağ tık: HTTPS binding ekle).'
        noKey       = "Bu sertifikanın özel anahtarı yok, binding'e atanamaz."
        assignQ     = "{0}`n`n-> {1}`n   bitiş {2} ({3} gün)`n`nAtansın mı?"
        tipAssign   = "Yenilemede: eski sertifikaya bağlı tüm binding'leri seçin, alttan yeni sertifikayı seçin, atayın"
        btnProbe    = "SSL'i canlı sorgula"
        tipProbe    = "Her https binding'e bu makineden bağlanır ve sunulan sertifikanın IIS'teki ile aynı olup olmadığını `"Canlı sorgu`" sütununa yazar"
        btnApplyAll = 'Tüm önerileri uygula'; noSuggest = 'Önerilen sertifikası olan https binding yok.'
        applyAllQ   = "{0}`n`nHepsi atansın mı?"; applyAllTitle = 'Önerileri uygula'
        tipApplyAll = "Her https binding'e, alan adına uyan en uzun ömürlü sertifikayı (Önerilen sütunu) atar"
        filter      = 'Süz:'; tipFilter = 'Site, alan adı, sertifika veya SSL durumuna göre üst listeyi süzer'
        assignOne   = "Önerilen sertifikayı bu binding'e ata"; isHttp = "Bu bir http binding'i; 'HTTPS binding ekle' seçeneğini kullanın."
        noMatch     = 'Bu alan adı için depoda uygun sertifika yok. Önce sertifikayı yükleyin.'
        assignOneQ  = "{0} [{1}]`n`n-> {2}`n`nAtansın mı?"
        addHttps    = 'HTTPS binding ekle (önerilen sertifikayla)...'; alreadyHttps = 'Bu satır zaten https.'
        noHost      = "Alan adı olmayan binding için HTTPS eklenmez; IIS'te elle ekleyin."
        addQ        = "{0} sitesine {1}:443:{2} (SNI) binding'i eklenecek`n`n-> {3}`n`nEklensin mi?"; addTitle = 'HTTPS binding ekle'
        probeOne    = "Bu binding'i canlı sorgula"; httpsOnly = 'Yalnızca https binding sorgulanır.'
        showCert    = 'Sertifikayı alt listede göster'; noCertHere = "Bu binding'de sertifika yok."; copyHost = 'Alan adını kopyala'
        lblLog      = 'Kayıt ({0})'
    }
}
# Açılışta dil seçimi; Enter veya pencereyi kapatmak İngilizce demektir.
function Choose-Language {
    $f = New-Object Windows.Forms.Form; $f.Text = "$appName - Language / Dil"; $f.ClientSize = '300,90'; $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; if ($appIcon) { $f.Icon = $appIcon }
    $l = New-Object Windows.Forms.Label; $l.Text = 'Select language / Dil seçin'; $l.Location = '20,15'; $l.AutoSize = $true
    $en = New-Object Windows.Forms.Button; $en.Text = 'English'; $en.Location = '20,45'; $en.Size = '120,30'; $en.DialogResult = 'OK'
    $tr = New-Object Windows.Forms.Button; $tr.Text = 'Türkçe'; $tr.Location = '160,45'; $tr.Size = '120,30'; $tr.DialogResult = 'Yes'
    $f.Controls.AddRange(@($l, $en, $tr)); $f.AcceptButton = $en
    if ($f.ShowDialog() -eq 'Yes') { 'tr' } else { 'en' }
}
$UI = $Lang[(Choose-Language)]

try { Import-Module WebAdministration } catch {
    [Windows.Forms.MessageBox]::Show($UI.noIis, $appName) | Out-Null; exit 1
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
function Show-Error($msg) { Write-Log "$($UI.logError)  $msg"; [Windows.Forms.MessageBox]::Show($msg, $appName, 'OK', 'Error') | Out-Null }
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
            Anahtar    = if ($_.HasPrivateKey) { $UI.keyYes } else { $UI.keyNo }
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
            $status = if (-not $https) { $UI.stNoHttps }
                      elseif (-not $c) { $UI.stNoCert }
                      elseif ($days -lt 0) { $UI.stExpired }
                      elseif ($h -and -not (Match-Host (Cert-Names $c) $h)) { $UI.stMismatch }
                      elseif ($days -lt 30) { $UI.stDays -f $days }
                      else { $UI.stOk }
            $best = Best-Cert $certs $h
            if ($best -and $c -and $best.Thumbprint -eq $c.Thumbprint) { $best = $null }   # zaten takılı olanı önerme
            [pscustomobject]@{
                Site       = $s.Name
                Durum      = if ($s.State -eq 'Started') { $UI.running } else { "$($s.State)".ToLower() }
                AlanAdi    = $h
                Protokol   = $b.protocol
                Binding    = $b.bindingInformation
                SNI        = if ($https -and ($b.sslFlags -band 1)) { $UI.yes } else { '' }
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
        if (-not $tcp.ConnectAsync($target, [int]$port).Wait(3000)) { return $UI.noConn }
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($(if ($h) { $h } else { $target }), $null, [Security.Authentication.SslProtocols]'Tls12, Tls11, Tls', $false)
        (New-Object Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate).Thumbprint
    } catch { $UI.err -f $_.Exception.GetBaseException().Message } finally { $tcp.Close() }
}
function Probe-Row($r) {
    $got = Probe-Ssl $r.Cells['Binding'].Value
    $r.Cells['Canli'].Value = if ($got -eq $r.Cells['Thumbprint'].Value) { $UI.liveSame } elseif ($got -match '^[0-9A-F]{40}$') { $UI.liveDiff -f $got.Substring(0, 8) } else { $got }
    Write-Log "$($UI.logLive)  $($r.Cells['Site'].Value) [$($r.Cells['Binding'].Value)]  $($r.Cells['Canli'].Value)"
}
function Probe-All {
    $form.Cursor = 'WaitCursor'
    try {
        $n = 0
        foreach ($r in $gridB.Rows) { if ($r.Cells['Protokol'].Value -eq 'https') { Probe-Row $r; $n++ } }
        Write-Log "$($UI.logLive)  $($UI.logLiveDone -f $n)"
    } finally { $form.Cursor = 'Default' }
}

# http binding'i olan alan adına https binding açıp sertifikayı takar.
function Add-HttpsBinding($site, $ip, $h, $thumb) {
    $info = "$($ip):443:$h"
    if (Get-WebBinding -Name $site -Protocol https | Where-Object bindingInformation -eq $info) { throw ($UI.bindExists -f $site, $info) }
    $p = @{ Name = $site; Protocol = 'https'; Port = 443; HostHeader = $h; SslFlags = 1 }
    if ($ip -and $ip -ne '*') { $p.IPAddress = $ip }
    New-WebBinding @p
    Write-Log ($UI.logBinding -f $site, $info)
    Set-BindingCert $site $info '' $thumb
}

function Set-BindingCert($site, $bindingInfo, $oldThumb, $thumb) {
    $b = Get-WebBinding -Name $site -Protocol https | Where-Object bindingInformation -eq $bindingInfo
    try { $b.RemoveSslCertificate() } catch { }   # boş binding'de hata verir, önemsiz
    $b.AddSslCertificate($thumb, 'My')
    Write-Log "$($UI.logAssign)  $site [$bindingInfo]  $oldThumb -> $thumb"
}

function Import-Pfx($path, $pass) {
    $sec = if ($pass) { ConvertTo-SecureString $pass -AsPlainText -Force } else { New-Object Security.SecureString }
    $c = Import-PfxCertificate -FilePath $path -CertStoreLocation Cert:\LocalMachine\My -Password $sec -Exportable
    Write-Log "$($UI.logImport)  $path -> LocalMachine\My  $($c.Subject)  $($c.Thumbprint)  $($UI.expires) $($c.NotAfter.ToString('yyyy-MM-dd'))"
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
        if ($LASTEXITCODE) { throw ($UI.mergeFail -f "$out") }
        Write-Log "$($UI.logConvert)  $crt + $key -> PFX"
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
        if (-not $leaf) { throw $UI.zipNoLeaf }
        if (-not $key) { throw $UI.zipNoKey }
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
    if (-not $hits) { Write-Log "$($UI.logAuto)  $($UI.autoNone)"; return }
    $lines = $hits | ForEach-Object { "$($_.Site) [$($_.Binding)]" + $(if ($_.Sertifika) { $UI.autoNow -f $_.Sertifika, $_.Bitis } else { $UI.autoNoCert }) }
    $q = $UI.autoQ -f ($lines -join "`n"), $cert.Subject, $cert.NotAfter.ToString('yyyy-MM-dd')
    if ([Windows.Forms.MessageBox]::Show($q, $UI.autoTitle, 'YesNo', 'Question') -ne 'Yes') { Write-Log "$($UI.logAuto)  $($UI.cancelled)"; return }
    foreach ($r in $hits) { Set-BindingCert $r.Site $r.Binding $r.Thumbprint $cert.Thumbprint }
    Refresh-All
}

function Remove-Cert($thumb, $subject) {
    Remove-Item "Cert:\LocalMachine\My\$thumb" -DeleteKey
    Write-Log "$($UI.logDelete)  $subject  $thumb  $($UI.withKey)"
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
        if ($UI.col[$c.Name]) { $c.HeaderText = $UI.col[$c.Name] }
        switch ($c.Name) {
            'Konu'       { $c.FillWeight = 180 }
            'SAN'        { $c.FillWeight = 150 }
            'Site'       { $c.FillWeight = 110 }
            'Durum'      { $c.FillWeight = 55 }
            'AlanAdi'    { $c.FillWeight = 120 }
            'Protokol'   { $c.FillWeight = 45 }
            'Binding'    { $c.FillWeight = 100 }
            'Sertifika'  { $c.FillWeight = 120 }
            'SSL'        { $c.FillWeight = 95 }
            'Onerilen'   { $c.FillWeight = 130 }
            'Canli'      { $c.FillWeight = 110 }
            'Thumbprint' { $c.FillWeight = 120 }
            'Oneri'      { $c.Visible = $false }
            'Bitis'      { $c.FillWeight = 60 }
            'Kalan'      { $c.FillWeight = 40; $c.DefaultCellStyle.Alignment = 'MiddleRight' }
            'SNI'        { $c.FillWeight = 35 }
            'Anahtar'    { $c.FillWeight = 50 }
        }
    }
}
function Color-Status($g) {
    foreach ($r in $g.Rows) {
        $cell = $r.Cells['SSL']; $s = "$($cell.Value)"
        $cell.Style.BackColor = if ($s -eq $UI.stOk) { 'Honeydew' } elseif ($s -eq $UI.stNoHttps) { 'WhiteSmoke' } elseif ($s -like ($UI.stDays -f '*')) { 'LemonChiffon' } else { 'MistyRose' }
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
    $g = New-Button $UI.browse 648 ($y - 1) 70 { $d = New-Object Windows.Forms.OpenFileDialog; $d.Filter = "$filter|$($UI.all)|*.*"; if ($d.ShowDialog() -eq 'OK') { $t.Text = $d.FileName } }.GetNewClosure()
    $g.Anchor = 'Top,Right'
    $panel.Controls.AddRange(@($l, $t, $g)); $t
}
function Selected-Cert {
    if ($gridC.SelectedRows.Count -ne 1) { throw $UI.selCert }
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
    $f = New-Object Windows.Forms.Form; $f.Text = $UI.aboutTitle; $f.ClientSize = '420,260'; $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false; $f.Icon = $form.Icon
    $pic = New-Object Windows.Forms.PictureBox; $pic.Location = '20,20'; $pic.Size = '48,48'; $pic.SizeMode = 'StretchImage'
    if ($form.Icon) { $pic.Image = (New-Object Drawing.Icon $form.Icon, 48, 48).ToBitmap() }
    $t = New-Object Windows.Forms.Label; $t.Text = $appName; $t.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold); $t.Location = '80,18'; $t.AutoSize = $true
    $v = New-Object Windows.Forms.Label; $v.Text = $UI.version -f $appVersion; $v.Location = '82,50'; $v.AutoSize = $true
    $d = New-Object Windows.Forms.Label; $d.Location = '20,85'; $d.Size = '380,40'; $d.Text = $UI.aboutDesc
    $en = New-Object Windows.Forms.Label; $en.Location = '20,128'; $en.Size = '380,32'; $en.ForeColor = 'DimGray'
    $en.Text = "Open source software released under the MIT License.`nDeveloped by Softviser Yazılım, Turkey."
    $by = New-Object Windows.Forms.Label; $by.Text = 'Softviser Yazılım'; $by.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold); $by.Location = '20,165'; $by.AutoSize = $true
    $l1 = New-Object Windows.Forms.LinkLabel; $l1.Text = 'www.softviser.com.tr'; $l1.Location = '20,185'; $l1.AutoSize = $true; $l1.Tag = $siteUrl
    $l2 = New-Object Windows.Forms.LinkLabel; $l2.Text = 'github.com/softviser/easy-ssl-installer-iis'; $l2.Location = '20,205'; $l2.AutoSize = $true; $l2.Tag = $repoUrl
    foreach ($l in $l1, $l2) { $l.Add_LinkClicked({ Start-Process $this.Tag }) }
    $ok = New-Object Windows.Forms.Button; $ok.Text = $UI.ok; $ok.Location = '320,222'; $ok.Size = '80,26'; $ok.DialogResult = 'OK'
    $f.Controls.AddRange(@($pic, $t, $v, $d, $en, $by, $l1, $l2, $ok)); $f.AcceptButton = $ok; $f.CancelButton = $ok
    [void]$f.ShowDialog($form)
}

# ---------- form ----------
$form = New-Object Windows.Forms.Form
$form.Text = "$appName - $env:COMPUTERNAME"; $form.Size = '1180,900'; $form.StartPosition = 'CenterScreen'; $form.MinimumSize = '960,640'
if ($appIcon) { $form.Icon = $appIcon }
$tip = New-Object Windows.Forms.ToolTip

# menü
$menu = New-Object Windows.Forms.MenuStrip
$mFile = $menu.Items.Add($UI.mFile); $mHelp = $menu.Items.Add($UI.mHelp)
[void](Add-MenuItem $mFile $UI.refresh { Refresh-All } ([Windows.Forms.Keys]::F5))
[void](Add-MenuItem $mFile $UI.openLog { if (Test-Path $logFile) { Start-Process notepad $logFile } else { throw $UI.noLog } })
[void](Add-MenuItem $mFile $UI.openStore { Start-Process certlm.msc })
[void]$mFile.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $mFile $UI.exit { $form.Close() })
[void](Add-MenuItem $mHelp $UI.github { Start-Process $repoUrl })
[void](Add-MenuItem $mHelp 'Softviser Yazılım' { Start-Process $siteUrl })
[void]$mHelp.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $mHelp $UI.aboutTitle { Show-About })
$form.MainMenuStrip = $menu

# yükleme paneli
$load = New-Object Windows.Forms.GroupBox; $load.Text = $UI.loadTitle; $load.Dock = 'Top'
$load.Size = "$($form.ClientSize.Width),180"   # anchor'lar doğru hesaplansın diye çocuklardan önce genişlik verilir
$txtPfx = Add-FileRow $load 22  $UI.pfxFile 'PFX|*.pfx;*.p12'
$txtPw  = New-Object Windows.Forms.TextBox; $txtPw.UseSystemPasswordChar = $true; $txtPw.Location = '790,22'; $txtPw.Width = 90; $txtPw.Anchor = 'Top,Right'
$lblPw  = New-Object Windows.Forms.Label; $lblPw.Text = $UI.password; $lblPw.Location = '730,26'; $lblPw.Width = 60; $lblPw.Anchor = 'Top,Right'
$btnPfx = New-Button $UI.btnPfx 886 21 95 {
    if (-not $txtPfx.Text) { throw $UI.selPfx }
    $c = Import-Pfx $txtPfx.Text $txtPw.Text; After-Import $c @($txtPfx, $txtPw)
}
$btnPfx.Anchor = 'Top,Right'; $tip.SetToolTip($btnPfx, $UI.tipPfx)
$txtCrt = Add-FileRow $load 55  $UI.crtFile "$($UI.fltCrt)|*.crt;*.cer;*.pem"
$txtKey = Add-FileRow $load 85  $UI.keyFile "$($UI.fltKey)|*.key;*.pem"
$txtCa  = Add-FileRow $load 115 $UI.caFile 'CA bundle|*.ca-bundle;*.crt;*.cer;*.pem'
$btnPem = New-Button $UI.btnPem 745 114 236 {
    if (-not $txtCrt.Text -or -not $txtKey.Text) { throw $UI.selPem }
    $c = Import-PemBundle $txtCrt.Text $txtKey.Text $txtCa.Text; After-Import $c @($txtCrt, $txtKey, $txtCa)
}
$btnPem.Anchor = 'Top,Right'; $tip.SetToolTip($btnPem, $UI.tipPem)
$txtZip = Add-FileRow $load 145 $UI.zipFile 'ZIP|*.zip'
$btnZip = New-Button $UI.btnZip 745 144 236 {
    if (-not $txtZip.Text) { throw $UI.selZip }
    $c = Import-Zip $txtZip.Text $txtPw.Text $txtKey.Text; After-Import $c @($txtZip, $txtPw, $txtKey)
}
$btnZip.Anchor = 'Top,Right'; $tip.SetToolTip($btnZip, $UI.tipZip)
$load.Controls.AddRange(@($lblPw, $txtPw, $btnPfx, $btnPem, $btnZip))

# listeler
$split = New-Object Windows.Forms.SplitContainer; $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'
$lblB = New-Object Windows.Forms.Label; $lblB.Text = $UI.lblB; $lblB.Dock = 'Top'; $lblB.Height = 18
$lblC = New-Object Windows.Forms.Label; $lblC.Text = $UI.lblC; $lblC.Dock = 'Top'; $lblC.Height = 18
$gridB = New-Grid; $gridC = New-Grid; $gridC.MultiSelect = $false
$split.Panel1.Controls.AddRange(@($gridB, $lblB)); $split.Panel2.Controls.AddRange(@($gridC, $lblC))
$status = New-Object Windows.Forms.StatusStrip; $stLbl = New-Object Windows.Forms.ToolStripStatusLabel; $stLbl.Spring = $true; $stLbl.TextAlign = 'MiddleLeft'
$stLink = New-Object Windows.Forms.ToolStripStatusLabel 'Softviser Yazılım - www.softviser.com.tr'; $stLink.IsLink = $true; $stLink.Add_Click({ Start-Process $siteUrl })
[void]$status.Items.AddRange(@($stLbl, $stLink))

function Refresh-All {
    $rows = @(Get-Domains)
    $gridB.DataSource = ConvertTo-Table $rows; Fit-Columns $gridB; Apply-Filter
    $gridC.DataSource = ConvertTo-Table (Get-Certs); Fit-Columns $gridC; Color-Expiry $gridC
    $https = @($rows | Where-Object Protokol -eq 'https'); $bad = @($https | Where-Object { $_.SSL -ne $UI.stOk })
    $httpsHosts = @($https | ForEach-Object AlanAdi); $noSsl = @($rows | Where-Object { $_.Protokol -eq 'http' -and $_.AlanAdi -and $_.AlanAdi -notin $httpsHosts })
    $stLbl.Text = $UI.summary -f @($rows | Select-Object -ExpandProperty Site -Unique).Count, @($rows | Where-Object AlanAdi | Select-Object -ExpandProperty AlanAdi -Unique).Count, $https.Count, $bad.Count, $noSsl.Count, $gridC.Rows.Count
    Write-Log "$($UI.logList)  $($stLbl.Text)"
}
function Apply-Filter {
    $t = $gridB.DataSource; if (-not $t) { return }
    $q = $txtFilter.Text.Replace("'", "''").Replace('[', '[[]').Replace('%', '[%]')
    $t.DefaultView.RowFilter = if ($q) { "Site LIKE '%$q%' OR AlanAdi LIKE '%$q%' OR Sertifika LIKE '%$q%' OR SSL LIKE '%$q%'" } else { '' }
    Color-Expiry $gridB; Color-Status $gridB   # süzgeç satırları yeniden kurar, renkler burada verilir
}
function Selected-Domain {
    if ($gridB.SelectedRows.Count -ne 1) { throw $UI.selRow }
    $gridB.SelectedRows[0]
}

# sertifika sağ tık menüsü
$ctx = New-Object Windows.Forms.ContextMenuStrip
[void](Add-MenuItem $ctx $UI.copyThumb { [Windows.Forms.Clipboard]::SetText((Selected-Cert).Cells['Thumbprint'].Value) })
[void](Add-MenuItem $ctx $UI.copySubject { [Windows.Forms.Clipboard]::SetText((Selected-Cert).Cells['Konu'].Value) })
[void]$ctx.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $ctx $UI.delCert {
    $row = Selected-Cert; $thumb = $row.Cells['Thumbprint'].Value; $subject = $row.Cells['Konu'].Value
    $used = @($gridB.Rows | Where-Object { $_.Cells['Thumbprint'].Value -eq $thumb })
    if ($used) { throw ($UI.certInUse -f $used.Count) }
    if ([Windows.Forms.MessageBox]::Show(($UI.delQ -f $subject, $thumb), $UI.delTitle, 'YesNo', 'Warning', 'Button2') -ne 'Yes') { return }
    Remove-Cert $thumb $subject; Refresh-All
})
$gridC.ContextMenuStrip = $ctx

# işlem çubuğu
$bar = New-Object Windows.Forms.Panel; $bar.Dock = 'Top'; $bar.Height = 34
$bar.Controls.Add((New-Button $UI.btnRefresh 10 5 90 { Refresh-All }))
$btnAssign = New-Button $UI.btnAssign 110 5 280 {
    $sel = @($gridB.SelectedRows | Where-Object { $_.Cells['Protokol'].Value -eq 'https' })
    if (-not $sel) { throw $UI.selHttps }
    $cert = Selected-Cert
    if ($cert.Cells['Anahtar'].Value -ne $UI.keyYes) { throw $UI.noKey }
    $targets = @($sel | ForEach-Object { "$($_.Cells['Site'].Value) [$($_.Cells['Binding'].Value)]" })
    $q = $UI.assignQ -f ($targets -join "`n"), $cert.Cells['Konu'].Value, $cert.Cells['Bitis'].Value, $cert.Cells['Kalan'].Value
    if ([Windows.Forms.MessageBox]::Show($q, $UI.confirm, 'YesNo', 'Question') -ne 'Yes') { Write-Log "$($UI.logAssign)  $($UI.cancelled)"; return }
    foreach ($r in $sel) { Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $cert.Cells['Thumbprint'].Value }
    Refresh-All
}
$tip.SetToolTip($btnAssign, $UI.tipAssign)
$bar.Controls.Add($btnAssign)
$btnProbe = New-Button $UI.btnProbe 400 5 130 { Probe-All }
$tip.SetToolTip($btnProbe, $UI.tipProbe)
$bar.Controls.Add($btnProbe)
$btnApplyAll = New-Button $UI.btnApplyAll 540 5 140 {
    $rows = @($gridB.Rows | Where-Object { $_.Cells['Oneri'].Value -and $_.Cells['Protokol'].Value -eq 'https' })
    if (-not $rows) { throw $UI.noSuggest }
    $q = ($rows | ForEach-Object { "$($_.Cells['Site'].Value) [$($_.Cells['Binding'].Value)]  ->  $($_.Cells['Onerilen'].Value)" }) -join "`n"
    if ([Windows.Forms.MessageBox]::Show(($UI.applyAllQ -f $q), $UI.applyAllTitle, 'YesNo', 'Question') -ne 'Yes') { Write-Log "$($UI.logAssign)  $($UI.cancelled)"; return }
    foreach ($r in $rows) { Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $r.Cells['Oneri'].Value }
    Refresh-All
}
$tip.SetToolTip($btnApplyAll, $UI.tipApplyAll)
$bar.Controls.Add($btnApplyAll)
$lblFilter = New-Object Windows.Forms.Label; $lblFilter.Text = $UI.filter; $lblFilter.Location = '700,9'; $lblFilter.Width = 42
$txtFilter = New-Object Windows.Forms.TextBox; $txtFilter.Location = '742,7'; $txtFilter.Width = 190; $txtFilter.Add_TextChanged({ Apply-Filter })
$tip.SetToolTip($txtFilter, $UI.tipFilter)
$bar.Controls.AddRange(@($lblFilter, $txtFilter))

# alan adı sağ tık menüsü
$ctxB = New-Object Windows.Forms.ContextMenuStrip
[void](Add-MenuItem $ctxB $UI.assignOne {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'https') { throw $UI.isHttp }
    if (-not $r.Cells['Oneri'].Value) { throw $UI.noMatch }
    $q = $UI.assignOneQ -f $r.Cells['Site'].Value, $r.Cells['Binding'].Value, $r.Cells['Onerilen'].Value
    if ([Windows.Forms.MessageBox]::Show($q, $UI.confirm, 'YesNo', 'Question') -ne 'Yes') { return }
    Set-BindingCert $r.Cells['Site'].Value $r.Cells['Binding'].Value $r.Cells['Thumbprint'].Value $r.Cells['Oneri'].Value; Refresh-All
})
[void](Add-MenuItem $ctxB $UI.addHttps {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'http') { throw $UI.alreadyHttps }
    if (-not $r.Cells['AlanAdi'].Value) { throw $UI.noHost }
    if (-not $r.Cells['Oneri'].Value) { throw $UI.noMatch }
    $ip = ($r.Cells['Binding'].Value -split ':')[0]
    $q = $UI.addQ -f $r.Cells['Site'].Value, $ip, $r.Cells['AlanAdi'].Value, $r.Cells['Onerilen'].Value
    if ([Windows.Forms.MessageBox]::Show($q, $UI.addTitle, 'YesNo', 'Question') -ne 'Yes') { return }
    Add-HttpsBinding $r.Cells['Site'].Value $ip $r.Cells['AlanAdi'].Value $r.Cells['Oneri'].Value; Refresh-All
})
[void]$ctxB.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem $ctxB $UI.probeOne {
    $r = Selected-Domain
    if ($r.Cells['Protokol'].Value -ne 'https') { throw $UI.httpsOnly }
    Probe-Row $r
})
[void](Add-MenuItem $ctxB $UI.showCert { $t = (Selected-Domain).Cells['Thumbprint'].Value; if (-not $t) { throw $UI.noCertHere }; Select-Cert $t })
[void](Add-MenuItem $ctxB $UI.copyHost { [Windows.Forms.Clipboard]::SetText("$((Selected-Domain).Cells['AlanAdi'].Value)") })
$gridB.ContextMenuStrip = $ctxB
$lblLog = New-Object Windows.Forms.Label; $lblLog.Text = $UI.lblLog -f $logFile; $lblLog.Dock = 'Bottom'; $lblLog.Height = 18

$form.Controls.AddRange(@($split, $bar, $load, $menu, $lblLog, $logBox, $status))
$form.Add_Shown({ try { $split.SplitterDistance = [int]($split.Height * 0.5); Write-Log "$($UI.logStart)  $appName $appVersion  $env:USERNAME@$env:COMPUTERNAME"; Refresh-All } catch { Show-Error $_.Exception.Message } })
[void]$form.ShowDialog()
