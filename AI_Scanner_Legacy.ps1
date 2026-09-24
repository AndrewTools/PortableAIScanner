# Portable AI Scanner - Windows 7 legacy edition
# Chosen by PortableAIScanner.exe when CurrentVersion is 6.1
# Does not use Appx, WinGet, Copilot, or on-device browser models

$script:AppName = "Portable AI Scanner (Windows 7)"
$script:AppVersion = "1.6.2"

$script:LogDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:LogDir) { $script:LogDir = (Get-Location).Path }
$script:LogPath = Join-Path $script:LogDir "Log.txt"

function Write-Log {
    param([string]$Message)
    if (-not $script:LogPath) { return }
    $line = "[" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "] " + $Message
    try { Add-Content -Path $script:LogPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Get-WindowsVersionInfo {
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $arch = "32-bit"
        if ($os.OSArchitecture) { $arch = $os.OSArchitecture }
        return ($os.Caption + " (Version " + $os.Version + ", Build " + $os.BuildNumber + ", " + $arch + ")")
    } catch {
        return [Environment]::OSVersion.VersionString
    }
}

function Initialize-Log {
    $win = Get-WindowsVersionInfo
    $header = @"
Portable AI Scanner Log
====================
Started : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Version : $($script:AppVersion) (Windows 7 legacy)
Windows : $win
Script  : $($MyInvocation.MyCommand.Path)
Folder  : $script:LogDir
PS      : $($PSVersionTable.PSVersion)
====================

"@
    try {
        if ($env:PAS_FROM_EXE -eq "1" -and (Test-Path $script:LogPath)) {
            $existing = Get-Content $script:LogPath -ErrorAction SilentlyContinue
            $joined = ""
            if ($existing) { $joined = [string]$existing }
            if ($joined -notmatch "Portable AI Scanner Log") {
                Set-Content -Path $script:LogPath -Value $header -Force -ErrorAction Stop
            } else {
                Add-Content -Path $script:LogPath -Value ("`r`n----- Windows 7 legacy scanner v" + $script:AppVersion + " -----`r`n") -ErrorAction SilentlyContinue
            }
        } else {
            Set-Content -Path $script:LogPath -Value $header -Force -ErrorAction Stop
        }
    } catch {
        $script:LogPath = Join-Path $env:TEMP "PortableAIScanner_Log.txt"
        try { Set-Content -Path $script:LogPath -Value $header -Force } catch { $script:LogPath = $null }
    }
}

Initialize-Log

function Test-ShouldCloseHost {
    if ($env:PAS_FROM_EXE -eq "1") { return $true }
    try {
        $me = Get-WmiObject Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
        if (-not $me) { return $false }
        $cmd = [string]$me.CommandLine
        if ($cmd -match '(?i)-File\s+.*AI_Scanner') { return $true }
        $par = Get-WmiObject Win32_Process -Filter ("ProcessId=" + $me.ParentProcessId) -ErrorAction Stop
        $n = ([string]$par.Name).ToLower()
        if ($n -match "^(wscript\.exe|cscript\.exe)$") { return $true }
    } catch {}
    return $false
}

$script:KeepHostPrompt = -not (Test-ShouldCloseHost)
if ($script:KeepHostPrompt) { Write-Log "LOAD: launched from a prompt; console will stay open" }
else { Write-Log "LOAD: launched from exe or Explorer; host console may be hidden" }

Write-Log "LOAD: Windows 7 legacy scanner started"

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Log "LOAD: WinForms OK"
} catch {
    Write-Log "LOAD ERROR: WinForms failed. .NET 3.5 may be missing."
    throw
}

$script:InstanceMutex = $null
try {
    if ($env:PAS_FROM_EXE -eq "1") {
        Write-Log "LOAD: exe holds the single-instance lock"
    } else {
        $created = $false
        $script:InstanceMutex = New-Object System.Threading.Mutex($true, "Local\PortableAIScanner", [ref]$created)
        if (-not $created) {
            Write-Log "LOAD: another instance is already running"
            [System.Windows.Forms.MessageBox]::Show(
                "Portable AI Scanner is already running. Close that window before starting it again.",
                "Portable AI Scanner", "OK", "Information") | Out-Null
            exit 2
        }
    }
} catch {
    Write-Log "LOAD: mutex check failed (continuing)"
}

function New-Result {
    param([string]$Name)
    $o = New-Object PSObject
    $o | Add-Member NoteProperty Name $Name
    $o | Add-Member NoteProperty Installed $false
    $o | Add-Member NoteProperty Activated "Not Installed"
    $o | Add-Member NoteProperty Details "No install found"
    $o | Add-Member NoteProperty Version ""
    $o | Add-Member NoteProperty Running "No"
    $o | Add-Member NoteProperty DisableHint ""
    return $o
}

function Set-Installed {
    param($Result, [string]$Status, [string]$Details, [string]$Version)
    $Result.Installed = $true
    $Result.Activated = $Status
    if ($Details) { $Result.Details = $Details }
    if ($Version) { $Result.Version = $Version }
}

function Get-FileVersionSafe {
    param([string]$Path)
    if (-not $Path) { return "" }
    if (-not (Test-Path $Path)) { return "" }
    try {
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($v.FileVersion) { return $v.FileVersion }
        if ($v.ProductVersion) { return $v.ProductVersion }
    } catch {}
    return ""
}

function Test-PathAny {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-UninstallHits {
    param([string[]]$Patterns)
    $hits = @()
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $null
            try { $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } catch { $p = $null }
            if (-not $p) { return }
            $dn = [string]$p.DisplayName
            if (-not $dn) { return }
            foreach ($pat in $Patterns) {
                if ($dn -like $pat) {
                    $hits += $p
                    break
                }
            }
        }
    }
    return $hits
}

function Test-ProcessRunning {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $proc = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($proc) { return $true }
    }
    return $false
}

function Get-HowToDisable {
    param([string]$Name)
    return "Control Panel > Programs and Features > find $Name > Uninstall."
}

function Scan-ByExeOrUninstall {
    param(
        [string]$Name,
        [string[]]$Exes,
        [string[]]$UninstallPatterns,
        [string[]]$ProcessNames,
        [int[]]$Ports
    )
    $r = New-Result $Name
    $exe = Test-PathAny $Exes
    $un = @()
    if ($UninstallPatterns) { $un = @(Get-UninstallHits $UninstallPatterns) }

    if ($exe) {
        Set-Installed $r "Installed" ("Executable: " + $exe) (Get-FileVersionSafe $exe)
        $r.DisableHint = Get-HowToDisable $Name
    } elseif ($un.Count -gt 0) {
        $first = $un[0]
        $loc = [string]$first.InstallLocation
        $ver = [string]$first.DisplayVersion
        $detail = "Listed in Programs and Features: " + $first.DisplayName
        if ($loc) { $detail = $detail + " | " + $loc }
        Set-Installed $r "Installed" $detail $ver
        $r.DisableHint = Get-HowToDisable $Name
    } else {
        $r.Details = "No executable or Programs and Features entry found"
        if ($Name -eq "Ollama" -and (Test-Path (Join-Path $env:USERPROFILE ".ollama"))) {
            $r.Details = "Leftover data folder only: " + (Join-Path $env:USERPROFILE ".ollama")
        }
    }

    $running = $false
    if ($ProcessNames -and (Test-ProcessRunning $ProcessNames)) { $running = $true }
    if ($running -and $r.Installed) { $r.Running = "Yes" }
    return $r
}

function Get-ModelStorageRoots {
    $roots = @(
        (Join-Path $env:USERPROFILE ".ollama"),
        (Join-Path $env:USERPROFILE ".cache\huggingface"),
        (Join-Path $env:USERPROFILE ".cache\lm-studio"),
        (Join-Path $env:USERPROFILE ".lmstudio"),
        (Join-Path $env:USERPROFILE "AppData\Local\nomic.ai\GPT4All"),
        (Join-Path $env:USERPROFILE "AppData\Local\Programs\Ollama"),
        (Join-Path $env:USERPROFILE "models"),
        (Join-Path $env:USERPROFILE "LLM"),
        (Join-Path $env:USERPROFILE "llms"),
        "C:\models",
        "D:\models"
    )
    if ($env:LOCALAPPDATA) {
        $roots += (Join-Path $env:LOCALAPPDATA "Programs\Ollama")
        $roots += (Join-Path $env:LOCALAPPDATA "nomic.ai\GPT4All")
    }
    if ($env:OLLAMA_MODELS) { $roots += $env:OLLAMA_MODELS }
    return $roots
}

$script:ModelNameIndex = $null
$script:ModelNameIndexBuilt = $false

function Initialize-ModelNameIndex {
    if ($script:ModelNameIndexBuilt) { return }
    $script:ModelNameIndexBuilt = $true
    $script:IndexNames = @()
    $script:IndexSeen = @{}
    $script:IndexDeadline = (Get-Date).AddSeconds(8)
    $script:IndexMax = 20000
    function Walk-ModelDir {
        param($dir, $depthLeft)
        if (@($script:IndexNames).Count -ge $script:IndexMax) { return }
        if ((Get-Date) -ge $script:IndexDeadline) { return }
        if (-not $dir) { return }
        if (-not (Test-Path -LiteralPath $dir)) { return }
        Get-ChildItem -LiteralPath $dir -ErrorAction SilentlyContinue | ForEach-Object {
            if (@($script:IndexNames).Count -ge $script:IndexMax) { return }
            if ((Get-Date) -ge $script:IndexDeadline) { return }
            if ($_.PSIsContainer) {
                if ($depthLeft -gt 0) { Walk-ModelDir $_.FullName ($depthLeft - 1) }
                return
            }
            $n = $_.Name
            if (-not $n) { return }
            if ($n -notmatch '\.(gguf|safetensors|ggml|bin|ot)$') { return }
            if ($n -eq 'weights.bin' -and $_.FullName -notmatch 'OptGuideOnDeviceModel|OptimizationGuide|optimization-guide') { return }
            if ($script:IndexSeen.ContainsKey($n)) { return }
            $script:IndexSeen[$n] = $true
            $script:IndexNames += $n
        }
    }
    foreach ($root in Get-ModelStorageRoots) {
        if (@($script:IndexNames).Count -ge $script:IndexMax) { break }
        if ((Get-Date) -ge $script:IndexDeadline) { break }
        try { Walk-ModelDir $root 4 } catch {}
    }
    $script:ModelNameIndex = @($script:IndexNames)
    Write-Log ("Model name index size: " + @($script:ModelNameIndex).Count)
}

function Find-Family {
    param([string]$DisplayName, [string[]]$Keywords)
    $r = New-Result $DisplayName
    Initialize-ModelNameIndex
    $hits = @()
    foreach ($n in @($script:ModelNameIndex)) {
        foreach ($kw in $Keywords) {
            if ($n -match $kw) {
                $hits += $n
                break
            }
        }
    }
    if ($hits.Count -gt 0) {
        $sample = ($hits | Select-Object -First 4) -join "; "
        Set-Installed $r "Installed" ("Files or folders: " + $sample) ""
        $r.DisableHint = "Open the app that downloaded this model (Ollama, LM Studio, GPT4All, or Jan) and remove the model. Or Control Panel > Programs and Features > uninstall that app."
    } else {
        $r.Activated = "None Found on Disk"
        $r.Details = "No matching model files in common folders"
    }
    return $r
}

function Scan-LocalSummary {
    $r = New-Result "Local AI Models (other / summary)"
    Initialize-ModelNameIndex
    $gguf = 0
    foreach ($n in @($script:ModelNameIndex)) {
        if ($n -like "*.gguf") { $gguf++ }
    }
    if ($gguf -gt 0) {
        Set-Installed $r "Installed" ("GGUF files: " + $gguf) ""
        $r.DisableHint = "Open Ollama, LM Studio, GPT4All, or Jan and remove models. Or uninstall that app from Control Panel."
    } else {
        $r.Activated = "None Found on Disk"
        $r.Details = "No GGUF files in common model folders"
    }
    return $r
}

function Scan-BrowserExe {
    param([string]$Name, [string[]]$Exes)
    $r = New-Result $Name
    $exe = Test-PathAny $Exes
    if ($exe) {
        Set-Installed $r "Installed" ("Browser found. Windows 7 has no on-device Copilot or Gemini Nano to scan. | " + $exe) (Get-FileVersionSafe $exe)
        $r.DisableHint = ""
    } else {
        $r.Details = "Browser not found"
    }
    return $r
}

# ----- GUI -----
Write-Log "LOAD: building window"

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName v$script:AppVersion"
$form.Size = New-Object System.Drawing.Size(900, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)
$form.StartPosition = "CenterScreen"
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = $script:AppName
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblOS = New-Object System.Windows.Forms.Label
$lblOS.Text = "Windows: " + (Get-WindowsVersionInfo)
$lblOS.Location = New-Object System.Drawing.Point(20, 48)
$lblOS.Size = New-Object System.Drawing.Size(840, 22)
$lblOS.ForeColor = [System.Drawing.Color]::DarkBlue
$form.Controls.Add($lblOS)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Scan"
$btnScan.Location = New-Object System.Drawing.Point(20, 78)
$btnScan.Size = New-Object System.Drawing.Size(90, 34)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = "Flat"
$form.Controls.Add($btnScan)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(116, 78)
$btnCancel.Size = New-Object System.Drawing.Size(80, 34)
$btnCancel.FlatStyle = "Flat"
$btnCancel.Visible = $false
$btnCancel.Enabled = $false
$form.Controls.Add($btnCancel)

$btnDetected = New-Object System.Windows.Forms.Button
$btnDetected.Text = "Detected"
$btnDetected.Location = New-Object System.Drawing.Point(202, 78)
$btnDetected.Size = New-Object System.Drawing.Size(88, 34)
$btnDetected.FlatStyle = "Flat"
$btnDetected.Visible = $false
$form.Controls.Add($btnDetected)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export list"
$btnExport.Location = New-Object System.Drawing.Point(296, 78)
$btnExport.Size = New-Object System.Drawing.Size(100, 34)
$btnExport.FlatStyle = "Flat"
$btnExport.Visible = $false
$form.Controls.Add($btnExport)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Windows 7 legacy scan. Looks for local apps and model files only."
$lblStatus.Location = New-Object System.Drawing.Point(406, 78)
$lblStatus.Size = New-Object System.Drawing.Size(454, 34)
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 118)
$progress.Size = New-Object System.Drawing.Size(840, 16)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 145)
$lv.Size = New-Object System.Drawing.Size(840, 400)
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.Anchor = "Top, Bottom, Left, Right"
[void]$lv.Columns.Add("AI Name", 220)
[void]$lv.Columns.Add("Installed", 70)
[void]$lv.Columns.Add("Running", 70)
[void]$lv.Columns.Add("Status", 160)
[void]$lv.Columns.Add("Version", 100)
[void]$lv.Columns.Add("Details", 240)
[void]$lv.Columns.Add("How to disable", 220)
$form.Controls.Add($lv)


function Add-Section {
    param([string]$Title, [switch]$SkipStore)
    $item = New-Object System.Windows.Forms.ListViewItem($Title)
    [void]$item.SubItems.Add("")
    [void]$item.SubItems.Add("")
    [void]$item.SubItems.Add("")
    [void]$item.SubItems.Add("")
    [void]$item.SubItems.Add("")
    [void]$item.SubItems.Add("")
    $item.ForeColor = [System.Drawing.Color]::DimGray
    $item.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $item.Font = New-Object System.Drawing.Font($lv.Font, [System.Drawing.FontStyle]::Bold)
    [void]$lv.Items.Add($item)
    if (-not $SkipStore) { $script:LegacyRows += @{ Kind = "section"; Title = $Title } }
}

function Add-Row {
    param($r, [switch]$SkipStore)
    $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
    if ($r.Installed) { [void]$item.SubItems.Add("Yes") } else { [void]$item.SubItems.Add("No") }
    [void]$item.SubItems.Add($r.Running)
    [void]$item.SubItems.Add($r.Activated)
    [void]$item.SubItems.Add($r.Version)
    [void]$item.SubItems.Add($r.Details)
    $hint = ""
    if ($r.Installed) { $hint = $r.DisableHint }
    [void]$item.SubItems.Add($hint)
    if ($r.Running -like "Yes*") {
        $item.ForeColor = [System.Drawing.Color]::Firebrick
    } elseif ($r.Installed) {
        $item.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $item.ForeColor = [System.Drawing.Color]::Gray
    }
    [void]$lv.Items.Add($item)
    if ($lv.Items.Count -eq 1 -or ($lv.Items.Count % 10 -eq 0)) { $item.EnsureVisible() }
    if (-not $SkipStore) { $script:LegacyRows += @{ Kind = "row"; R = $r } }
}

$script:CancelScan = $false
$btnCancel.Add_Click({ $script:CancelScan = $true; $lblStatus.Text = "Canceling scan..." })

$btnScan.Add_Click({
    $script:CancelScan = $false
    $btnScan.Enabled = $false
    $btnCancel.Visible = $true
    $btnCancel.Enabled = $true
    $btnDetected.Visible = $false
    $btnExport.Visible = $false
    $script:FilterDetected = $false
    $script:LegacyRows = @()
    $lv.Items.Clear()
    $script:ModelNameIndex = $null
    $script:ModelNameIndexBuilt = $false
    Write-Log "SCAN: Windows 7 legacy scan started"
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    $jobs = @(
        @{ Title = "Local apps"; Fn = {
            Scan-ByExeOrUninstall -Name "Ollama" -Exes @(
                "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
                "${env:ProgramFiles}\Ollama\ollama.exe"
            ) -UninstallPatterns @("Ollama*") -ProcessNames @("ollama","ollama app") -Ports @(11434)
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "LM Studio" -Exes @(
                "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe",
                "$env:USERPROFILE\AppData\Local\LM Studio\LM Studio.exe"
            ) -UninstallPatterns @("LM Studio*") -ProcessNames @("LM Studio") -Ports @(1234)
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "GPT4All" -Exes @(
                "$env:LOCALAPPDATA\Programs\GPT4All\bin\chat.exe",
                "$env:LOCALAPPDATA\nomic.ai\GPT4All\bin\chat.exe"
            ) -UninstallPatterns @("GPT4All*") -ProcessNames @("gpt4all") -Ports @(4891)
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "Jan" -Exes @(
                "$env:LOCALAPPDATA\Programs\jan\Jan.exe",
                "$env:LOCALAPPDATA\jan\Jan.exe"
            ) -UninstallPatterns @("Jan*") -ProcessNames @("Jan") -Ports @(1337)
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "llama.cpp / llama-server" -Exes @(
                "$env:USERPROFILE\llama.cpp\llama-server.exe",
                "$env:USERPROFILE\llama.cpp\llama-cli.exe"
            ) -UninstallPatterns @("llama.cpp*") -ProcessNames @("llama-server","llama-cli") -Ports @(8080)
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "KoboldCPP" -Exes @(
                "$env:USERPROFILE\koboldcpp\koboldcpp.exe"
            ) -UninstallPatterns @("KoboldCPP*","koboldcpp*") -ProcessNames @("koboldcpp") -Ports @()
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "Msty" -Exes @(
                "$env:LOCALAPPDATA\Programs\Msty\Msty.exe"
            ) -UninstallPatterns @("Msty*") -ProcessNames @("Msty") -Ports @()
        }},
        @{ Title = ""; Fn = {
            Scan-ByExeOrUninstall -Name "AnythingLLM" -Exes @(
                "$env:LOCALAPPDATA\Programs\AnythingLLM\AnythingLLM.exe"
            ) -UninstallPatterns @("AnythingLLM*") -ProcessNames @("AnythingLLM") -Ports @()
        }},
        @{ Title = "Model files"; Fn = { Find-Family "Qwen (Alibaba)" @('(?i)qwen') }},
        @{ Title = ""; Fn = { Find-Family "Llama (Meta)" @('(?i)llama-?[234]','(?i)meta-llama') }},
        @{ Title = ""; Fn = { Find-Family "DeepSeek" @('(?i)deepseek','(?i)r1-distill') }},
        @{ Title = ""; Fn = { Find-Family "Gemma (Google)" @('(?i)gemma') }},
        @{ Title = ""; Fn = { Find-Family "Phi (Microsoft)" @('(?i)phi-?[34]') }},
        @{ Title = ""; Fn = { Find-Family "GLM (Zhipu)" @('(?i)glm-?[45]','(?i)chatglm') }},
        @{ Title = ""; Fn = { Find-Family "Mistral / Mixtral" @('(?i)mistral','(?i)mixtral') }},
        @{ Title = ""; Fn = { Find-Family "GPT-J / Pygmalion" @('(?i)gpt-?j','(?i)pygmalion') }},
        @{ Title = ""; Fn = { Find-Family "gpt-oss" @('(?i)gpt-oss','(?i)gptoss') }},
        @{ Title = ""; Fn = { Scan-LocalSummary }},
        @{ Title = "Browsers"; Fn = {
            Scan-BrowserExe "Google Chrome" @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
        }},
        @{ Title = ""; Fn = {
            Scan-BrowserExe "Mozilla Firefox" @(
                "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
                "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
            )
        }}
    )

    $total = $jobs.Count
    $i = 0
    $found = 0
    foreach ($job in $jobs) {
        if ($script:CancelScan) { break }
        $i++
        if ($job.Title) { Add-Section $job.Title }
        $lblStatus.Text = "Scanning $i of $total"
        $progress.Value = [Math]::Min(100, [int](($i / $total) * 100))
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $r = & $job.Fn
            Add-Row $r
            if ($r.Installed) {
                $found++
                Write-Log ("FOUND: " + $r.Name + " | Installed=Yes | Running=" + $r.Running + " | Status=" + $r.Activated)
            }
        } catch {
            Write-Log ("SCAN ERROR: " + $_.Exception.Message)
        }
    }

    $watch.Stop()
    $sec = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
    $lblStatus.Text = "Scan done in $sec sec. Installed: $found"
    $progress.Value = 100
    Write-Log "SCAN: finished in $sec sec, installed $found"
    if ($script:CancelScan) { $lblStatus.Text = "Scan canceled. " + $lblStatus.Text; Write-Log "SCAN: canceled" }
    $btnCancel.Visible = $true
    $btnCancel.Enabled = $false
    $btnScan.Enabled = $true
    $btnScan.Text = "Rescan"
    $script:HasScanResults = $true
    $btnDetected.Visible = $true
    $btnExport.Visible = $true
})

$script:FilterDetected = $false
$script:HasScanResults = $false
$script:LegacyRows = @()

$btnDetected.Add_Click({
    if (-not $script:HasScanResults) { return }
    $script:FilterDetected = -not $script:FilterDetected
    $lv.Items.Clear()
    foreach ($row in @($script:LegacyRows)) {
        if ($row.Kind -eq "section") {
            if (-not $script:FilterDetected) { Add-Section $row.Title -SkipStore }
        } else {
            $r = $row.R
            $keep = $true
            if ($script:FilterDetected) {
                $keep = $r.Installed -or ($r.Running -like "Yes*")
            }
            if ($keep) { Add-Row $r -SkipStore }
        }
    }
})

$btnExport.Add_Click({
    if (-not $script:HasScanResults) { return }
    $stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = "Export list"
    $dlg.Filter = "CSV (Excel, LibreOffice) (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.DefaultExt = "csv"
    $dlg.FileName = "AI_Scanner_export_$stamp.csv"
    $dlg.InitialDirectory = $script:LogDir
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $lines = @()
        $lines += '"AI Name","Installed","Running","Status","Version","Details","How to disable"'
        foreach ($item in $lv.Items) {
            $cols = @()
            foreach ($si in $item.SubItems) {
                $t = [string]$si.Text
                $t = $t.Replace('"', '""')
                $t = $t -replace "[\r\n]+", " "
                $cols += '"' + $t + '"'
            }
            $lines += ($cols -join ",")
        }
        $utf8bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllLines($dlg.FileName, [string[]]$lines, $utf8bom)
        Write-Log ("EXPORT: " + $dlg.FileName)
        $lblStatus.Text = "Exported to " + $dlg.FileName
    } catch {
        Write-Log ("EXPORT failed: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show("Could not write the export file.", "Portable AI Scanner", "OK", "Error") | Out-Null
    }
})

Write-Log "LOAD: window ready"
try {
    [void]$form.ShowDialog()
} finally {
    try { if ($form) { $form.Dispose() } } catch {}
    try { if ($script:InstanceMutex) { $script:InstanceMutex.ReleaseMutex(); $script:InstanceMutex.Dispose() } } catch {}
    Write-Log "LOAD: process exiting"
}
if (-not $script:KeepHostPrompt) {
    [Environment]::Exit(0)
}
