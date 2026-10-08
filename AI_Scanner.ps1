# Portable AI Scanner - Windows 10/11 App
# No installation required. Run with: powershell -STA -ExecutionPolicy Bypass -File AI_Scanner.ps1
# Or rebuild PortableAIScanner.exe with Build_Wrapper.bat
# Changelog: Version.txt (keep in sync with $script:AppVersion and $script:AppBuild)
# Brace audit: raw } can be one higher than { because a regex uses a
# literal } in a character class (Chrome model_execution pattern).
# That is not a missing function closer. Count braces outside strings.

$script:AppName = "Portable AI Scanner"
$script:AppVersion = "1.7.5"
$script:AppBuild = "0179"
$script:GitHubRepo = "AndrewTools/PortableAIScanner"
$script:UpdateUrl = ""

if ($env:PAS_FROM_EXE -ne "1") {
    try {
        $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        if ($apt -ne [System.Threading.ApartmentState]::STA) {
            # Second process is expected on a non-STA host. The exe never uses this path.
            $self = $PSCommandPath
            if (-not $self) { $self = $MyInvocation.MyCommand.Path }
            if ($self -and (Test-Path -LiteralPath $self)) {
                $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
                if (-not (Test-Path -LiteralPath $ps)) { $ps = "powershell.exe" }
                $arg = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$self`""
                Start-Process -FilePath $ps -ArgumentList $arg -WorkingDirectory (Split-Path -Parent $self)
                exit 0
            }
        }
    } catch {}
}

# ========== Logging (Log.txt, overwritten at each launch) ==========
$script:LogDir = $PSScriptRoot
if (-not $script:LogDir) { $script:LogDir = (Get-Location).Path }
$script:LogPath = Join-Path -Path $script:LogDir -ChildPath "Log.txt"

function Ensure-LogFile {
    if (-not $script:LogDir) { $script:LogDir = (Get-Location).Path }
    if (-not $script:LogPath) {
        $script:LogPath = Join-Path -Path $script:LogDir -ChildPath "Log.txt"
    }
    $missing = $true
    try {
        if ($script:LogPath -and (Test-Path -LiteralPath $script:LogPath)) {
            if (([System.IO.FileInfo]$script:LogPath).Length -gt 0) { $missing = $false }
        }
    } catch { $missing = $true }
    if (-not $missing) { return $true }
    $win = [Environment]::OSVersion.VersionString
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $arch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
        $win = "$($os.Caption) (Version $($os.Version), Build $($os.BuildNumber), $arch)"
    } catch {}
    $header = @"
Portable AI Scanner Log
====================
Started : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Version : $($script:AppVersion)
Build   : $($script:AppBuild)
Windows : $win
Script  : $PSCommandPath
Folder  : $script:LogDir
PS      : $($PSVersionTable.PSVersion)
64-bit  : $([Environment]::Is64BitProcess)
====================

"@
    try {
        $dir = Split-Path -Parent $script:LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        Set-Content -LiteralPath $script:LogPath -Value $header -Encoding UTF8 -Force -ErrorAction Stop
        return $true
    } catch {
        $alt = Join-Path -Path $env:TEMP -ChildPath "PortableAIScanner_Log.txt"
        try {
            $script:LogPath = $alt
            Set-Content -LiteralPath $script:LogPath -Value $header -Encoding UTF8 -Force -ErrorAction Stop
            return $true
        } catch {
            $script:LogPath = $null
            return $false
        }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )
    if (-not (Ensure-LogFile)) { return }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    if ($ErrorRecord) {
        $entry += "`r`n  Exception: $($ErrorRecord.Exception.Message)"
        $entry += "`r`n  Category : $($ErrorRecord.CategoryInfo.Category)"
        $entry += "`r`n  Script   : $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
        if ($ErrorRecord.InvocationInfo.Line) {
            $entry += "`r`n  Line     : $($ErrorRecord.InvocationInfo.Line.Trim())"
        }
    }
    $entry += "`r`n`r`n"
    try {
        [System.IO.File]::AppendAllText($script:LogPath, $entry)
    } catch {
        try {
            if (-not $script:LogPath -or -not (Test-Path -LiteralPath $script:LogPath)) {
                if (Ensure-LogFile) { [System.IO.File]::AppendAllText($script:LogPath, $entry) }
            }
        } catch {}
    }
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )
    Write-Log -Message $Message -ErrorRecord $ErrorRecord
}

function Initialize-Log {
    if ($env:PAS_FROM_EXE -eq "1" -and $script:LogPath -and (Test-Path -LiteralPath $script:LogPath) -and (([System.IO.FileInfo]$script:LogPath).Length -gt 0)) {
        return
    }
    [void](Ensure-LogFile)
}

Initialize-Log
Write-Log "LOAD: script file started"
trap {
    Write-Log "LOAD ERROR (trap): $_" -ErrorRecord $_
    if ($null -eq $form -or $null -eq $lv) { exit 1 }
    if ($script:ScanBusy) {
        Write-Log "SCAN ERROR (trap): $_" -ErrorRecord $_
    }
    continue
}

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Write-Log "LOAD: System.Windows.Forms OK"
} catch {
    Write-Log "LOAD ERROR: System.Windows.Forms failed" -ErrorRecord $_
    throw
}
try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Write-Log "LOAD: System.Drawing OK"
} catch {
    Write-Log "LOAD ERROR: System.Drawing failed" -ErrorRecord $_
    throw
}

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

# Hide the attached console if present (SW_HIDE = 0, not SW_MINIMIZE = 6)
try {
    $hideConsoleSrc = @"
using System;
using System.Runtime.InteropServices;
public class NativeConsole {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    if ($script:KeepHostPrompt) {
        Write-Log "LOAD: console left visible (started from a prompt)"
    } else {
    Add-Type -TypeDefinition $hideConsoleSrc -ErrorAction SilentlyContinue
    $con = [NativeConsole]::GetConsoleWindow()
    if ($con -ne [IntPtr]::Zero) {
        [void][NativeConsole]::ShowWindow($con, 0)
        Write-Log "LOAD: console window hidden"
    } else {
        Write-Log "LOAD: no console window attached"
    }
    }
} catch {
    Write-Log "LOAD ERROR: hide-console step failed (non-fatal)" -ErrorRecord $_
}
Write-Log "LOAD: helpers starting"

function Get-WindowsClientKind {
    # 7 = Windows 7, 10 = Windows 10/11, 0 = not supported (Server, 8/8.1, other)
    try {
        $os = $null
        try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch {}
        if (-not $os) { $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop }
        if ([int]$os.ProductType -ne 1) { return 0 }
        if ([string]$os.Caption -match "(?i)Server") { return 0 }
        $ver = [version]$os.Version
        if ($ver.Major -eq 6 -and $ver.Minor -eq 1) { return 7 }
        if ($ver.Major -ge 10) { return 10 }
    } catch {}
    return 0
}
function Show-UnsupportedWindowsMessage {
    param([string]$Extra = "")
    $msg = "Portable AI Scanner runs on Windows 7, 10, and 11 only.`r`nWindows Server and Windows 8 / 8.1 are not supported."
    if ($Extra) { $msg += "`r`n`r`n" + $Extra }
    try {
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {}
}
$script:WindowsClientKind = Get-WindowsClientKind
if ($script:WindowsClientKind -ne 10) {
    Write-Log ("LOAD: this script is Windows 10/11 only (kind=" + $script:WindowsClientKind + ")")
    $extra = ""
    if ($script:WindowsClientKind -eq 7) {
        $extra = "On Windows 7 run AI_Scanner_Legacy.ps1, or use PortableAIScanner.exe."
    }
    Show-UnsupportedWindowsMessage $extra
    exit 1
}

function Test-ParentIsScannerExe {
    try {
        if ($env:PAS_FROM_EXE -ne "1") { return $false }
        $here = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
        $ppid = 0
        try { $ppid = [int]$here.ParentProcessId } catch { return $false }
        if ($ppid -le 0) { return $false }
        $par = Get-CimInstance Win32_Process -Filter "ProcessId=$ppid" -ErrorAction Stop
        $path = [string]$par.ExecutablePath
        if (-not $path) { return $false }
        return ([IO.Path]::GetFileName($path) -eq "PortableAIScanner.exe")
    } catch { return $false }
}

function Test-WrapperMutexHeld {
    # A leftover lock from a starter that already exited is not a running copy.
    # Take it. If Windows says the last owner exited, release it and continue.
    $m = $null
    $created = $false
    try {
        $m = New-Object System.Threading.Mutex($true, "Local\PortableAIScanner", [ref]$created)
        if ($created) {
            try { $m.ReleaseMutex() } catch {}
            try { $m.Dispose() } catch {}
            return $false
        }
        try { $m.Dispose() } catch {}
        return $true
    } catch [System.Threading.AbandonedMutexException] {
        $owned = $_.Exception.Mutex
        if ($owned) {
            try { $owned.ReleaseMutex() } catch {}
            try { $owned.Dispose() } catch {}
        }
        return $false
    } catch {
        return "failed"
    }
}

$script:InstanceMutex = $null
# Script lock is Local\PortableAIScanner.Script so it does not collide
# with the wrapper lock Local\PortableAIScanner. Always take the script
# lock. If this is not a confirmed exe child, also refuse when the
# wrapper lock already exists (exe + right-click .ps1).
if (-not (Test-ParentIsScannerExe)) {
    $wrap = Test-WrapperMutexHeld
    if ($wrap -eq "failed") {
        Write-Log "LOAD: starter lock was not returned"
        [System.Windows.Forms.MessageBox]::Show(
            "The last copy closed badly.`r`nStart Portable AI Scanner again.",
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 3
    }
    if ($wrap) {
        Write-Log "LOAD: wrapper instance is already running"
        [System.Windows.Forms.MessageBox]::Show(
            "Portable AI Scanner is already running.`r`nClose the other window before starting a new one.",
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 2
    }
}
try {
    $created = $false
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, "Local\PortableAIScanner.Script", [ref]$created)
    if (-not $created) {
        Write-Log "LOAD: another instance is already running"
        [System.Windows.Forms.MessageBox]::Show(
            "Portable AI Scanner is already running.`r`nClose the other window before starting a new one.",
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 2
    }
    Write-Log "LOAD: single-instance lock taken"
} catch [System.Threading.AbandonedMutexException] {
    $owned = $_.Exception.Mutex
    $held = $false
    if (-not $owned) {
        $created2 = $false
        try {
            $retry = New-Object System.Threading.Mutex($true, "Local\PortableAIScanner.Script", [ref]$created2)
            if ($created2) { $owned = $retry }
            else {
                $held = $true
                try { $retry.Dispose() } catch {}
            }
        } catch [System.Threading.AbandonedMutexException] {
            $owned = $_.Exception.Mutex
        } catch {
            $owned = $null
        }
    }
    if ($held) {
        Write-Log "LOAD: another instance is already running"
        [System.Windows.Forms.MessageBox]::Show(
            "Portable AI Scanner is already running.`r`nClose the other window before starting a new one.",
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 2
    }
    if ($owned) {
        $script:InstanceMutex = $owned
        Write-Log "LOAD: leftover script lock kept; continuing"
    } else {
        Write-Log "LOAD: leftover script lock was not returned"
        [System.Windows.Forms.MessageBox]::Show(
            "The last copy closed badly.`r`nStart Portable AI Scanner again.",
            "Portable AI Scanner",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 3
    }
} catch {
    Write-Log "LOAD: single-instance check failed"
    [System.Windows.Forms.MessageBox]::Show(
        "The last copy closed badly.`r`nStart Portable AI Scanner again.",
        "Portable AI Scanner", "OK", "Information") | Out-Null
    exit 3
}

# ========== Helpers ==========

function Get-WindowsVersionInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $caption = $os.Caption
        $version = $os.Version
        $build = $os.BuildNumber
        $arch = if ([Environment]::Is64BitOperatingSystem) { "64-bit" } else { "32-bit" }
        return "$caption (Version $version, Build $build, $arch)"
    } catch {
        return [System.Environment]::OSVersion.VersionString
    }
}

function Get-AppxByName {
    param([string]$Pattern)
    try {
        if ($null -eq $script:AllAppx) {
            $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
        }
        $pkgs = @($script:AllAppx | Where-Object { $_.Name -like $Pattern })
        if ($pkgs.Count -gt 0) { return $pkgs }
        return $null
    } catch { return $null }
}

function Test-LocalPortOpen {
    param([int]$Port, [int]$TimeoutMs = 200)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            try { $client.EndConnect($iar) } catch {}
            try { $client.Close() } catch {}
            return $false
        }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

function Get-KnownCommandSource {
    param(
        [string]$Name,
        [string[]]$PathLike
    )
    if (-not $Name) { return $null }
    $cmd = $null
    try { $cmd = Get-Command $Name -ErrorAction SilentlyContinue } catch { return $null }
    if (-not $cmd) { return $null }
    $src = [string]$cmd.Source
    if (-not $src) { return $null }
    foreach ($pat in @($PathLike)) {
        if ($pat -and ($src -like $pat)) { return $src }
    }
    return $null
}

function Test-PathAny {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Get-NewestExistingExe {
    param([string[]]$Paths)
    $best = $null
    $bestMajor = -1
    $bestMinor = -1
    $bestBuild = -1
    foreach ($p in @($Paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $ver = Get-FileVersionSafe $p
        $maj = 0; $min = 0; $bld = 0
        if ($ver -match '^(\d+)(?:\.(\d+))?(?:\.(\d+))?') {
            $maj = [int]$Matches[1]
            if ($Matches[2]) { $min = [int]$Matches[2] }
            if ($Matches[3]) { $bld = [int]$Matches[3] }
        }
        if (-not $best -or $maj -gt $bestMajor -or ($maj -eq $bestMajor -and $min -gt $bestMinor) -or ($maj -eq $bestMajor -and $min -eq $bestMinor -and $bld -gt $bestBuild)) {
            $best = $p
            $bestMajor = $maj
            $bestMinor = $min
            $bestBuild = $bld
        }
    }
    if ($best) { return $best }
    return $null
}

function Get-FileVersionSafe {
    param([string]$Path)
    try {
        if ($Path -and (Test-Path -LiteralPath $Path)) {
            return (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
        }
    } catch {}
    return ""
}

function Get-RegValueSafe {
    param([string]$Path, [string]$Name)
    try {
        $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $p.$Name
    } catch { return $null }
}

function Read-NotepadSettingsDatFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $bytes = $null
    $fs = $null
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        } catch {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        }
        $max = 4194304
        $len = [int][Math]::Min($fs.Length, $max)
        if ($len -lt 8) { return $null }
        $buf = New-Object byte[] $len
        $read = 0
        while ($read -lt $len) {
            $n = $fs.Read($buf, $read, $len - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        if ($read -le 0) { return $null }
        if ($read -lt $len) {
            $bytes = New-Object byte[] $read
            [Array]::Copy($buf, $bytes, $read)
        } else {
            $bytes = $buf
        }
    } catch {
        Write-ErrorLog "Notepad settings.dat file read failed" -ErrorRecord $_
        return [PSCustomObject]@{ Name = ""; Value = $null; Unread = $true }
    } finally {
        if ($fs) { try { $fs.Dispose() } catch {} }
    }
    # Unofficial user switch. Microsoft does not publish this name.
    # settings.dat hive, value RewriteEnabled, type 5f5e10b. Do not reg-load.
    # Developer notes list RewriteEnabled. Writing tools is the later
    # on-screen name. A bad byte on that name must not hide RewriteEnabled.
    $rank = @{
        WritingToolsEnabled = 1
        RewriteEnabled = 2
    }
    $best = $null
    $bestRank = 99
    $sawName = $false
    $hiveBase = 0
    if ($bytes.Length -gt 0x1004 -and $bytes[0] -eq 0x72 -and $bytes[1] -eq 0x65 -and $bytes[2] -eq 0x67 -and $bytes[3] -eq 0x66) {
        $hiveBase = 0x1000
    }
    $limit = $bytes.Length - 24
    for ($i = 4; $i -le $limit; $i++) {
        if ($bytes[$i] -ne 0x76 -or $bytes[$i + 1] -ne 0x6B) { continue }
        $nameLen = [BitConverter]::ToUInt16($bytes, $i + 2)
        if ($nameLen -lt 4 -or $nameLen -gt 64) { continue }
        $flags = [BitConverter]::ToUInt16($bytes, $i + 16)
        $ascii = (($flags -band 1) -eq 1)
        # Name length in the file is bytes for both ASCII and Unicode.
        $nameBytes = [int]$nameLen
        if ((-not $ascii) -and (($nameBytes % 2) -ne 0)) { continue }
        if (($i + 20 + $nameBytes) -gt $bytes.Length) { continue }
        $valName = ""
        try {
            if ($ascii) {
                $valName = [System.Text.Encoding]::ASCII.GetString($bytes, $i + 20, $nameBytes)
            } else {
                $valName = [System.Text.Encoding]::Unicode.GetString($bytes, $i + 20, $nameBytes)
            }
        } catch { continue }
        $valName = $valName.TrimEnd([char]0)
        if (-not $rank.ContainsKey($valName)) { continue }
        $typeAt = [BitConverter]::ToUInt32($bytes, $i + 12)
        if ($typeAt -ne 0x5f5e10b) { continue }
        $sawName = $true
        $thisRank = [int]$rank[$valName]
        if ($thisRank -ge $bestRank) { continue }
        $dataLenRaw = [BitConverter]::ToUInt32($bytes, $i + 4)
        $inline = (($dataLenRaw -band 0x80000000) -ne 0)
        $dataLen = [int]($dataLenRaw -band 0x7FFFFFFF)
        $dataField = [BitConverter]::ToUInt32($bytes, $i + 8)
        $payload = $null
        if ($inline) {
            if ($dataLen -lt 1 -or $dataLen -gt 4) { continue }
            $payload = New-Object byte[] $dataLen
            [Array]::Copy($bytes, $i + 8, $payload, 0, $dataLen)
        } else {
            if ($dataLen -lt 1) { continue }
            $abs = $hiveBase + [int]$dataField + 4
            if ($abs -lt 0 -or $abs -ge $bytes.Length) { continue }
            $payload = New-Object byte[] 1
            $payload[0] = $bytes[$abs]
        }
        $val = -1
        if ($payload -and $payload.Length -ge 1) {
            $b = [int]$payload[0]
            if ($b -eq 0 -or $b -eq 1) { $val = $b }
        }
        if ($val -eq 0 -or $val -eq 1) {
            $best = [PSCustomObject]@{ Name = $valName; Value = $val }
            $bestRank = $thisRank
            if ($bestRank -eq 1) { break }
        }
    }
    if (-not $best) {
        # Whole value name only. Read the switch from that same record.
        foreach ($name in @("WritingToolsEnabled", "RewriteEnabled")) {
            $thisRank = 1
            if ($name -eq "RewriteEnabled") { $thisRank = 2 }
            if ($thisRank -ge $bestRank) { continue }
            foreach ($enc in @([System.Text.Encoding]::Unicode, [System.Text.Encoding]::ASCII)) {
                $needle = $enc.GetBytes($name)
                $maxAt = $bytes.Length - $needle.Length
                for ($at = 20; $at -le $maxAt; $at++) {
                    $match = $true
                    for ($k = 0; $k -lt $needle.Length; $k++) {
                        if ($bytes[$at + $k] -ne $needle[$k]) { $match = $false; break }
                    }
                    if (-not $match) { continue }
                    $vk = $at - 20
                    if ($bytes[$vk] -ne 0x76 -or $bytes[$vk + 1] -ne 0x6B) { continue }
                    $nameLen = [int][BitConverter]::ToUInt16($bytes, $vk + 2)
                    if ($enc -eq [System.Text.Encoding]::Unicode -and (($nameLen % 2) -ne 0)) { continue }
                    $nullOk = $false
                    if ($nameLen -eq ($needle.Length + 1) -and $bytes[$at + $needle.Length] -eq 0) { $nullOk = $true }
                    if ($nameLen -eq ($needle.Length + 2) -and $bytes[$at + $needle.Length] -eq 0 -and $bytes[$at + $needle.Length + 1] -eq 0) { $nullOk = $true }
                    if ($nameLen -ne $needle.Length -and -not $nullOk) { continue }
                    if ($bytes[$at - 8] -ne 0x0B -or $bytes[$at - 7] -ne 0xE1 -or $bytes[$at - 6] -ne 0xF5 -or $bytes[$at - 5] -ne 0x05) { continue }
                    $sawName = $true
                    $dataLenRaw = [BitConverter]::ToUInt32($bytes, $vk + 4)
                    $inline = (($dataLenRaw -band 0x80000000) -ne 0)
                    $dataField = [BitConverter]::ToUInt32($bytes, $vk + 8)
                    $b = -1
                    if ($inline) {
                        $b = [int]$bytes[$vk + 8]
                    } else {
                        $abs = $hiveBase + [int]$dataField + 4
                        if ($abs -ge 0 -and $abs -lt $bytes.Length) { $b = [int]$bytes[$abs] }
                    }
                    if ($b -eq 0 -or $b -eq 1) {
                        $best = [PSCustomObject]@{ Name = $name; Value = $b }
                        $bestRank = $thisRank
                        break
                    }
                }
                if ($best -and $bestRank -eq $thisRank) { break }
            }
            if ($bestRank -eq 1) { break }
        }
    }
    if ($best) { return $best }
    if ($sawName) {
        return [PSCustomObject]@{ Name = ""; Value = $null; Unread = $true }
    }
    if ($hiveBase -eq 0x1000) {
        return [PSCustomObject]@{ Name = ""; Value = $null; Absent = $true }
    }
    return [PSCustomObject]@{ Name = ""; Value = $null; Unread = $true }
}

function New-LoopbackListenOwnerMap {
    $map = @{}
    try {
        $conns = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)
        foreach ($c in $conns) {
            $addr = ""
            try { $addr = [string]$c.LocalAddress } catch {}
            if ($addr -and $addr -ne "127.0.0.1" -and $addr -ne "::1" -and $addr -ne "0.0.0.0" -and $addr -ne "::") { continue }
            $lp = 0
            try { $lp = [int]$c.LocalPort } catch { continue }
            if ($lp -le 0) { continue }
            if ($map.ContainsKey($lp)) { continue }
            $ownPid = 0
            try { $ownPid = [int]$c.OwningProcess } catch { continue }
            if ($ownPid -le 0) { continue }
            try {
                $pr = Get-Process -Id $ownPid -ErrorAction SilentlyContinue
                if ($pr) { $map[$lp] = [string]$pr.ProcessName }
            } catch {}
        }
    } catch {}
    return $map
}

function Get-LoopbackListenOwnerMap {
    if ($null -ne $script:ListenOwnerMap) { return $script:ListenOwnerMap }
    $script:ListenOwnerMap = New-LoopbackListenOwnerMap
    return $script:ListenOwnerMap
}

function Test-LoopbackListenOwnerName {
    param([int]$Port)
    $map = Get-LoopbackListenOwnerMap
    if ($map -and $map.ContainsKey([int]$Port)) { return [string]$map[[int]$Port] }
    return $null
}

function Test-PortOwnerMatchesProduct {
    param([int]$Port)
    $owner = Test-LoopbackListenOwnerName -Port $Port
    if (-not $owner) { return $false }
    $n = $owner.ToLower()
    switch ($Port) {
        11434 { return ($n -like "ollama*") }
        1234 { return ($n -like "lm studio*" -or $n -eq "lm studio") }
        4891 { return ($n -like "gpt4all*" -or $n -eq "chat" -or $n -like "lm studio*") }
        1337 { return ($n -like "jan*") }
        8080 { return ($n -like "llama-server*" -or $n -like "koboldcpp*" -or $n -like "local-ai*" -or $n -like "localai*") }
        5000 { return ($n -like "llama-server*" -or $n -like "koboldcpp*" -or $n -like "local-ai*" -or $n -like "localai*") }
        5001 { return ($n -like "llama-server*" -or $n -like "koboldcpp*" -or $n -like "local-ai*" -or $n -like "localai*") }
        3000 { return ($n -like "llama-server*" -or $n -like "koboldcpp*" -or $n -like "local-ai*" -or $n -like "localai*") }
        default { return $false }
    }
}

function Test-LocalAiPortAllowed {
    param([int]$Port)
    $owner = Test-LoopbackListenOwnerName -Port $Port
    if ($owner -and -not (Test-PortOwnerMatchesProduct -Port $Port)) { return $false }
    switch ($Port) {
        11434 {
            return [bool](Test-PathAny @(
                "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
                "${env:ProgramFiles}\Ollama\ollama.exe"
            )) -or [bool](Get-KnownCommandSource -Name ollama -PathLike @("*\Ollama\*"))
        }
        1234 { return [bool](Test-PathAny @("$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe", "$env:LOCALAPPDATA\LM-Studio\LM Studio.exe")) }
        4891 {
            return [bool](Test-PathAny @(
                "$env:LOCALAPPDATA\Programs\GPT4All\bin\chat.exe",
                "$env:LOCALAPPDATA\Programs\GPT4All\chat.exe",
                "$env:USERPROFILE\gpt4all\bin\chat.exe",
                "$env:USERPROFILE\gpt4all\gpt4all.exe",
                "${env:ProgramFiles}\GPT4All\gpt4all.exe",
                "$env:LOCALAPPDATA\nomic.ai\GPT4All\bin\chat.exe",
                "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe",
                "$env:LOCALAPPDATA\LM-Studio\LM Studio.exe"
            ))
        }
        3080 { return $false }
        8080 { return (Test-LocalLlmServerProcess) }
        5000 { return (Test-LocalLlmServerProcess) }
        5001 { return (Test-LocalLlmServerProcess) }
        3000 { return (Test-LocalLlmServerProcess) }
        1337 {
            return [bool](Test-PathAny @(
                "$env:LOCALAPPDATA\Programs\Jan\Jan.exe",
                "$env:LOCALAPPDATA\Programs\jan\Jan.exe",
                "$env:LOCALAPPDATA\jan\Jan.exe"
            ))
        }
        default { return $false }
    }
}

function Test-LocalLlmServerProcess {
    foreach ($p in @(Get-CachedProcesses)) {
        $n = ""
        $pp = ""
        try { $n = [string]$p.ProcessName } catch {}
        if ($n -notlike "llama-server*" -and $n -notlike "koboldcpp*" -and $n -notlike "local-ai*" -and $n -notlike "localai*") { continue }
        $pp = Get-ProcessImageHint $p
        if (-not $pp) { continue }
        if ($pp -match '(?i)llama-server\.exe|llama\.cpp|koboldcpp|local-ai\.exe|localai\.exe') { return $true }
    }
    return $false
}

function Get-LocalHttpResponse {
    param([string]$Uri)
    if (-not $Uri) { return $null }
    try {
        $u = [Uri]$Uri
        $h = [string]$u.Host
        if ($h -ne "127.0.0.1" -and $h -ne "localhost" -and $h -ne "[::1]" -and $h -ne "::1") { return $null }
        if ($u.Scheme -ne "http" -and $u.Scheme -ne "https") { return $null }
    } catch {
        return $null
    }
    $req = $null
    $resp = $null
    $stream = $null
    $ms = $null
    try {
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.Method = "GET"
        $req.Timeout = 1000
        $req.ReadWriteTimeout = 1000
        $req.AllowAutoRedirect = $false
        $req.Proxy = $null
        $req.UserAgent = "PortableAIScanner"
        $resp = $req.GetResponse()
        $code = 0
        try { $code = [int]$resp.StatusCode } catch {}
        $stream = $resp.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $buf = New-Object byte[] 4096
        $total = 0
        $max = 262144
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $n
            if ($total -gt $max) { return $null }
            $ms.Write($buf, 0, $n)
        }
        $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        return [PSCustomObject]@{ StatusCode = $code; Content = $text }
    } catch {
        return $null
    } finally {
        if ($ms) { try { $ms.Dispose() } catch {} }
        if ($stream) { try { $stream.Close() } catch {} }
        if ($resp) { try { $resp.Close() } catch {} }
    }
}

function Convert-LocalHttpJson {
    param($Response)
    if (-not $Response -or $Response.StatusCode -ne 200) { return $null }
    $c = [string]$Response.Content
    if (-not $c -or $c.Length -gt 262144) { return $null }
    $t = $c.TrimStart()
    if (-not $t) { return $null }
    $ch = $t.Substring(0, 1)
    if ($ch -ne "{" -and $ch -ne "[") { return $null }
    try { return ($c | ConvertFrom-Json) } catch { return $null }
}

function Get-NotepadPackageSetting {
    param([string]$PackageFamilyName)
    if (-not $PackageFamilyName) { return $null }
    try {
        $null = [Windows.Management.Core.ApplicationDataManager, Windows.Management.Core, ContentType = WindowsRuntime]
        $data = [Windows.Management.Core.ApplicationDataManager]::CreateForPackageFamily($PackageFamilyName)
        if (-not $data) { return $null }
        $stores = @()
        try { if ($data.LocalSettings) { $stores += $data.LocalSettings } } catch {}
        try { if ($data.RoamingSettings) { $stores += $data.RoamingSettings } } catch {}
        foreach ($store in $stores) {
            $maps = @()
            try { if ($store.Values) { $maps += $store.Values } } catch {}
            try {
                if ($store.Containers) {
                    foreach ($c in $store.Containers.Values) { if ($c.Values) { $maps += $c.Values } }
                }
            } catch {}
            foreach ($map in $maps) {
                foreach ($name in @("WritingToolsEnabled", "RewriteEnabled")) {
                    $raw = $null
                    try { $raw = $map.Item($name) } catch { $raw = $null }
                    if ($null -eq $raw) { continue }
                    $n = 0
                    if ($raw -is [bool]) { $n = $(if ($raw) { 1 } else { 0 }) }
                    elseif (-not [int]::TryParse([string]$raw, [ref]$n)) { continue }
                    if ($n -eq 0 -or $n -eq 1) {
                        return [PSCustomObject]@{ Name = $name; Value = $n }
                    }
                }
            }
        }
    } catch {}
    return $null
}

function Get-NotepadPackageSwitch {
    param([string]$PackageFamilyName)
    if (-not $PackageFamilyName) { return $null }
    try {
        $null = [Windows.Management.Core.ApplicationDataManager, Windows.Management.Core, ContentType=WindowsRuntime]
    } catch { return $null }
    $data = $null
    try {
        $data = [Windows.Management.Core.ApplicationDataManager]::CreateForPackageFamily($PackageFamilyName)
    } catch { return $null }
    if (-not $data) { return $null }
    $best = $null
    $bestRank = 99
    foreach ($bag in @($data.LocalSettings, $data.RoamingSettings)) {
        if (-not $bag) { continue }
        $vals = $null
        try { $vals = $bag.Values } catch { continue }
        foreach ($name in @("WritingToolsEnabled", "RewriteEnabled")) {
            $raw = $null
            try { $raw = $vals.Item($name) } catch {
                try { $raw = $vals.Lookup($name) } catch { $raw = $null }
            }
            if ($null -eq $raw) { continue }
            $b = -1
            if ($raw -is [bool]) {
                if ($raw) { $b = 1 } else { $b = 0 }
            } elseif ("$raw" -eq "0" -or "$raw" -eq "1") {
                $b = [int]$raw
            }
            if ($b -ne 0 -and $b -ne 1) { continue }
            $thisRank = 2
            if ($name -eq "WritingToolsEnabled") { $thisRank = 1 }
            if ($thisRank -ge $bestRank) { continue }
            $best = [PSCustomObject]@{ Name = $name; Value = $b }
            $bestRank = $thisRank
        }
    }
    return $best
}

function Get-NotepadRewriteSetting {
    param([string]$PackageFamilyName)
    # User switch is in this app's settings.dat. Microsoft does not publish the name.
    # Copy first so an open Notepad does not make the file look unread.
    # A missing byte while Notepad is open is not Unknown. Scan-NotepadAI
    # sets Activated for that case. Do not put Unknown back.
    $paths = @()
    if ($PackageFamilyName) {
        $paths += (Join-Path $env:LOCALAPPDATA "Packages\$PackageFamilyName\Settings\settings.dat")
    }
    $known = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsNotepad_8wekyb3d8bbwe\Settings\settings.dat"
    if ($paths -notcontains $known) { $paths += $known }
    $found = $false
    $last = $null
    foreach ($settingsFile in $paths) {
        if (-not (Test-Path -LiteralPath $settingsFile)) { continue }
        $found = $true
        $tmp = Join-Path $env:TEMP ("pas-notepad-" + [guid]::NewGuid().ToString("n") + ".dat")
        $hit = $null
        try {
            $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            $src = $null
            try {
                $src = [System.IO.File]::Open($settingsFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            } catch {
                $src = [System.IO.File]::Open($settingsFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
            }
            $dst = [System.IO.File]::Create($tmp)
            try { $src.CopyTo($dst) } finally { $dst.Dispose(); if ($src) { $src.Dispose() } }
            $hit = Read-NotepadSettingsDatFile -Path $tmp
        } catch {
            $direct = $null
            $directThrew = $false
            try { $direct = Read-NotepadSettingsDatFile -Path $settingsFile } catch { $directThrew = $true }
            if ($directThrew) {
                $hit = [PSCustomObject]@{ Name = ""; Value = $null; Unread = $true; Locked = $true }
            } else {
                $hit = $direct
            }
        } finally {
            if (Test-Path -LiteralPath $tmp) {
                try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        $hasByte = ($hit -and -not $hit.Unread -and ($hit.Value -eq 0 -or $hit.Value -eq 1))
        if (-not $hasByte -and $PackageFamilyName) {
            $live = Get-NotepadPackageSwitch -PackageFamilyName $PackageFamilyName
            if ($live -and ($live.Value -eq 0 -or $live.Value -eq 1)) { return $live }
        }
        if (-not $hasByte) {
            $win = Get-NotepadPackageSetting -PackageFamilyName $PackageFamilyName
            if ($win) { return $win }
            $dir = Split-Path -Parent $settingsFile
            foreach ($logName in @("settings.dat.LOG1", "settings.dat.LOG2")) {
                $log = Join-Path $dir $logName
                if (-not (Test-Path -LiteralPath $log)) { continue }
                $logHit = $null
                try {
                    $sig = New-Object byte[] 4
                    $lfs = [System.IO.File]::Open($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try { [void]$lfs.Read($sig, 0, 4) } finally { $lfs.Dispose() }
                    $isHive = ($sig[0] -eq 0x72 -and $sig[1] -eq 0x65 -and $sig[2] -eq 0x67 -and $sig[3] -eq 0x66)
                    if ($isHive) { $logHit = Read-NotepadSettingsDatFile -Path $log }
                } catch { $logHit = $null }
                if ($logHit -and -not $logHit.Unread -and -not $logHit.Absent -and ($logHit.Value -eq 0 -or $logHit.Value -eq 1)) {
                    return $logHit
                }
            }
        }
        if ($hit -and -not $hit.Unread -and -not $hit.Absent) { return $hit }
        if ($hit) { $last = $hit }
    }
    if (-not $found) {
        return [PSCustomObject]@{ Name = ""; Value = $null; Missing = $true }
    }
    $live = Get-NotepadPackageSetting -PackageFamilyName $PackageFamilyName
    if ($live) { return $live }
    if ($last) { return $last }
    return [PSCustomObject]@{ Name = ""; Value = $null; Unread = $true }
}

function Get-SystemAiConsent {
    if ($null -ne $script:SystemAiConsentCache) { return $script:SystemAiConsentCache }
    $signals = @()
    $denied = $false
    $allowed = $false
    foreach ($p in @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI"
    )) {
        $v = Get-RegValueSafe -Path $p -Name "Value"
        if ($v) {
            $signals += "Text and image generation Value=$v"
            if ("$v" -eq "Deny") { $denied = $true }
            if ("$v" -eq "Allow") { $allowed = $true }
        }
    }
    $pol = Get-RegValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessSystemAIModels"
    if ($null -eq $pol) {
        $pol = Get-RegValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessGenerativeAI"
    }
    if ($null -ne $pol) {
        $signals += "AppPrivacy LetAppsAccessSystemAIModels/GenerativeAI=$pol"
        try {
            if ([int]$pol -eq 2) { $denied = $true }
            if ([int]$pol -eq 1) { $allowed = $true }
        } catch {}
    }
    $script:SystemAiConsentCache = [PSCustomObject]@{ Denied = $denied; Allowed = $allowed; Signals = $signals }
    return $script:SystemAiConsentCache
}

function Set-ScanStatus {
    param(
        $Result,
        [string]$Status,
        [string]$Reason = ""
    )
    if (-not $Result) { return }
    $Result.Activated = $Status
    if ($Reason) {
        if ($Result.Details) { $Result.Details = "$Reason | $($Result.Details)" }
        else { $Result.Details = $Reason }
    }
}

function New-Result {
    param(
        [string]$Name,
        [bool]$Installed = $false,
        [string]$Activated = "Not Installed",
        [string]$Details = "",
        [string]$Version = "",
        [string]$Running = "",
        [string]$DisableHint = ""
    )
    return [PSCustomObject]@{
        Name = $Name
        Installed = $Installed
        Activated = $Activated
        Details = $Details
        Version = $Version
        Running = $Running
        DisableHint = $DisableHint
    }
}

function Get-HowToDisable {
    param([string]$Name)
    $apps = "Windows Settings > Apps > Installed apps"
    switch -Wildcard ($Name) {
        "Copilot (Microsoft)" { return "$apps > Copilot > Uninstall. Also Settings > Personalization > Taskbar > turn off Copilot." }
        "Microsoft 365 Copilot*" { return "$apps > Microsoft 365 Copilot > Uninstall. In Word, Excel, or PowerPoint: File > Options > Copilot > turn off Enable Copilot." }
        "Notepad*" { return "Open Notepad > gear icon (Settings) > AI Features > turn off Writing tools." }
        "Paint*" { return "Windows Settings > Privacy & security > Text and image generation > turn off Paint if listed. Paint itself has no simple off switch for every AI tool." }
        "Google Chrome + Gemini*" { return "Open Chrome > three-dot menu > Settings > System > turn off On-device AI." }
        "ChatGPT*" { return "$apps > ChatGPT > Uninstall." }
        "Gemini (Google)*" { return "$apps > Gemini > Uninstall." }
        "Claude Code*" { return "$apps > Claude Code if listed > Uninstall. Or delete claude.exe under your user .local\bin folder." }
        "Claude*" { return "$apps > Claude > Uninstall." }
        "Cherry Studio*" { return "$apps > Cherry Studio > Uninstall." }
        "ChatRTX (NVIDIA)*" { return "$apps > ChatRTX or NVIDIA ChatRTX > Uninstall." }
        "G-Assist (NVIDIA)*" { return "Open the NVIDIA App > Discover > G-Assist > Uninstall. Or $apps > NVIDIA App > Modify and remove G-Assist." }
        "LibreChat*" { return "If LibreChat appears in $apps, click Uninstall. If you use Docker Desktop, open Docker Desktop and stop or delete the LibreChat container." }
        "Perplexity" { return "$apps > Perplexity > Uninstall." }
        "Microsoft Edge*" { return "Open Edge > three-dot menu > Settings > Sidebar > turn off Copilot. Then Settings > System and performance > turn off On-device AI if that switch is listed." }
        "Ollama*" { return "$apps > Ollama > Uninstall. That also removes its downloaded models." }
        "LM Studio*" { return "Open LM Studio > My Models > remove models you do not want. Or $apps > LM Studio > Uninstall." }
        "Jan*" { return "Open Jan > Hub / Models > delete models. Or $apps > Jan > Uninstall." }
        "GPT4All*" { return "Open GPT4All > Downloads / Models > remove models. Or $apps > GPT4All > Uninstall." }
        "Cursor*" { return "$apps > Cursor > Uninstall." }
        "Recall (Windows)*" { return "Windows Settings > Privacy & security > Recall & snapshots > turn off Save snapshots. To remove the feature: search Turn Windows features on or off > uncheck Recall > OK > restart." }
        "Click to Do (Windows)*" { return "Windows Settings > Privacy & security > Click to Do > turn it Off." }
        "Agent in Settings (Windows)*" { return (Get-SettingsAgentDisableText) }
        "File Explorer + AI*" { return "Settings > Apps > Actions, then turn off each action. Restart if the menu is still there. Do not edit the registry." }
        "Windows On-Device*" { return "Windows Settings > Privacy & security > Text and image generation > turn the feature off. Settings > System > AI components. Only Image Creation can be removed there if it is listed." }
        "GitHub Copilot*" { return "Open VS Code > Extensions > GitHub Copilot > Disable or Uninstall." }
        "ComfyUI*" { return "$apps > ComfyUI if listed > Uninstall. If it is only a folder app, open Start > right-click the app shortcut > Uninstall." }
        "Opera*" { return "Open Opera > Settings > Sidebar > turn off Aria / Opera AI." }
        "Brave*" { return "Open Brave > Settings > Leo > turn off Leo AI." }
        "Perplexity Comet*" { return "Open Comet > Settings > turn off AI features. Or $apps > Comet > Uninstall." }
        "Mozilla Firefox*" {
            return "Firefox 148+: Settings > AI Controls > turn on Block AI enhancements. Firefox 147: Settings > General > Browsing > turn off Enable link previews. Firefox 136-146: Settings > General > Browsing and Settings > General > Browser Layout > uncheck AI chatbot if listed. Firefox 130-135: Settings > Firefox Labs > turn off AI chatbot. Settings > General > Tabs is smart tab groups, not Labs."
        }
        "Grok*" { return "$apps > Grok > Uninstall if listed. Otherwise use the website only and sign out." }
        "Windsurf*" { return "$apps > Windsurf > Uninstall." }
        "llama.cpp*" { return "If llama.cpp appears in $apps, click Uninstall. If you only have a program file, delete that app shortcut from Start by right-click > Uninstall when Windows offers it." }
        "Llamafile*" { return "If Llamafile appears in $apps, click Uninstall. If you only have llamafile.exe or a .llamafile on the Desktop or in Downloads, delete that file." }
        "LocalAI*" { return "If LocalAI appears in $apps, click Uninstall." }
        "vLLM*" { return "If vLLM appears in $apps, click Uninstall. Otherwise open the Start menu, find the Python app you used, and uninstall that app." }
        "Msty*" { return "$apps > Msty > Uninstall." }
        "KoboldCPP*" { return "If KoboldCPP appears in $apps, click Uninstall. If it is only a downloaded program, right-click it in Start or Downloads and choose Uninstall when Windows offers it." }
        "Open WebUI*" { return "If Open WebUI appears in $apps, click Uninstall. If you use Docker Desktop, open Docker Desktop and stop or delete the Open WebUI container." }
        "AnythingLLM*" { return "$apps > AnythingLLM > Uninstall." }
        "text-generation-webui*" { return "If it appears in $apps, click Uninstall. If it is only a folder app, use Start > right-click the shortcut > Uninstall when offered." }
        "Dolphin*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Other Local Models*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Qwen*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Llama *" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "DeepSeek*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Gemma*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Phi*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Granite*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "GLM*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Mistral*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "gpt-oss*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "GPT-J*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Nemotron*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Muse *" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Kimi*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "MiniMax*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "MiniCPM*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Hunyuan*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Ling *" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Ornith*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "MiMo*" { return "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model." }
        "Foundry Local*" { return "$apps > Foundry Local > Uninstall. Or Settings > System > AI components if listed." }
        default { return "$apps > find this app > Uninstall. If it is a browser feature, open that browser Settings and turn the AI option off." }
    }
}

# Running = Yes whenever the browser or app process is open.
# Red only if Running = Yes and Status is Activated or Model loaded.


function Get-WatchedLoadedModelNote {
    param([string[]]$Loaded)
    $watch = @("promptlock", "prompt-lock", "prompt_lock")
    $hits = @()
    foreach ($n in @($Loaded)) {
        $raw = [string]$n
        if (-not $raw) { continue }
        $leaf = $raw
        if ($raw -match "^([^:/\\]+)") { $leaf = $Matches[1] }
        $leaf = $leaf.Trim().ToLowerInvariant()
        if ($watch -contains $leaf -and $hits -notcontains $raw) { $hits += $raw }
    }
    if ($hits.Count -eq 0) { return $null }
    return "Loaded name matches " + ($hits -join ", ")
}

function Get-OllamaLoadedModels {
    # Returns model names currently loaded in Ollama memory (HTTP /api/ps only). Empty array = none loaded.
    $models = @()

    # 1) Preferred: HTTP API /api/ps (works even if CLI not on PATH)
    try {
        if ((Test-LocalAiPortAllowed 11434) -and (Test-LocalPortOpen -Port 11434)) {
        foreach ($uri in @("http://127.0.0.1:11434/api/ps")) {
            try {
                $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
                $json = Convert-LocalHttpJson $resp
                if (-not $json) { continue }
                if ($json.models) {
                    foreach ($m in $json.models) {
                        $n = $null
                        if ($m.name) { $n = [string]$m.name }
                        elseif ($m.model) { $n = [string]$m.model }
                        if ($n -and $models -notcontains $n) { $models += $n }
                    }
                }
                if ($models.Count -gt 0) { return $models }
            } catch { continue }
        }
        }
    } catch {
        Write-ErrorLog "Ollama /api/ps check failed" -ErrorRecord $_
    }

    return $models
}

function Get-OllamaInstalledTags {
    # Installed (on-disk) Ollama tags via API, not loaded-in-memory
    $tags = @()
    if (-not ((Test-LocalAiPortAllowed 11434) -and (Test-LocalPortOpen -Port 11434))) { return $tags }
    foreach ($uri in @("http://127.0.0.1:11434/api/tags")) {
        try {
            $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
            $json = Convert-LocalHttpJson $resp
            if (-not $json) { continue }
            if ($json.models) {
                foreach ($m in $json.models) {
                    $n = $null
                    if ($m.name) { $n = [string]$m.name }
                    elseif ($m.model) { $n = [string]$m.model }
                    if ($n -and $tags -notcontains $n) { $tags += $n }
                }
            }
            if ($tags.Count -gt 0) { return $tags }
        } catch { continue }
    }
    return $tags
}

function Get-LmStudioLoadedModels {
    # Query LM Studio (and compatible) local OpenAI-style APIs for loaded/served models
    $ids = @()
    $uris = @()
    if ((Test-LocalAiPortAllowed 1234) -and (Test-LocalPortOpen -Port 1234)) {
        $uris += "http://127.0.0.1:1234/v1/models"
        $uris += "http://127.0.0.1:1234/api/v0/models"
    }
    if ((Test-LocalAiPortAllowed 4891) -and (Test-LocalPortOpen -Port 4891)) {
        $uris += "http://127.0.0.1:4891/v1/models"
    }
    foreach ($uri in $uris) {
        try {
            $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
            $json = Convert-LocalHttpJson $resp
            if (-not $json) { continue }
            if ($json.data) {
                foreach ($m in $json.data) {
                    if ($m.id) {
                        $id = [string]$m.id
                        if ($ids -notcontains $id) { $ids += $id }
                    }
                }
            }
            if ($ids.Count -gt 0) { return $ids }
        } catch { continue }
    }
    return $ids
}

function Get-LlamaCppLoadedModels {
    $ids = @()
    if (-not (Test-ProductProcessOpen "llama.cpp")) { return $ids }
    if (-not (Test-LocalPortOpen -Port 8080)) { return $ids }
    foreach ($uri in @("http://127.0.0.1:8080/v1/models", "http://127.0.0.1:8080/api/v1/models")) {
        try {
            $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
            $json = Convert-LocalHttpJson $resp
            if (-not $json) { continue }
            if ($json.data) {
                foreach ($m in $json.data) {
                    if ($m.id) {
                        $id = [string]$m.id
                        if ($ids -notcontains $id) { $ids += $id }
                    }
                }
            }
            if ($ids.Count -gt 0) { return $ids }
        } catch { continue }
    }
    return $ids
}

function Get-LocalAiLoadedModels {
    $ids = @()
    $localAiOpen = $false
    foreach ($p in @(Get-CachedProcesses)) {
        $n = ""
        try { $n = [string]$p.ProcessName } catch {}
        if ($n -like "local-ai*" -or $n -like "localai*") { $localAiOpen = $true; break }
    }
    if (-not $localAiOpen) { return $ids }
    if (Test-ProductProcessOpen "llama.cpp") { return $ids }
    if (-not (Test-LocalPortOpen -Port 8080)) { return $ids }
    foreach ($uri in @("http://127.0.0.1:8080/v1/models", "http://127.0.0.1:8080/api/v1/models")) {
        try {
            $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
            $json = Convert-LocalHttpJson $resp
            if (-not $json) { continue }
            if ($json.data) {
                foreach ($m in $json.data) {
                    if ($m.id) {
                        $id = [string]$m.id
                        if ($ids -notcontains $id) { $ids += $id }
                    }
                }
            }
            if ($ids.Count -gt 0) { return $ids }
        } catch { continue }
    }
    return $ids
}

function Get-KoboldCppLoadedModels {
    $ids = @()
    if (-not (Test-ProductProcessOpen "KoboldCPP")) { return $ids }
    $ports = @(5001, 5000)
    if (-not (Test-ProductProcessOpen "llama.cpp")) { $ports += 8080 }
    foreach ($port in $ports) {
        if (-not (Test-LocalPortOpen -Port $port)) { continue }
        foreach ($uri in @("http://127.0.0.1:$port/v1/models", "http://127.0.0.1:$port/api/v1/models")) {
            try {
                $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
                $json = Convert-LocalHttpJson $resp
                if (-not $json) { continue }
                if ($json.data) {
                    foreach ($m in $json.data) {
                        if ($m.id) {
                            $id = [string]$m.id
                            if ($ids -notcontains $id) { $ids += $id }
                        }
                    }
                }
                if ($ids.Count -gt 0) { return $ids }
            } catch { continue }
        }
    }
    return $ids
}

function Get-OpenAiCompatLoadedModels {
    # Generic OpenAI-compatible servers often used with local models (llama.cpp, kobold, etc.)
    $ids = @()
    $portMap = @{
        8080 = @("http://127.0.0.1:8080/v1/models", "http://127.0.0.1:8080/api/v1/models")
        5001 = @("http://127.0.0.1:5001/v1/models")
        5000 = @("http://127.0.0.1:5000/v1/models")
        3000 = @("http://127.0.0.1:3000/v1/models")
        1337 = @("http://127.0.0.1:1337/v1/models")
        4891 = @("http://127.0.0.1:4891/v1/models")
    }
    $uris = @()
    $skip8080 = (Test-ProductProcessOpen "llama.cpp") -or (Test-ProductProcessOpen "LocalAI")
    foreach ($p in $portMap.Keys) {
        if ($p -eq 8080 -and $skip8080) { continue }
        if ((Test-LocalAiPortAllowed $p) -and (Test-LocalPortOpen -Port $p)) { $uris += $portMap[$p] }
    }
    foreach ($uri in $uris) {
        try {
            $resp = Get-LocalHttpResponse -Uri $uri
                if (-not $resp) { continue }
            $json = Convert-LocalHttpJson $resp
            if (-not $json) { continue }
            if ($json.data) {
                foreach ($m in $json.data) {
                    if ($m.id) {
                        $id = [string]$m.id
                        if ($ids -notcontains $id) { $ids += $id }
                    }
                }
            }
        } catch { continue }
    }
    return $ids
}

function Get-LoadedModelsMatching {
    param(
        [string[]]$Loaded,
        [string[]]$Patterns,
        [string]$FamilyName = ""
    )
    if (-not $Loaded -or $Loaded.Count -eq 0) { return @() }
    $matched = @()
    foreach ($m in $Loaded) {
        if ($FamilyName -and $script:ClaimedModelNames -and $script:ClaimedModelNames.ContainsKey($m)) {
            $owner = [string]$script:ClaimedModelNames[$m]
            if ($owner -and $owner -ne $FamilyName) { continue }
        }
        if ($FamilyName -like "Qwen*" -or $FamilyName -like "Llama*" -or $FamilyName -like "Mistral*" -or $FamilyName -like "Phi*" -or $FamilyName -like "Gemma*") {
            if ($m -match '(?i)deepseek|(?i)r1-distill|(?i)r1_distill|(?i)dolphin') { continue }
        }
        if ($FamilyName -like "Llama*") {
            if ($m -match '(?i)nemotron') { continue }
        }
        foreach ($p in $Patterns) {
            if ($m -match $p) {
                $matched += $m
                break
            }
        }
    }
    return $matched
}

function Get-KnownFamilyPatterns {
    return @(
        '(?i)qwen',
        '(?i)meta-llama',
        '(?i)llama-?[2345]',
        '(?i)llama[2345]',
        '(?i)llama-?4.*scout',
        '(?i)llama-?4.*maverick',
        '(?i)dolphin',
        '(?i)deepseek',
        '(?i)r1-distill',
        '(?i)r1_distill',
        '(?i)ds-r1',
        '(?i)ds-v3',
        '(?i)ds-v4',
        '(?i)gemma',
        '(?i)medgemma',
        '(?i)functiongemma',
        '(?i)translategemma',
        '(?i)phi-?[0-9]',
        '(?i)phi[345]',
        '(?i)phi-mini',
        '(?i)glm',
        '(?i)chatglm',
        '(?i)mistral',
        '(?i)mixtral',
        '(?i)devstral',
        '(?i)magistral',
        '(?i)ministral',
        '(?i)pixtral',
        '(?i)voyage',
        '(?i)gpt-oss',
        '(?i)gpt_oss',
        '(?i)gptoss',
        '(?i)gpt-?j',
        '(?i)gptj',
        '(?i)pygmalion',
        '(?i)nvidia-?nemotron',
        '(?i)nemotron',
        '(?i)muse-?glimmer',
        '(?i)muse-?spark',
        '(?i)kimi',
        '(?i)granite',
        '(?i)ibm-granite',
        '(?i)minimax',
        '(?i)minicpm',
        '(?i)hunyuan',
        '(?i)ling-?3',
        '(?i)ornith',
                '(?i)mimo-v2\.6',
        '(?i)mimo-v2\.5',
        '(?i)mimo-v2',
        '(?i)mimo_v2',
        '(?i)xiaomi-mimo',
        '(?i)xiaomi_mimo'
    )
}

function Get-UnclaimedLoadedModels {
    param([string[]]$Loaded)
    if (-not $Loaded -or $Loaded.Count -eq 0) { return @() }
    $claimed = Get-LoadedModelsMatching -Loaded $Loaded -Patterns @(Get-KnownFamilyPatterns)
    $left = @()
    foreach ($m in $Loaded) {
        if ($claimed -notcontains $m) { $left += $m }
    }
    return $left
}


function Get-CachedProcesses {
    if ($null -eq $script:ProcSnap) {
        try { $script:ProcSnap = @(Get-Process -ErrorAction SilentlyContinue) } catch { $script:ProcSnap = @() }
    }
    return @($script:ProcSnap)
}

function Test-CachedProcessName {
    param([string]$Name)
    if (-not $Name) { return $false }
    foreach ($p in @(Get-CachedProcesses)) {
        try {
            if ($p.ProcessName -like $Name) { return $true }
        } catch {}
    }
    return $false
}

function Test-ProductProcessOpen {
    param([string]$Name)
    if (-not $Name) { return $false }
    # Product-exe helper only. Browser rows use Test-BrowserProcessOpen.
    if ($Name -like "Google Chrome + Gemini*") { return $false }
    if ($Name -like "Microsoft Edge*") { return $false }
    if ($Name -like "Mozilla Firefox*") { return $false }
    if ($Name -like "Opera*") { return $false }
    if ($Name -like "Brave*") { return $false }
    if ($Name -like "Perplexity Comet*") { return $false }
    if ($Name -like "Gemini (Google)*") {
        return (Test-OfficialGeminiProcessOpen)
    }

    $patterns = @()
    switch -Wildcard ($Name) {
        "ChatGPT*" { $patterns = @("ChatGPT") }
        "Claude Code*" { $patterns = @("claude") }
        "Claude*" { $patterns = @("Claude") }
        "Gemini (Google)*" { $patterns = @() }
        "Recall (Windows)*" { $patterns = @("Recall") }
        "Click to Do (Windows)*" { $patterns = @("ClickToDo", "ClickToDoExperience") }
        "Copilot (Microsoft)" { $patterns = @("Copilot") }
        "Microsoft 365 Copilot*" { $patterns = @("Microsoft365Copilot") }
        "Grok*" { $patterns = @("Grok") }
        "Ollama*" { $patterns = @("ollama") }
        "Perplexity" { $patterns = @("Perplexity") }
        "LM Studio*" { $patterns = @("LM Studio") }
        "GPT4All*" { $patterns = @("gpt4all","GPT4All") }
        "Jan*" { $patterns = @("Jan") }
        "Cherry Studio*" { $patterns = @("Cherry Studio") }
        "LibreChat*" { $patterns = @() }
        "ChatRTX (NVIDIA)*" { $patterns = @("ChatRTX") }
        "G-Assist (NVIDIA)*" { $patterns = @() }
        "Nemotron*" { $patterns = @() }
        "Cursor*" { $patterns = @("Cursor") }
        "Windsurf*" { $patterns = @("Windsurf") }
        "Msty*" { $patterns = @("Msty") }
        "ComfyUI*" { $patterns = @("python", "ComfyUI", "comfyui") }
        "Foundry Local*" { $patterns = @("foundry", "FoundryLocal") }
        "GitHub Copilot*" { $patterns = @() }
        "llama.cpp*" { $patterns = @("llama-server","llama-cli") }
        "Llamafile*" { $patterns = @("llamafile") }
        "LocalAI*" { $patterns = @("local-ai","localai") }
        "KoboldCPP*" { $patterns = @("koboldcpp") }
        "AnythingLLM*" { $patterns = @("AnythingLLM") }
        "Open WebUI*" { $patterns = @() }
        default { $patterns = @() }
    }
    $needPath = ($Name -like "Jan*" -or $Name -like "Claude*" -or $Name -like "Foundry Local*" -or $Name -like "ComfyUI*" -or $Name -like "Cursor*" -or $Name -eq "Copilot (Microsoft)" -or $Name -like "Microsoft 365 Copilot*" -or $Name -like "ChatRTX*" -or $Name -like "ChatGPT*" -or $Name -like "Grok*" -or $Name -like "Ollama*" -or $Name -eq "Perplexity" -or $Name -like "LM Studio*" -or $Name -like "AnythingLLM*" -or $Name -like "Windsurf*" -or $Name -like "Msty*" -or $Name -like "GPT4All*" -or $Name -like "llama.cpp*" -or $Name -like "Llamafile*" -or $Name -like "LocalAI*" -or $Name -like "KoboldCPP*" -or $Name -like "Cherry Studio*")
    foreach ($pat in $patterns) {
        if (-not $pat) { continue }
        try {
            $proc = @(Get-CachedProcesses) | Where-Object { $_.ProcessName -like $pat }
            if ($proc) {
                if ($Name -like "Gemini (Google)*") {
                    $ok = $false
                    foreach ($pr in @($proc)) {
                        $pp = Get-ProcessImageHint $pr
                        if ($pp -match '(?i)\\Google\\Gemini\\') { $ok = $true }
                    }
                    if ($ok) { return $true }
                } elseif ($needPath) {
                    if (Test-ProcessPathMatchesProduct -Name $Name -Processes $proc) { return $true }
                } else {
                    return $true
                }
            }
        } catch {}
        if ($needPath) { continue }
        try {
            $proc = @(Get-CachedProcesses) | Where-Object { $_.ProcessName -like $pat -or $_.ProcessName -like ($pat + "*") }
            if ($proc) { return $true }
        } catch {}
    }
    return $false
}

function Get-ProcessImageHint {
    param($Process)
    if (-not $Process) { return "" }
    $pp = ""
    try { $pp = [string]$Process.Path } catch {}
    if ($pp) { return $pp }
    $id = 0
    try { $id = [int]$Process.Id } catch { return "" }
    if ($id -le 0) { return "" }
    if (-not $script:ProcImageHint) { $script:ProcImageHint = @{} }
    if ($script:ProcImageHint.ContainsKey($id)) { return [string]$script:ProcImageHint[$id] }
    $hint = ""
    try {
        $cim = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop
        if ($cim.ExecutablePath) { $hint = [string]$cim.ExecutablePath }
        elseif ($cim.CommandLine) { $hint = [string]$cim.CommandLine }
    } catch {}
    $script:ProcImageHint[$id] = $hint
    return $hint
}

function Test-ProcessPathMatchesProduct {
    param([string]$Name, $Processes)
    foreach ($pr in @($Processes)) {
        $pp = Get-ProcessImageHint $pr
        if (-not $pp) { continue }
        if ($Name -like "Jan*") {
            if ($pp -match '(?i)\\Jan\\' -or $pp -match '(?i)\\jan\\Jan\.exe$') { return $true }
        } elseif ($Name -like "Claude Code*") {
            if ($pp -match '(?i)\\\.claude\\' -or $pp -match '(?i)Anthropic' -or $pp -match '(?i)Claude Code' -or $pp -match '(?i)\\\.local\\bin\\claude\.exe$') { return $true }
        } elseif ($Name -like "Claude*") {
            if ($pp -match '(?i)\\Claude\\' -or $pp -match '(?i)\\AnthropicClaude\\' -or $pp -match '(?i)Anthropic\.Claude') { return $true }
        } elseif ($Name -like "Foundry Local*") {
            if ($pp -match '(?i)FoundryLocal' -or $pp -match '(?i)Foundry Local' -or $pp -match '(?i)Microsoft Foundry') { return $true }
        } elseif ($Name -like "ComfyUI*") {
            if ($pp -match '(?i)\\ComfyUI\\' -or $pp -match '(?i)ComfyUI\.exe$') { return $true }
        } elseif ($Name -like "Cursor*") {
            if ($pp -match '(?i)Cursor Hero|(?i)Mouse Without Borders|(?i)\\Mouse\\') { continue }
            if ($pp -match '(?i)\\Cursor\\Cursor\.exe$' -or $pp -match '(?i)\\Programs\\[Cc]ursor\\') { return $true }
        } elseif ($Name -eq "Copilot (Microsoft)") {
            if ($pp -match '(?i)Microsoft\.Copilot|(?i)\\WindowsApps\\.*Copilot|(?i)\\Copilot\\Copilot\.exe$') { return $true }
        } elseif ($Name -like "Microsoft 365 Copilot*") {
            if ($pp -match '(?i)WINWORD\.EXE$|(?i)EXCEL\.EXE$|(?i)POWERPNT\.EXE$|(?i)OUTLOOK\.EXE$|(?i)ONENOTE\.EXE$') { continue }
            if ($pp -match '(?i)Microsoft\.Copilot') { continue }
            if ($pp -match '(?i)Microsoft365Copilot|(?i)Microsoft\.Microsoft365Copilot|(?i)\\WindowsApps\\.*365.*Copilot') { return $true }
        } elseif ($Name -like "ChatRTX*") {
            if ($pp -match '(?i)NVIDIA App|(?i)NVIDIA GeForce|(?i)\\NVIDIA Overlay\\') { continue }
            if ($pp -match '(?i)\\NVIDIA\\ChatRTX\\|(?i)\\NVIDIA\\ChatWithRTX\\') { return $true }
        } elseif ($Name -like "ChatGPT*") {
            if ($pp -match '(?i)OpenAI\.ChatGPT|(?i)\\WindowsApps\\.*ChatGPT|(?i)\\ChatGPT\\ChatGPT\.exe$') { return $true }
        } elseif ($Name -like "Grok*") {
            if ($pp -match '(?i)\\Grok\\Grok\.exe$' -or $pp -match '(?i)\\WindowsApps\\.*Grok|(?i)\\xAI\\') { return $true }
        } elseif ($Name -like "Ollama*") {
            if ($pp -match '(?i)\\Ollama\\ollama\.exe$' -or $pp -match '(?i)\\Ollama\\') { return $true }
        } elseif ($Name -eq "Perplexity") {
            if ($pp -match '(?i)\\Perplexity\\Perplexity\.exe$' -or $pp -match '(?i)\\Perplexity\\') { return $true }
        } elseif ($Name -like "LM Studio*") {
            if ($pp -match '(?i)LM Studio\.exe$' -or $pp -match '(?i)\\LM[- ]Studio\\') { return $true }
        } elseif ($Name -like "AnythingLLM*") {
            if ($pp -match '(?i)\\AnythingLLM\\' -or $pp -match '(?i)AnythingLLM\.exe$' -or $pp -match '(?i)anythingllm-desktop') { return $true }
        } elseif ($Name -like "Windsurf*") {
            if ($pp -match '(?i)\\Windsurf\\Windsurf\.exe$' -or $pp -match '(?i)\\Programs\\Windsurf\\') { return $true }
        } elseif ($Name -like "Msty*") {
            if ($pp -match '(?i)\\Msty\\Msty\.exe$' -or $pp -match '(?i)\\Programs\\[Mm]sty\\') { return $true }
        } elseif ($Name -like "Cherry Studio*") {
            if ($pp -match '(?i)\\Cherry Studio\\' -or $pp -match '(?i)\\CherryStudio\\' -or $pp -match '(?i)Cherry Studio\.exe$' -or $pp -match '(?i)CherryStudio\.exe$') { return $true }
        } elseif ($Name -like "GPT4All*") {
            if ($pp -match '(?i)\\GPT4All\\' -or $pp -match '(?i)\\gpt4all\\' -or $pp -match '(?i)nomic\.ai\\GPT4All' -or $pp -match '(?i)gpt4all\.exe$') { return $true }
        } elseif ($Name -like "llama.cpp*") {
            if ($pp -match '(?i)\\llama\.cpp\\' -or $pp -match '(?i)\\llamacpp\\' -or $pp -match '(?i)llama-server\.exe$' -or $pp -match '(?i)llama-cli\.exe$') { return $true }
        } elseif ($Name -like "Llamafile*") {
            if ($pp -match '(?i)\\llamafile\\' -or $pp -match '(?i)llamafile\.exe$' -or $pp -match '(?i)\.llamafile$') { return $true }
        } elseif ($Name -like "LocalAI*") {
            if ($pp -match '(?i)\\LocalAI\\' -or $pp -match '(?i)\\local-ai\\' -or $pp -match '(?i)local-ai\.exe$' -or $pp -match '(?i)localai\.exe$') { return $true }
        } elseif ($Name -like "KoboldCPP*") {
            if ($pp -match '(?i)\\[Kk]oboldcpp\\' -or $pp -match '(?i)koboldcpp.*\.exe$') { return $true }
        }
    }
    return $false
}

function Test-BrowserProcessOpen {
    param([string]$Name)
    $procName = $null
    switch -Wildcard ($Name) {
        "Google Chrome + Gemini*" { $procName = "chrome" }
        "Microsoft Edge*" { $procName = "msedge" }
        "Mozilla Firefox*" { $procName = "firefox" }
        "Brave*" { $procName = "brave" }
        "Opera*" { $procName = "opera" }
        "Perplexity Comet*" { $procName = "comet" }
        "Notepad*" { $procName = "notepad" }
        "Paint*" { $procName = "mspaint" }
        default { return $false }
    }
    try {
        if (Test-CachedProcessName $procName) { return $true }
    } catch {}
    return $false
}

function Set-RunningAndStatus {
    param($Result, [string]$ModelRunning)
    if (-not $Result) { return $Result }
    $st = [string]$Result.Activated
    $keepOff = @("Deactivated", "Unknown", "Not Installed", "No AI Features")

    if ($Result.Name -like "Windows On-Device*") {
        $Result.Running = "No"
        return $Result
    }

    if ((Test-IsBrowserAiRow $Result.Name) -or (Test-IsHostOptionalAiRow $Result.Name)) {
        # Browsers: process name even if Installed is No (portable / unzip copy).
        # Notepad/Paint still require Installed so a random notepad.exe is ignored.
        $checkProc = $Result.Installed -or (Test-IsBrowserAiRow $Result.Name)
        $browserOpen = $false
        if ($checkProc) { $browserOpen = Test-BrowserProcessOpen $Result.Name }
        $Result.Running = $(if ($browserOpen) { "Yes" } else { "No" })
        if ($browserOpen -and -not $Result.Installed) {
            $Result.Activated = "Unknown"
            $note = "Process is running; no install path found"
            if ([string]$Result.Details -notmatch 'no install path found') {
                if ($Result.Details) { $Result.Details = [string]$Result.Details + " | " + $note }
                else { $Result.Details = $note }
            }
        }
        return $Result
    }

    $modelYes = ($ModelRunning -like "Yes*")
    $procYes = $false
    if ($Result.Installed) {
        $procYes = Test-ProductProcessOpen -Name $Result.Name
    }
    if ($modelYes) {
        $Result.Running = $ModelRunning
        $Result.Installed = $true
        if ($keepOff -notcontains $st) { $Result.Activated = "Model loaded" }
    } elseif ($procYes) {
        $Result.Running = "Yes"
    } else {
        $Result.Running = "No"
        if ($Result.Installed -and $st -eq "Model loaded") {
            $Result.Activated = "Installed"
        }
    }
    return $Result
}



function Test-IsHostOptionalAiRow {
    param([string]$Name)
    return ($Name -like "Notepad*" -or $Name -like "Paint*")
}

function Test-IsBrowserAiRow {
    param([string]$Name)
    return ($Name -like "Google Chrome + Gemini*" -or $Name -like "Microsoft Edge*" -or $Name -like "Mozilla Firefox*" -or $Name -like "Brave + Leo*" -or $Name -like "Opera + Aria*" -or $Name -like "Perplexity Comet*")
}

function Test-IsRunning {
    param(
        [string]$AiName,
        [string[]]$OllamaLoadedModels = $null,
        [string[]]$LmStudioLoadedModels = $null,
        [string[]]$CompatLoadedModels = $null
    )

    # Model-in-memory helper for desktop/local rows.
    # Does not set the Running column for browsers or host apps.
    # Set-RunningAndStatus sets Running from the open process.

    $allLoaded = @()
    if ($OllamaLoadedModels) { $allLoaded += $OllamaLoadedModels }
    if ($LmStudioLoadedModels) { $allLoaded += $LmStudioLoadedModels }
    if ($CompatLoadedModels) { $allLoaded += $CompatLoadedModels }
    $allLoaded = @($allLoaded | Select-Object -Unique)

    function Format-Yes([string[]]$list) {
        if (-not $list -or $list.Count -eq 0) { return "No" }
        if ($list.Count -eq 1) { return "Yes ($($list[0]))" }
        if ($list.Count -eq 2) { return "Yes ($($list[0]), $($list[1]))" }
        return "Yes ($($list.Count) models: $($list[0]), ...)"
    }

    switch -Wildcard ($AiName) {
        "Ollama" {
            return (Format-Yes $OllamaLoadedModels)
        }
        "LM Studio" {
            return (Format-Yes $LmStudioLoadedModels)
        }
        "llama.cpp*" {
            if (-not (Test-ProductProcessOpen "llama.cpp")) { return "No" }
            $llamaIds = @(Get-LlamaCppLoadedModels)
            if ($llamaIds.Count -gt 0) { return (Format-Yes $llamaIds) }
            return "No"
        }
        "Other Local Models*" {
            return (Format-Yes (Get-UnclaimedLoadedModels $allLoaded))
        }
        "Dolphin*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @(
                '(?i)dolphin',
                '(?i)dolphincoder'
            )))
        }
        "Qwen*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)qwen')))
        }
        "Llama 3*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @(
                '(?i)meta-llama',
                '(?i)llama-?[345]',
                '(?i)llama3',
                '(?i)llama2',
                '(?i)llama-?2',
                '(?i)llama-?4.*scout',
                '(?i)llama-?4.*maverick'
            )))
        }
        "DeepSeek*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @(
                '(?i)deepseek', '(?i)r1-distill', '(?i)r1_distill', '(?i)ds-r1', '(?i)ds-v3', '(?i)ds-v4'
            )))
        }
        "Gemma*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)gemma', '(?i)medgemma', '(?i)functiongemma', '(?i)translategemma')))
        }
        "Phi*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)phi-?[0-9]', '(?i)phi4', '(?i)phi5', '(?i)phi-mini')))
        }
        "GLM*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)glm', '(?i)chatglm')))
        }
        "Mistral*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)mistral', '(?i)mixtral', '(?i)devstral', '(?i)magistral', '(?i)ministral', '(?i)pixtral', '(?i)voyage')))
        }
        "gpt-oss*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)gpt-oss', '(?i)gpt_oss', '(?i)gptoss')))
        }
        "GPT-J*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)gpt-?j', '(?i)gptj', '(?i)pygmalion')))
        }
        "Nemotron*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @(
                '(?i)nvidia-?nemotron',
                '(?i)llama-3\.[13]-nemotron',
                '(?i)nemotron-?[0-9]',
                '(?i)nemotron-(mini|nano|super|ultra|lightning)',
                '(?i)nemotron'
            )))
        }
        "Muse *" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)muse-?glimmer', '(?i)muse_glimmer', '(?i)museglimmer', '(?i)muse-?spark', '(?i)spark-1\.[123]')))
        }
        "Kimi*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)kimi', '(?i)moonshot-kimi')))
        }
        "Granite*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)granite', '(?i)ibm-granite')))
        }
        "MiniMax*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)minimax')))
        }
        "MiniCPM*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)minicpm')))
        }
        "Hunyuan*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)hunyuan')))
        }
        "Ling *" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)ling-?3', '(?i)inclusionai-ling')))
        }
        "Ornith*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @('(?i)ornith-1\.5', '(?i)ornith-1', '(?i)ornith')))
        }
        "MiMo*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -FamilyName $AiName -Patterns @(
                '(?i)mimo-v2\.6',
                '(?i)mimo-v2\.5',
                '(?i)mimo-v2',
                '(?i)mimo_v2',
                '(?i)xiaomi-mimo',
                '(?i)xiaomi_mimo'
            )))
        }
        default {
            return "No"
        }
    }
}


# ========== Scanners ==========

function Scan-Copilot {
    # Present and not policy-off is Activated. Policy off is Deactivated.
    # Open Copilot window + Activated = Red. Other Major Apps stay Installed.
    $r = New-Result "Copilot (Microsoft)"
    $r.DisableHint = "Windows Settings > Apps > Installed apps > Copilot > Uninstall. Then Settings > Personalization > Taskbar > turn off Copilot if the button is still there."

    $pkgs = Get-AppxByName "Microsoft.Copilot*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "MicrosoftWindows.Copilot*" }
    $other = Get-AppxByName "*Copilot*"
    $userPkgs = @()
    foreach ($p in @($pkgs)) {
        if (-not $p) { continue }
        $n = [string]$p.Name
        if ($n -like "Microsoft.Copilot*" -or $n -like "MicrosoftWindows.Copilot*") { $userPkgs += $p }
    }
    if ($userPkgs.Count -gt 0) {
        $pkg = $userPkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "App: $($pkg.Name)"
    }

    $leftover = @()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\WindowsUdk.UI.Shell.WindowsCopilot") {
        $leftover += "WindowsCopilot activatable class"
    }
    if (Test-Path "HKCR:\ms-copilot") {
        $leftover += "ms-copilot protocol"
    }
    $otherNames = @()
    foreach ($p in @($other)) {
        if (-not $p) { continue }
        $n = [string]$p.Name
        if ($n -like "Microsoft.Copilot*" -or $n -like "MicrosoftWindows.Copilot*") { continue }
        if ($n -like "*365*Copilot*" -or $n -like "*Office*") { continue }
        $otherNames += $n
    }
    if ($otherNames.Count -gt 0) { $leftover += "Other Copilot-named packages: " + (($otherNames | Select-Object -Unique) -join ", ") }

    if ($r.Installed) {
        $turnedOff = $false
        foreach ($rp in @("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
            $val = Get-ItemProperty -Path $rp -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
            if ($val -and $val.TurnOffWindowsCopilot -eq 1) { $turnedOff = $true }
        }
        if ($turnedOff) {
            Set-ScanStatus $r "Deactivated"
            $r.DisableHint = "Controlled by your administrator."
            $r.Details = "AI off | turned off by policy | App: $($pkg.Name)"
        } else {
            Set-ScanStatus $r "Activated"
            $r.Details = "AI on | App: $($pkg.Name)"
        }
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.DisableHint = ""
        if ($leftover.Count -gt 0) {
            $r.Details = "Leftover folder; no app: " + ($leftover -join "; ")
        } else {
            $r.Details = "No Copilot app found"
        }
    }
    return $r
}

function Scan-M365Copilot {
    # Toggle on = Activated. Toggle unread = Unknown. Policy off = Deactivated.
    $r = New-Result "Microsoft 365 Copilot"
    $pkgs = Get-AppxByName "*Microsoft365Copilot*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "*Copilot*Office*" }

    $officeExe = Test-PathAny @(
        "${env:ProgramFiles}\Microsoft Office\root\Office16\WINWORD.EXE",
        "${env:ProgramFiles}\Microsoft Office\Office16\WINWORD.EXE",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\WINWORD.EXE"
    )

    if ($pkgs) {
        $pkg = $pkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "App: $($pkg.Name)"
        if ($officeExe) { $r.Details += " | Office desktop present" }
        $policyOff = $false
        $userOff = $false
        $on = $false
        $seen = $false
        foreach ($op in @(
            "HKCU:\Software\Policies\Microsoft\Office\16.0\Common\OfficeAI",
            "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeAI"
        )) {
            $dis = Get-RegValueSafe -Path $op -Name "DisableOfficeCopilot"
            $en = Get-RegValueSafe -Path $op -Name "EnableCopilot"
            if ($null -ne $dis) {
                $seen = $true
                if ("$dis" -eq "1") { $policyOff = $true }
            }
            if ($null -ne $en) {
                $seen = $true
                if ("$en" -eq "0") { $policyOff = $true }
                elseif ("$en" -eq "1") { $on = $true }
            }
        }
        $userPath = "HKCU:\Software\Microsoft\Office\16.0\Common\OfficeAI"
        $dis = Get-RegValueSafe -Path $userPath -Name "DisableOfficeCopilot"
        $en = Get-RegValueSafe -Path $userPath -Name "EnableCopilot"
        if ($null -ne $dis) {
            $seen = $true
            if ("$dis" -eq "1") { $userOff = $true }
            elseif ("$dis" -eq "0") { $on = $true }
        }
        if ($null -ne $en) {
            $seen = $true
            if ("$en" -eq "0") { $userOff = $true }
            elseif ("$en" -eq "1") { $on = $true }
        }
        $userHow = "Windows Settings > Apps > Installed apps > Microsoft 365 Copilot > Uninstall. In Word, Excel, or PowerPoint: File > Options > Copilot > turn off Enable Copilot."
        $appBit = [string]$r.Details
        if ($policyOff) {
            Set-ScanStatus $r "Deactivated"
            $r.Details = "AI off | turned off by policy | $appBit"
            $r.DisableHint = "Controlled by your administrator."
        } elseif ($userOff) {
            Set-ScanStatus $r "Deactivated"
            $r.Details = "AI off | $appBit"
            $r.DisableHint = $userHow
        } elseif ($on) {
            Set-ScanStatus $r "Activated"
            $r.Details = "AI on | $appBit"
            $r.DisableHint = $userHow
        } else {
            Set-ScanStatus $r "Unknown"
            $r.Details = "Could not read settings | $appBit"
            $r.DisableHint = $userHow
        }
    } elseif ($officeExe) {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Microsoft 365 Copilot app found"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Microsoft 365 Copilot app found"
    }
    return $r
}

function Scan-NotepadAI {
    $r = New-Result "Notepad + AI"
    $pkgs = Get-AppxByName "Microsoft.WindowsNotepad*"
    if (-not $pkgs) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Notepad app found"
        return $r
    }
    $pkg = $pkgs | Select-Object -First 1
    $r.Installed = $true
    $r.Version = $pkg.Version
    $hints = @("App: $($pkg.Name)")

    # Official off switch: HKLM\SOFTWARE\Policies\WindowsNotepad DisableAIFeatures=1
    # (Microsoft Learn, Notepad 11.2503.16.0+). Microsoft does not publish
    # the in-app Writing tools value. Do not use EnableCopilot or Text and
    # image generation as Status.
    # Do not mark Unknown when Notepad is running and the saved switch was
    # not read. An open Notepad holds that app hive, so the file can miss
    # the on or off byte. That case is Activated, and Details must say the
    # saved switch was not read. Policy off and a saved 0 or 1 still win.
    # Unknown is only when Notepad is closed and the byte still cannot be read.
    $pol = Get-RegValueSafe -Path "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures"
    $family = ""
    try { $family = [string]$pkg.PackageFamilyName } catch {}
    $rewrite = Get-NotepadRewriteSetting -PackageFamilyName $family
    $userHow = "Open Notepad > gear icon (Settings) > AI Features > turn off Writing tools."
    $adminHow = "Controlled by your administrator."
    $adminOff = ($null -ne $pol -and [int]$pol -eq 1)
    $tooOld = $false
    try {
        if ($r.Version -and ([version]$r.Version) -lt ([version]"11.2503.16.0")) { $tooOld = $true }
    } catch {}
    if ($tooOld) {
        Set-ScanStatus $r "No AI Features"
        $hints += "Notepad $($r.Version) has no AI features"
        $r.Details = $hints -join " | "
        return $r
    }
    $fileUnread = ($rewrite -and $rewrite.Unread)
    $fileOff = ($rewrite -and -not $fileUnread -and ("$($rewrite.Value)" -eq "0"))
    $fileOn = ($rewrite -and -not $fileUnread -and ("$($rewrite.Value)" -eq "1"))

    if ($adminOff) {
        Set-ScanStatus $r "Deactivated"
        $hints += "Disabled by policy"
        $r.DisableHint = $adminHow
    } elseif ($fileOff) {
        Set-ScanStatus $r "Deactivated"
        $hints += "AI writing tools off"
        $r.DisableHint = $userHow
    } elseif ($fileOn) {
        Set-ScanStatus $r "Activated"
        $hints += "AI writing tools on"
        $r.DisableHint = $userHow
    } elseif ($fileUnread) {
        $notepadOpen = $false
        try { if (Get-Process -Name "Notepad" -ErrorAction SilentlyContinue) { $notepadOpen = $true } } catch {}
        if ($notepadOpen) {
            Set-ScanStatus $r "Activated"
            $hints += "Notepad is open and the saved switch was not read"
            $r.DisableHint = $userHow
        } else {
            Set-ScanStatus $r "Unknown"
            $hints += "Writing tools switch was not read from settings.dat"
            $r.DisableHint = $userHow
        }
    } else {
        Set-ScanStatus $r "Activated"
        $hints += "Switch never saved; Microsoft default is on"
        $r.DisableHint = $userHow
    }
    $r.Details = $hints -join " | "
    return $r
}

function Scan-PaintAI {
    $r = New-Result "Paint + AI"
    $pkgs = Get-AppxByName "Microsoft.Paint*"
    if (-not $pkgs) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Paint app found"
        return $r
    }
    $pkg = $pkgs | Select-Object -First 1
    $r.Installed = $true
    $r.Version = $pkg.Version
    $hints = @("App: $($pkg.Name)")
    $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
    $names = @("DisableCocreator", "DisableGenerativeFill", "DisableImageCreator", "DisableGenerativeErase", "DisableRemoveBackground")
    $disabled = @()
    $enabledMissing = @()
    foreach ($n in $names) {
        $v = Get-RegValueSafe -Path $policyPath -Name $n
        if ($null -ne $v -and [int]$v -eq 1) { $disabled += $n }
        else { $enabledMissing += $n }
    }
    $privacyHow = "Windows Settings > Privacy & security > Text and image generation > turn off Paint if listed. Paint itself has no simple off switch for every AI tool."
    $adminHow = "Controlled by your administrator."
    $consent = Get-SystemAiConsent
    if ($disabled.Count -eq $names.Count) {
        Set-ScanStatus $r "Deactivated"
        $hints += "Disabled by policy"
        $r.DisableHint = $adminHow
    } elseif ($disabled.Count -gt 0) {
        Set-ScanStatus $r "Activated"
        $hints = @("Some Paint AI tools may still be on") + $hints
        $hints += "Some Paint AI tools off"
        $r.DisableHint = $adminHow
    } else {
        if ($consent.Denied) {
            Set-ScanStatus $r "Deactivated"
            $hints += "Text and image generation off"
            $hints += ($consent.Signals -join "; ")
            $r.DisableHint = $privacyHow
        } elseif ($consent.Allowed) {
            Set-ScanStatus $r "Activated"
            $hints += "Text and image generation allowed"
            $hints += ($consent.Signals -join "; ")
            $r.DisableHint = $privacyHow
        } else {
            Set-ScanStatus $r "Unknown"
            $hints += "AI switch not stored"
            if ($consent.Signals.Count -gt 0) { $hints += ($consent.Signals -join "; ") }
            $r.DisableHint = $privacyHow
        }
    }
    if ($consent.Denied) {
        $sig = $consent.Signals -join "; "
        if ($sig -and ($hints -notcontains $sig)) { $hints += $sig }
        if ($r.Activated -ne "Deactivated") {
            Set-ScanStatus $r "Deactivated"
            if ($hints -notcontains "Text and image generation off") { $hints += "Text and image generation off" }
        }
        if ($disabled.Count -eq 0) { $r.DisableHint = $privacyHow }
    }
    $r.Details = $hints -join " | "
    $lead = "Some Paint AI tools may still be on"
    if ($r.Activated -eq "Deactivated") {
        $r.Details = ([string]$r.Details).Replace($lead, "")
        while ($r.Details -match "\|[ |]*\|") { $r.Details = [regex]::Replace($r.Details, "\|[ |]*\|", "|") }
        $r.Details = $r.Details.Trim(" |")
    } elseif ($disabled.Count -gt 0 -and $disabled.Count -lt $names.Count) {
        if ([string]$r.Details -notlike "$lead*") {
            if ($r.Details) { $r.Details = "$lead | $($r.Details)" }
            else { $r.Details = $lead }
        }
    }
    return $r
}

# Browser AI checklist - update when a new stable version ships
# For each browser below, confirm:
#   1. First version that includes the AI feature (gray if older)
#   2. Settings path to turn it off (mouse only; no about:config)
#   3. Pref / policy / Local State key names if they were renamed
#   4. Default on vs off (absent pref is not always off)
#   5. Details order: AI on or AI off first, folder words in the middle,
#      Browser path last. Do not put the status sentence or policy key names
#      in Details. Policy off is "turned off by policy".
# Current cutoffs: Chrome 126, Edge 112, Opera 100, Brave 1.52 / Chromium 112,
# Firefox 130 (Labs), Firefox 148 (AI Controls).

function Get-PrefFileText {
    param([string]$Path, [int]$MaxBytes = 12582912)
    $script:LastPrefTruncated = $false
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        if ($fs.Length -gt $MaxBytes) { $script:LastPrefTruncated = $true }
        $take = [int][Math]::Min($fs.Length, $MaxBytes)
        if ($take -le 0) { return "" }
        $buf = New-Object byte[] $take
        $n = $fs.Read($buf, 0, $take)
        if ($n -le 0) { return "" }
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
    } catch {
        return $null
    } finally {
        if ($fs) { $fs.Dispose() }
    }
}


function Get-ChromiumPrefFiles {
    param([string[]]$UserDataRoots, [int]$MaxFiles = 12)
    $files = New-Object System.Collections.Generic.List[string]
    $skip = @("System Profile","Guest Profile","Crashpad","ShaderCache","SwReporter","GrShaderCache","GraphiteDawnCache")
    foreach ($root in @($UserDataRoots)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $ls = Join-Path $root "Local State"
        if ((Test-Path -LiteralPath $ls) -and -not $files.Contains($ls)) { [void]$files.Add($ls) }
        $def = Join-Path $root "Default\Preferences"
        if ((Test-Path -LiteralPath $def) -and -not $files.Contains($def)) { [void]$files.Add($def) }
        try {
            $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -First 24)
            foreach ($d in $dirs) {
                if ($files.Count -ge $MaxFiles) { break }
                $n = [string]$d.Name
                if ($n -eq "Default") { continue }
                if ($skip -contains $n) { continue }
                if ($n -notlike "Profile*") { continue }
                $pref = Join-Path $d.FullName "Preferences"
                if ((Test-Path -LiteralPath $pref) -and -not $files.Contains($pref)) { [void]$files.Add($pref) }
            }
        } catch {}
    }
    return @($files)
}

function Get-FirstWeightsBin {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    try {
        $stack = New-Object System.Collections.Stack
        $stack.Push($Root)
        $seen = 0
        while ($stack.Count -gt 0 -and $seen -lt 400) {
            $dir = [string]$stack.Pop()
            $seen++
            $di = $null
            try { $di = Get-Item -LiteralPath $dir -Force -ErrorAction Stop } catch { continue }
            try {
                if ($di.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            } catch {}
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter "weights.bin" -ErrorAction SilentlyContinue)) {
                return $f
            }
            foreach ($sub in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
                try {
                    if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                } catch {}
                $stack.Push($sub.FullName)
            }
        }
    } catch {}
    return $null
}

function Get-OptGuideFolderDetail {
    param([string[]]$UserDataRoots)
    $emptyFolder = $false
    $folderPresent = $false
    $weightsPresent = $false
    $weightsSize = $null
    if ($UserDataRoots) {
        foreach ($root in @($UserDataRoots)) {
            if (-not $root) { continue }
            foreach ($rel in @("OptGuideOnDeviceModel", "Default\OptGuideOnDeviceModel")) {
                $modelBase = Join-Path $root $rel
                if (-not (Test-Path -LiteralPath $modelBase)) { continue }
                $anyFile = $null
                try { $anyFile = Get-FirstWeightsBin -Root $modelBase } catch { $anyFile = $null }
                if (-not $anyFile) {
                    try {
                        $anyFile = Get-ChildItem -LiteralPath $modelBase -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    } catch { $anyFile = $null }
                }
                if (-not $anyFile) { $emptyFolder = $true; continue }
                $folderPresent = $true
                $weights = Get-FirstWeightsBin -Root $modelBase
                if ($weights -and $weights.Length -gt 50MB) {
                    $weightsPresent = $true
                    $weightsSize = [math]::Round($weights.Length / 1GB, 2)
                }
            }
        }
    }
    if ($weightsPresent) { $detail = "weights.bin ~${weightsSize}GB on disk" }
    elseif ($folderPresent) { $detail = "model files present (download may be incomplete)" }
    elseif ($emptyFolder) { $detail = "model folder empty" }
    else { $detail = "no model folder" }
    return @{ Detail = $detail; HasFiles = $folderPresent; HasWeights = $weightsPresent }
}


function Test-ChromeProcessLive {
    try {
        $procs = @(Get-Process -Name "chrome" -ErrorAction SilentlyContinue)
        return ($procs.Count -gt 0)
    } catch {
        return $false
    }
}

function Get-ChromeRowStatus {
    if (-not $lv) { return "" }
    $n = 0
    try { $n = $lv.Items.Count } catch { return "" }
    for ($i = 0; $i -lt $n; $i++) {
        $it = Get-ListViewItemAt $lv $i
        if (-not $it -or $it.Tag -eq "section") { continue }
        $cur = $it.Tag
        if ($cur -and [string]$cur.Name -like "Google Chrome + Gemini*") {
            return [string]$cur.Activated
        }
    }
    return ""
}

function Save-ChromeReadStamp {
    param([string]$Status)
    if (-not $script:ChromeRecheckPending) {
        $script:ChromeStatusBaseline = [string]$Status
    }
}

function Set-ChromeStatusBar {
    param([string]$Text)
    if (-not $Text -or -not (Test-UiAlive) -or -not $lblStatus) { return }
    try {
        $lblStatus.Text = $Text
        $lblStatus.Refresh()
    } catch {}
}

function Stop-ChromeSettingsRecheck {
    $script:ChromeRecheckPending = $false
    $script:ChromeRecheckStep = 0
    if ($script:ChromeRecheckTimer) {
        try { $script:ChromeRecheckTimer.Stop() } catch {}
        try { $script:ChromeRecheckTimer.Dispose() } catch {}
        $script:ChromeRecheckTimer = $null
    }
}

function Update-ChromeRowFromResult {
    param($r)
    if (-not $r -or -not (Test-UiAlive) -or -not $lv) { return }
    try {
        [void](Set-RunningAndStatus $r (Test-IsRunning -AiName $r.Name))
    } catch {}
    $n = 0
    try { $n = $lv.Items.Count } catch { return }
    for ($i = 0; $i -lt $n; $i++) {
        $it = Get-ListViewItemAt $lv $i
        if (-not $it -or $it.Tag -eq "section") { continue }
        $cur = $it.Tag
        if (-not $cur) { continue }
        if ([string]$cur.Name -ne [string]$r.Name) { continue }
        $it.Tag = $r
        try { Set-ListViewItemAppearance -Item $it -r $r } catch {}
        break
    }
    if ($script:LvCache) {
        foreach ($it in @($script:LvCache)) {
            if (-not $it -or $it.Tag -eq "section") { continue }
            $cur = $it.Tag
            if ($cur -and [string]$cur.Name -eq [string]$r.Name) { $it.Tag = $r }
        }
    }
}

function Start-ChromeFollowUpTimer {
    param([int]$IntervalMs)
    if ($IntervalMs -lt 1) { $IntervalMs = 10000 }
    if ($script:ChromeRecheckTimer) {
        try { $script:ChromeRecheckTimer.Stop() } catch {}
        try { $script:ChromeRecheckTimer.Dispose() } catch {}
        $script:ChromeRecheckTimer = $null
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $IntervalMs
    $timer.Add_Tick({
        try {
            $tm = $script:ChromeRecheckTimer
            if ($tm) { try { $tm.Stop() } catch {} }
            Invoke-ChromeSettingsRecheck
        } catch {}
    })
    $script:ChromeRecheckTimer = $timer
    $timer.Start()
}

function Invoke-ChromeSettingsRecheck {
    if (-not (Test-UiAlive)) { return }
    if ($script:ScanBusy) { return }
    if (Test-ScanCanceled) { return }
    $r = $null
    try {
        $r = Scan-GeminiChrome
        if ($r) { Update-ChromeRowFromResult $r }
    } catch {
        try { Write-ErrorLog "Chrome settings recheck failed" -ErrorRecord $_ } catch {}
    }
    $st = ""
    try {
        if ($r) { $st = [string]$r.Activated }
        if (-not $st) { $st = Get-ChromeRowStatus }
    } catch {}
    $base = [string]$script:ChromeStatusBaseline
    $changed = ($st -and $base -and $st -ne $base)
    if ($changed) {
        try { Stop-ChromeSettingsRecheck } catch {}
        Set-ChromeStatusBar "Chrome AI switch changed."
        return
    }
    $step = 0
    try { $step = [int]$script:ChromeRecheckStep } catch { $step = 0 }
    $chromeOpen = $false
    try { $chromeOpen = [bool](Test-ChromeProcessLive) } catch { $chromeOpen = $false }
    if ($step -lt 2 -and $chromeOpen) {
        $script:ChromeRecheckStep = 2
        $script:ChromeRecheckPending = $true
        Start-ChromeFollowUpTimer 10000
        return
    }
    try { Stop-ChromeSettingsRecheck } catch {}
}

function Start-ChromeSettingsRecheck {
    Stop-ChromeSettingsRecheck
    if (-not (Test-UiAlive)) { return }
    if ([int]$script:ScanPass -lt 2) { return }
    $st = ""
    try { $st = Get-ChromeRowStatus } catch { $st = "" }
    if (-not $st -or $st -eq "Not Installed" -or $st -eq "No AI Features") { return }
    $chromeOpen = $false
    try { $chromeOpen = [bool](Test-ChromeProcessLive) } catch { $chromeOpen = $false }
    if (-not $chromeOpen) { return }
    $script:ChromeRecheckPending = $true
    $script:ChromeRecheckStep = 1
    Start-ChromeFollowUpTimer 10000
}

# Browser Details order. Do not put the status reason in front of AI on / AI off.
# 1. AI on, AI off, AI not in this version, Could not read settings, or AI on/off key not stored
# 2. Extra switch only if read (Edge: Copilot sidebar on/off). Policy off: turned off by policy
# 3. Folder words: no model folder, model folder empty, model files present, weights.bin size
# 4. Browser path last. A missing browser has no path.
# Browser Details order: AI on or AI off first when the switch was read,
# then folder or other facts, then Browser: path last.
# Do not put the status sentence or policy key names in Details.
# A version with no AI says AI not in this version.
function Move-BrowserPathLast {
    param($Result)
    if (-not $Result) { return }
    $d = [string]$Result.Details
    if (-not $d) { return }
    $d = $d.Replace("AI not in this version", "AI not in this version")
    $parts = @($d -split '\s*\|\s*' | Where-Object { $_ })
    $browser = @($parts | Where-Object { $_ -like 'Browser:*' })
    $rest = @($parts | Where-Object { $_ -notlike 'Browser:*' })
    $st = [string]$Result.Activated
    $hasOn = @($rest | Where-Object { $_ -like 'AI on*' }).Count -gt 0
    $hasOff = @($rest | Where-Object { $_ -like 'AI off*' }).Count -gt 0
    if ($st -eq 'Activated' -and -not $hasOn) { $rest = @('AI on') + @($rest) }
    elseif ($st -eq 'Deactivated' -and -not $hasOff) { $rest = @('AI off') + @($rest) }
    $Result.Details = (@($rest + $browser) | Where-Object { $_ }) -join ' | '
}

function Scan-GeminiChrome {
    # Chrome: Gemini Nano cutoff 126. Settings > System > On-device AI.
    $r = New-Result "Google Chrome + Gemini"
    $r.DisableHint = "Chrome Settings > System > turn off On-device AI."

    $chromeExe = Get-NewestExistingExe @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome Beta\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome Beta\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome Dev\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome Dev\Application\chrome.exe",
        "${env:ProgramFiles}\Google\Chrome SxS\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome SxS\Application\chrome.exe"
    )
    if (-not $chromeExe) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Chrome browser found"
        $r.DisableHint = ""
        Save-ChromeReadStamp -Status $r.Activated
        Move-BrowserPathLast $r
        return $r
    }
    $r.Installed = $true
    $r.Details = "Browser: $chromeExe"
    $r.Version = Get-FileVersionSafe $chromeExe
    $chMajor = 0
    if ($r.Version -match "^(\d+)") { $chMajor = [int]$Matches[1] }
    if ($chMajor -gt 0 -and $chMajor -lt 126) {
        $r.DisableHint = ""
        Set-ScanStatus $r "No AI Features"
        $r.Details += " | AI not in this version"
        Save-ChromeReadStamp -Status $r.Activated
        Move-BrowserPathLast $r
        return $r
    }

    $signals = @()
    $weightsPresent = $false
    $folderPresent = $false
    $policyDisabled = $false
    $sawOn = $false
    $sawOff = $false
    $localStateRead = $false
    $prefTruncated = $false

    # --- Policy disable (strongest) ---
    # Hard Chrome policy only. Recommended is not an administrator lock.
    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Google\Chrome",
        "HKCU:\SOFTWARE\Policies\Google\Chrome"
    )) {
        try {
            $gs = Get-ItemProperty -Path $p -Name "GeminiSettings" -ErrorAction SilentlyContinue
            if ($gs -and $gs.GeminiSettings -eq 1) {
                $policyDisabled = $true
                $signals += "Policy GeminiSettings=1"
            }
            $od = Get-ItemProperty -Path $p -Name "GenAILocalFoundationalModelSettings" -ErrorAction SilentlyContinue
            if ($null -ne $od -and $od.GenAILocalFoundationalModelSettings -eq 1) {
                $policyDisabled = $true
                $signals += "Policy GenAILocalFoundationalModelSettings=1 (do not download)"
            }
        } catch {}
    }
    $recommendedOff = @()
    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Google\Chrome\Recommended",
        "HKCU:\SOFTWARE\Policies\Google\Chrome\Recommended"
    )) {
        try {
            $gs = Get-ItemProperty -Path $p -Name "GeminiSettings" -ErrorAction SilentlyContinue
            if ($gs -and $gs.GeminiSettings -eq 1) { $recommendedOff += "Recommended GeminiSettings=1" }
            $od = Get-ItemProperty -Path $p -Name "GenAILocalFoundationalModelSettings" -ErrorAction SilentlyContinue
            if ($null -ne $od -and $od.GenAILocalFoundationalModelSettings -eq 1) { $recommendedOff += "Recommended GenAILocalFoundationalModelSettings=1" }
        } catch {}
    }

    $chromeDataRoots = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Google\Chrome Beta\User Data",
        "$env:LOCALAPPDATA\Google\Chrome Dev\User Data",
        "$env:LOCALAPPDATA\Google\Chrome SxS\User Data"
    )
    if (-not $script:ChromeRecheckPending) {
        Set-ScanProgressText "Reading Chrome settings..."
    }

    foreach ($prefFile in @(Get-ChromiumPrefFiles $chromeDataRoots)) {
        try {
            $content = Get-PrefFileText $prefFile
            if ($null -eq $content) { continue }
            if ($script:LastPrefTruncated) { $prefTruncated = $true }
            $prefName = [IO.Path]::GetFileName([string]$prefFile)
            if ($prefName -eq "Local State") { $localStateRead = $true }
            # Real Local State key (Chromium):
            # optimization_guide.on_device_foundational_model_user_settings
            # Default is true. Older guessed names kept as extras.
            if ($content -match '"on_device_foundational_model_user_settings"\s*:\s*true' -or
                $content -match '"on_device_ai_user_settings_enabled"\s*:\s*true' -or
                $content -match '"OnDeviceAiUserSettingsEnabled"\s*:\s*true') {
                $sawOn = $true
            }
            if ($content -match '"on_device_foundational_model_user_settings"\s*:\s*false' -or
                $content -match '"on_device_ai_user_settings_enabled"\s*:\s*false' -or
                $content -match '"OnDeviceAiUserSettingsEnabled"\s*:\s*false') {
                $sawOff = $true
            }
        } catch {}
        $content = $null
    }

    $guide = Get-OptGuideFolderDetail $chromeDataRoots
    $modelDetail = [string]$guide.Detail
    $folderPresent = [bool]$guide.HasFiles
    $weightsPresent = [bool]$guide.HasWeights

    # Status follows the Settings switch. Folder only changes Details.
    # Missing key: Chrome default is on.
    if ($policyDisabled) {
        Set-ScanStatus $r "Deactivated"
        $r.Details += " | AI off | turned off by policy | $modelDetail"
        if ($folderPresent -or $weightsPresent) { $r.DisableHint = "" }
    } elseif ($sawOn) {
        Set-ScanStatus $r "Activated"
        $r.Details += " | AI on | $modelDetail"
    } elseif ($sawOff) {
        Set-ScanStatus $r "Deactivated"
        $r.Details += " | AI off | $modelDetail"
        if ($folderPresent -or $weightsPresent) { $r.DisableHint = "" }
    } elseif ($localStateRead -and -not $prefTruncated) {
        Set-ScanStatus $r "Activated"
        $r.Details += " | AI on | $modelDetail"
    } elseif (-not $localStateRead) {
        $r.DisableHint = ""
        Set-ScanStatus $r "Unknown"
        $r.Details += " | Could not read settings | $modelDetail"
    } elseif ($prefTruncated -and -not $sawOn -and -not $sawOff) {
        $r.DisableHint = ""
        Set-ScanStatus $r "Unknown"
        $r.Details += " | Could not read settings | $modelDetail"
    } else {
        $r.DisableHint = ""
        Set-ScanStatus $r "Deactivated"
        $r.Details += " | AI off | $modelDetail"
    }
    $content = $null
    Save-ChromeReadStamp -Status $r.Activated
    Move-BrowserPathLast $r
    return $r
}

function Scan-ChatGPT {
    $r = New-Result "ChatGPT (OpenAI)"
    $pkgs = Get-AppxByName "OpenAI.ChatGPT*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "OpenAI.Codex*" }

    if ($pkgs) {
        $pkg = $pkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "App: $($pkg.Name)"
        Set-ScanStatus $r "Installed"
        return $r
    }

    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\ChatGPT\ChatGPT.exe",
        "$env:LOCALAPPDATA\ChatGPT\ChatGPT.exe"
    )
    $pkgFolder = $null
    $pkgRoot = "$env:LOCALAPPDATA\Packages"
    if (Test-Path $pkgRoot) {
        $hit = Get-ChildItem $pkgRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "OpenAI.ChatGPT*" -or $_.Name -like "OpenAI.Codex*" } |
            Select-Object -First 1
        if ($hit) { $pkgFolder = $hit.FullName }
    }

    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($pkgFolder) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $pkgFolder"
        Set-ScanStatus $r "Not Installed" "Leftover package folder"
        $r.DisableHint = ""
    } elseif (Test-Path "$env:USERPROFILE\.codex") {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $env:USERPROFILE\.codex"
        Set-ScanStatus $r "Not Installed" "Leftover data folder"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No ChatGPT app found"
    }
    return $r
}

function Scan-Claude {
    $r = New-Result "Claude (Anthropic)"
    $pkgs = Get-AppxByName "Claude*"
    $claudePkgs = @()
    foreach ($p0 in @($pkgs)) {
        if (-not $p0) { continue }
        $n = [string]$p0.Name
        $pub = ""
        try { $pub = [string]$p0.Publisher } catch {}
        if ($n -match '(?i)Anthropic' -or $pub -match '(?i)Anthropic' -or $n -like "Claude_*" -or $n -like "Anthropic.Claude*") {
            $claudePkgs += $p0
        }
    }
    if ($claudePkgs.Count -gt 0) {
        $pkg = $claudePkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "App: $($pkg.Name)"
        Set-ScanStatus $r "Installed"
        return $r
    }

    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
        "$env:LOCALAPPDATA\AnthropicClaude\Claude.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } else {
        $left = @()
        foreach ($p in @(
            "$env:LOCALAPPDATA\Programs\Claude",
            "$env:LOCALAPPDATA\AnthropicClaude",
            "$env:APPDATA\Claude"
        )) {
            if (Test-Path $p) { $left += $p }
        }
        $pkgDir = "$env:LOCALAPPDATA\Packages"
        if (Test-Path $pkgDir) {
            $claudePkg = Get-ChildItem $pkgDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Claude_*" } | Select-Object -First 1
            if ($claudePkg) { $left += $claudePkg.FullName }
        }
        if ($left.Count -gt 0) {
            $r.Installed = $false
            $r.Details = "Leftover folder; no app: " + ($left -join "; ")
            Set-ScanStatus $r "Not Installed" "Leftover data folder"
            $r.DisableHint = ""
        }
    }
    if (-not $r.Installed) {
        if (-not $r.Details) {
            $r.Details = "No Claude app found"
        }
        Set-ScanStatus $r "Not Installed"
    }
    return $r
}


function Test-OfficialGeminiProcessOpen {
    try {
        $procs = @(Get-CachedProcesses) | Where-Object {
            $_.ProcessName -match '(?i)^gemini'
        }
        foreach ($p in @($procs)) {
            $path = $null
            try { $path = [string]$p.Path } catch {}
            if ($path -and $path -like "*\Google\Gemini\*") { return $true }
        }
    } catch {}
    return $false
}

function Scan-GeminiDesktop {
    # Maintainer check (does not run). Official GeminiSetup.exe is Google Updater
    # only. Confirmed from that file: appguid {533DD80C-942A-4464-B6A9-2E59428D784E},
    # appname=Gemini, needsadmin=false (per-user).
    # Still needed for 100% confirmation on a live install:
    #   exact Gemini.exe path under %LOCALAPPDATA%\Google\Gemini
    #   process name and FileDescription
    #   uninstall DisplayIcon / InstallLocation
    #   whether Store/Appx Google.Gemini* is ever used
    #   ClientState value names (pv, name, UninstallCmdLine)
    # Do not treat Programs\Gemini Desktop wrappers as official.
    # Folder alone under Google\Gemini is leftover, not Installed.
    # Re-read this when a new GeminiSetup.exe ships.

    $r = New-Result "Gemini (Google)"
    $r.DisableHint = "Windows Settings > Apps > Installed apps > Gemini > Uninstall."
    $guid = "{533DD80C-942A-4464-B6A9-2E59428D784E}"
    $bits = @()

    foreach ($rk in @(
        "HKCU:\SOFTWARE\Google\Update\Clients\$guid",
        "HKCU:\SOFTWARE\Google\Update\ClientState\$guid",
        "HKLM:\SOFTWARE\Google\Update\Clients\$guid",
        "HKLM:\SOFTWARE\WOW6432Node\Google\Update\Clients\$guid"
    )) {
        try {
            if (Test-Path $rk) {
                $item = Get-ItemProperty $rk -ErrorAction SilentlyContinue
                $r.Installed = $true
                $nm = [string]$item.name
                if (-not $nm) { $nm = [string]$item.Name }
                $pv = [string]$item.pv
                if ($pv) { $r.Version = $pv }
                if ($nm) { $bits += "App: $nm" }
                break
            }
        } catch {}
    }

    $geminiRoot = Join-Path $env:LOCALAPPDATA "Google\Gemini"
    $exe = $null
    $geminiFolder = $false
    if (Test-Path $geminiRoot) {
        $geminiFolder = $true
        $geminiSkipWalk = $false
        try {
            $gdi = Get-Item -LiteralPath $geminiRoot -Force -ErrorAction Stop
            if ($gdi.Attributes -band [IO.FileAttributes]::ReparsePoint) { $geminiSkipWalk = $true }
        } catch {}
        try {
            $found = $null
            if (-not $geminiSkipWalk) {
            $found = Get-ChildItem -LiteralPath $geminiRoot -Recurse -Depth 3 -Filter "Gemini.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $found) {
                $found = Get-ChildItem -LiteralPath $geminiRoot -Recurse -Depth 3 -Filter "gemini.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($found) { $exe = $found.FullName }
            }
        } catch {}
    }
    if (-not $exe) {
        $exe = Test-PathAny @(
            "$env:LOCALAPPDATA\Google\Gemini\Gemini.exe",
            "$env:LOCALAPPDATA\Google\Gemini\Application\Gemini.exe",
            "$env:LOCALAPPDATA\Programs\Google\Gemini\Gemini.exe"
        )
        if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    }
    if ($exe) {
        $r.Installed = $true
        $bits = @("App: $exe")
        $ver = Get-FileVersionSafe $exe
        if ($ver) { $r.Version = $ver }
    }

    if (-not $r.Installed) {
        $pkgs = Get-AppxByName "Google.Gemini*"
        if (-not $pkgs) { $pkgs = Get-AppxByName "*GeminiApp*" }
        if ($pkgs) {
            $pkg = $pkgs | Select-Object -First 1
            $r.Installed = $true
            $r.Version = $pkg.Version
            $bits = @("App: $($pkg.Name)")
        }
    }

    if (-not $r.Installed) {
        try {
            $unG = Get-UninstallApps @("Gemini","Google Gemini*")
            foreach ($u in @($unG)) {
                $pub = [string]$u.Publisher
                $dn = [string]$u.DisplayName
                if ($dn -like "*Desktop*" -or $dn -like "*GeminiDesktop*") { continue }
                if ($pub -match '(?i)google') {
                    $r.Installed = $true
                    $bits = @("App: $dn")
                    if ($u.DisplayVersion) { $r.Version = $u.DisplayVersion }
                    break
                }
            }
        } catch {}
    }

    if ($r.Installed) {
        $r.Details = (($bits | Where-Object { $_ }) -join " | ")
        if (-not $r.Details) { $r.Details = "App: Gemini" }
        Set-ScanStatus $r "Installed"
    } elseif ($geminiFolder) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $geminiRoot"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe or Apps entry"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Gemini app found"
        $r.DisableHint = ""
    }
    return $r
}

function Scan-ClaudeCode {
    $r = New-Result "Claude Code (Anthropic)"
    $r.DisableHint = "Windows Settings > Apps > Installed apps > Claude Code > Uninstall. If it is not listed, File Explorer > your user folder > .local\bin > delete claude.exe."
    $exe = Test-PathAny @(
        "$env:USERPROFILE\.local\bin\claude.exe",
        "$env:LOCALAPPDATA\Programs\claude-code\claude.exe",
        "$env:LOCALAPPDATA\Programs\Claude Code\claude.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    $data = Test-PathAny @(
        "$env:USERPROFILE\.claude",
        "$env:USERPROFILE\.claude-code",
        "$env:LOCALAPPDATA\Programs\claude-code",
        "$env:LOCALAPPDATA\Programs\Claude Code"
    )
    $desc = ""
    if ($exe) {
        try { $desc = [string](Get-Item $exe).VersionInfo.FileDescription } catch {}
        if (-not $desc) { try { $desc = [string](Get-Item $exe).VersionInfo.ProductName } catch {} }
    }
    $looksClaude = ($desc -match '(?i)claude')
    $un = $null
    try { $un = Get-UninstallApps @("Claude Code*","Anthropic Claude Code*") } catch {}
    if (($exe -and $data) -or ($exe -and $looksClaude) -or $un) {
        $r.Installed = $true
        if ($exe) {
            $r.Details = "App: $exe"
            $r.Version = Get-FileVersionSafe $exe
            if ($desc) { $r.Details += " | $desc" }
        } elseif ($un) {
            $r.Details = "App: $($un[0].DisplayName)"
            if ($un[0].DisplayVersion) { $r.Version = $un[0].DisplayVersion }
        }
        if ($data) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed" "Claude Code"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Claude Code app found"
        $r.DisableHint = ""
    }
    return $r
}

function Scan-CherryStudio {
    $r = New-Result "Cherry Studio"
    $r.DisableHint = "Windows Settings > Apps > Installed apps > Cherry Studio > Uninstall."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Cherry Studio\Cherry Studio.exe",
        "$env:LOCALAPPDATA\Programs\CherryStudio\CherryStudio.exe",
        "$env:LOCALAPPDATA\Programs\Cherry Studio\CherryStudio.exe",
        "${env:ProgramFiles}\Cherry Studio\Cherry Studio.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    $data = Test-PathAny @(
        "$env:APPDATA\CherryStudio",
        "$env:LOCALAPPDATA\CherryStudio"
    )
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } else {
        $unC = $null
        try { $unC = Get-UninstallApps @("Cherry Studio*") } catch {}
        if ($unC) {
            $r.Installed = $true
            $r.Details = "App: $($unC[0].DisplayName)"
            if ($data) { $r.Details += " | Data folder present" }
            if ($unC[0].DisplayVersion) { $r.Version = $unC[0].DisplayVersion }
            Set-ScanStatus $r "Installed" "Uninstall registry"
        } elseif ($data) {
            $r.Installed = $false
            $r.Details = "Leftover folder; no app: $data"
            Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
            $r.DisableHint = ""
        } else {
            Set-ScanStatus $r "Not Installed"
            $r.Details = "No Cherry Studio app found"
            $r.DisableHint = ""
        }
    }
    return $r
}


function Scan-ChatRTX {
    $r = New-Result "ChatRTX (NVIDIA)"
    $r.DisableHint = "Windows Settings > Apps > Installed apps > ChatRTX or NVIDIA ChatRTX > Uninstall."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\NVIDIA\ChatRTX\ChatRTX.exe",
        "$env:LOCALAPPDATA\NVIDIA\ChatWithRTX\ChatRTX.exe",
        "${env:ProgramFiles}\NVIDIA Corporation\ChatRTX\ChatRTX.exe",
        "${env:ProgramFiles}\NVIDIA ChatRTX\ChatRTX.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    $models = Test-PathAny @(
        "$env:LOCALAPPDATA\NVIDIA\ChatRTX",
        "$env:LOCALAPPDATA\NVIDIA\ChatWithRTX",
        "$env:LOCALAPPDATA\NVIDIA\RAG"
    )
    $un = $null
    try { $un = Get-UninstallApps @("ChatRTX*", "ChatRTX (NVIDIA)*", "Chat with RTX*") } catch {}
    if ($exe -or $un) {
        $r.Installed = $true
        if ($exe) {
            $r.Details = "App: $exe"
            $r.Version = Get-FileVersionSafe $exe
        } elseif ($un) {
            $r.Details = "App: $($un[0].DisplayName)"
            if ($un[0].DisplayVersion) { $r.Version = $un[0].DisplayVersion }
        }
        if ($models) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($models) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $models"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No ChatRTX app found"
        $r.DisableHint = ""
    }
    return $r
}

function Scan-GAssist {
    $r = New-Result "G-Assist (NVIDIA)"
    $r.DisableHint = "Open the NVIDIA App > Discover > G-Assist > Uninstall."
    # Overlay folder or Apps list = Installed. nvtopps folder alone = leftover.
    $overlay = Test-PathAny @(
        "$env:PROGRAMDATA\NVIDIA Corporation\NVIDIA Overlay\G-Assist",
        "$env:LOCALAPPDATA\NVIDIA Corporation\NVIDIA Overlay\G-Assist"
    )
    $leftover = Test-PathAny @(
        "$env:PROGRAMDATA\NVIDIA Corporation\nvtopps\rise\G-Assist",
        "$env:PROGRAMDATA\NVIDIA Corporation\nvtopps\rise\g-assist"
    )
    $hit = $null
    if (Test-Path "$env:PROGRAMDATA\NVIDIA Corporation") {
        $hit = Get-ChildItem "$env:PROGRAMDATA\NVIDIA Corporation" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)g-?assist' } |
            Select-Object -First 1
        if ($hit) {
            if ([string]$hit.FullName -match '(?i)NVIDIA Overlay') { $overlay = $hit.FullName }
            else { $leftover = $hit.FullName }
        }
    }
    $un = $null
    try { $un = Get-UninstallApps @("G-Assist*", "G-Assist (NVIDIA)*", "Project G-Assist*") } catch {}
    if ($overlay -or $un) {
        $r.Installed = $true
        $r.Details = if ($overlay) { "App: $overlay" } else { "App: $($un[0].DisplayName)" }
        if ($un -and $un[0].DisplayVersion) { $r.Version = $un[0].DisplayVersion }
        Set-ScanStatus $r "Installed"
    } elseif ($leftover) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $leftover"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe or Apps entry"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No G-Assist app found"
        $r.DisableHint = ""
    }
    return $r
}

function Scan-LibreChat {
    $r = New-Result "LibreChat"
    $r.DisableHint = "If LibreChat appears in Windows Settings > Apps, click Uninstall. If you use Docker Desktop, open Docker Desktop and stop or delete the LibreChat container."
    $folder = Test-PathAny @(
        "$env:USERPROFILE\LibreChat",
        "$env:USERPROFILE\librechat",
        "$env:LOCALAPPDATA\LibreChat",
        "$env:USERPROFILE\.librechat"
    )
    $launcher = $null
    if ($folder) {
        $launcher = Test-PathAny @(
            (Join-Path $folder "LibreChat.exe"),
            (Join-Path $folder "docker-compose.yml"),
            (Join-Path $folder "docker-compose.yaml")
        )
    }
    $un = $null
    try { $un = Get-UninstallApps @("LibreChat*") } catch {}
    # Port 3080 is not probed. Another app on that port is not LibreChat.
    if ($launcher -or $un) {
        $r.Installed = $true
        if ($launcher) { $r.Details = "App: $launcher" }
        elseif ($un) { $r.Details = "App: $($un[0].DisplayName)" }
        if ($folder) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($folder) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $folder"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no launcher"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No LibreChat app found"
        $r.DisableHint = ""
    }
    return $r
}


function Scan-Perplexity {
    $r = New-Result "Perplexity"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Perplexity\Perplexity.exe",
        "$env:LOCALAPPDATA\Perplexity\Perplexity.exe",
        "${env:ProgramFiles}\Perplexity\Perplexity.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        Set-ScanStatus $r "Installed"
        $r.Version = Get-FileVersionSafe $exe
    } elseif (Test-Path "$env:APPDATA\Perplexity") {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $env:APPDATA\Perplexity"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Perplexity app found"
    }
    return $r
}

function Scan-EdgeCopilot {
    # Edge: Copilot sidebar + OptGuide weights. First version 112.
    $r = New-Result "Microsoft Edge + Copilot"
    $r.DisableHint = "Edge Settings > Sidebar > turn off Copilot. Then Settings > System and performance > turn off On-device AI if that switch is listed."
    $edge = Get-NewestExistingExe @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge Beta\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge Beta\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge Dev\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge Dev\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge SxS\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge SxS\Application\msedge.exe"
    )
    if (-not $edge) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Edge browser found"
        Move-BrowserPathLast $r
        return $r
    }

    $r.Installed = $true
    $r.Details = "Browser: $edge"
    $r.Version = Get-FileVersionSafe $edge
    $edMajor = 0
    if ($r.Version -match '^(\d+)') { $edMajor = [int]$Matches[1] }
    if ($edMajor -gt 0 -and $edMajor -lt 112) {
        $r.DisableHint = ""
        Set-ScanStatus $r "No AI Features"
        $r.Details += " | AI not in this version"
        Move-BrowserPathLast $r
        return $r
    }

    # Hard Edge policy only. Recommended is not an administrator lock.
    $activatedHints = @()
    $policyOff = $false
    $sidebarOn = $false
    $userSidebarOff = $false

    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
        "HKCU:\SOFTWARE\Policies\Microsoft\Edge"
    )) {
        try {
            $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            if ($null -ne $props.HubsSidebarEnabled -and $props.HubsSidebarEnabled -eq 0) {
                $policyOff = $true
                $activatedHints += "Policy HubsSidebarEnabled=0"
            }
            if ($null -ne $props.CopilotPage -and $props.CopilotPage -eq 0) {
                $policyOff = $true
                $activatedHints += "Policy CopilotPage=0"
            }
            if ($null -ne $props.HubsSidebarEnabled -and $props.HubsSidebarEnabled -eq 1) {
                $activatedHints += "Policy HubsSidebarEnabled=1"
            }
            if ($null -ne $props.CopilotPage -and $props.CopilotPage -eq 1) {
                $activatedHints += "Policy CopilotPage=1"
            }
        } catch {}
    }

    Set-ScanProgressText "Reading Edge settings..."
    $prefsRead = $false
    $localStateRead = $false
    $userModelOff = $false
    $onDeviceSettingOn = $false
    $prefTruncated = $false
    $edgeDataRoots = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge Beta\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge Dev\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge SxS\User Data"
    )
    foreach ($prefFile in @(Get-ChromiumPrefFiles $edgeDataRoots)) {
        try {
            $pr = Get-PrefFileText $prefFile
            if ($null -eq $pr) { continue }
            if ($script:LastPrefTruncated) { $prefTruncated = $true }
            $prefsRead = $true
            if ($pr -match '"copilot_page"\s*:\s*true' -or $pr -match '"show_copilot"\s*:\s*true') {
                $sidebarOn = $true
            }
            if ($pr -match '"copilot_page"\s*:\s*false' -or $pr -match '"show_copilot"\s*:\s*false') {
                $userSidebarOff = $true
            }
            if ($pr -match '"on_device_foundational_model_user_settings"\s*:\s*false' -or
                $pr -match '"on_device_ai_user_settings_enabled"\s*:\s*false') {
                $userModelOff = $true
                $localStateRead = $true
            } elseif ($pr -match '"on_device_foundational_model_user_settings"\s*:\s*true' -or
                      $pr -match '"on_device_ai_user_settings_enabled"\s*:\s*true') {
                $onDeviceSettingOn = $true
                $localStateRead = $true
            }
        } catch {}
        $pr = $null
    }

    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
        "HKCU:\SOFTWARE\Policies\Microsoft\Edge"
    )) {
        try {
            $od = Get-ItemProperty -Path $p -Name "GenAILocalFoundationalModelSettings" -ErrorAction SilentlyContinue
            if ($null -ne $od -and $od.GenAILocalFoundationalModelSettings -eq 1) {
                $policyOff = $true
                $activatedHints += "Policy GenAILocalFoundationalModelSettings=1 (do not download)"
            }
        } catch {}
    }

    $guide = Get-OptGuideFolderDetail $edgeDataRoots
    $modelDetail = [string]$guide.Detail
    $onDeviceOn = ($onDeviceSettingOn -eq $true)
    $settingsOff = ($userSidebarOff -or $userModelOff)
    $settingsOn = ($sidebarOn -or $onDeviceOn)
    $settingsRead = $prefsRead -or $localStateRead
    $sideTxt = ""
    if ($sidebarOn) { $sideTxt = "Copilot sidebar on" }
    elseif ($userSidebarOff) { $sideTxt = "Copilot sidebar off" }
    $userHow = "Edge Settings > Sidebar > turn off Copilot. Then Settings > System and performance > turn off On-device AI if that switch is listed."
    $mid = $(if ($sideTxt) { " | $sideTxt" } else { "" })

    if ($policyOff) {
        Set-ScanStatus $r "Deactivated"
        $r.DisableHint = "Controlled by your administrator."
        $r.Details += " | AI off | turned off by policy$mid | $modelDetail"
    } elseif ($settingsOn) {
        Set-ScanStatus $r "Activated"
        $r.DisableHint = $userHow
        $r.Details += " | AI on$mid | $modelDetail"
    } elseif ($settingsOff) {
        Set-ScanStatus $r "Deactivated"
        $r.DisableHint = $userHow
        $r.Details += " | AI off$mid | $modelDetail"
    } elseif (-not $settingsRead) {
        Set-ScanStatus $r "Unknown"
        $r.DisableHint = ""
        $r.Details += " | Could not read settings$mid | $modelDetail"
    } elseif ($prefTruncated -and -not $settingsOn -and -not $settingsOff) {
        Set-ScanStatus $r "Unknown"
        $r.DisableHint = ""
        $r.Details += " | Could not read settings$mid | $modelDetail"
    } else {
        Set-ScanStatus $r "Deactivated"
        $r.DisableHint = $userHow
        $r.Details += " | AI off$mid | $modelDetail"
    }
    Move-BrowserPathLast $r
    return $r
}

function Scan-Ollama {
    $r = New-Result "Ollama"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe",
        "${env:ProgramFiles}\Ollama\ollama.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Ollama\ollama.exe"
    )
    $models = Test-Path "$env:USERPROFILE\.ollama"
    $logs = Test-Path "$env:LOCALAPPDATA\Ollama"

    if (-not $exe) {
        $exe = Get-KnownCommandSource -Name ollama -PathLike @("*\Ollama\*")
    }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        if ($models) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($models -or $logs) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Ollama app found"
    }
    return $r
}

function Scan-LMStudio {
    $r = New-Result "LM Studio"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe",
        "$env:LOCALAPPDATA\Programs\LM-Studio\LM Studio.exe",
        "$env:LOCALAPPDATA\LM-Studio\LM Studio.exe",
        "${env:ProgramFiles}\LM Studio\LM Studio.exe"
    )
    $data = Test-PathAny @(
        "$env:USERPROFILE\.lmstudio",
        "$env:USERPROFILE\.cache\lm-studio",
        "$env:LOCALAPPDATA\lm-studio"
    )

    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        if ($data) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No LM Studio app found"
    }
    return $r
}

function Scan-Jan {
    $r = New-Result "Jan"
    $data = Test-PathAny @(
        "$env:APPDATA\Jan",
        "$env:LOCALAPPDATA\Programs\Jan",
        "$env:LOCALAPPDATA\Jan"
    )
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Jan\Jan.exe",
        "$env:LOCALAPPDATA\Programs\jan\Jan.exe"
    )

    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Jan app found"
    }
    return $r
}

function Scan-GPT4All {
    $r = New-Result "GPT4All"
    # Do not recurse the models folder (%LOCALAPPDATA%\nomic.ai\GPT4All).
    # That tree holds large GGUF files and made this scan slow.
    $exe = Test-PathAny @(
        "$env:USERPROFILE\gpt4all\bin\chat.exe",
        "$env:USERPROFILE\gpt4all\chat.exe",
        "$env:USERPROFILE\gpt4all\gpt4all.exe",
        "$env:USERPROFILE\gpt4all\bin\gpt4all.exe",
        "$env:LOCALAPPDATA\Programs\GPT4All\bin\chat.exe",
        "$env:LOCALAPPDATA\Programs\GPT4All\chat.exe",
        "${env:ProgramFiles}\GPT4All\bin\chat.exe",
        "${env:ProgramFiles}\GPT4All\gpt4all.exe"
    )
    if (-not $exe) {
        $installRoot = "$env:USERPROFILE\gpt4all"
        if (Test-Path $installRoot) {
            $hit = Get-ChildItem -Path $installRoot -Depth 2 -File -Filter "chat.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $hit) {
                $hit = Get-ChildItem -Path $installRoot -Depth 2 -File -Filter "gpt4all*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($hit) { $exe = $hit.FullName }
        }
    }
    if (-not $exe) {
        try { $unHits = @(Get-UninstallApps @("*GPT4All*")) } catch { $unHits = @() }
        $hit = $unHits | Select-Object -First 1
        if ($hit) {
            $icon = [string]$hit.DisplayIcon
            if ($icon) { $icon = ($icon -split ',')[0].Trim('"') }
            if ($icon -and (Test-Path $icon)) { $exe = $icon }
            elseif ($hit.InstallLocation) {
                $cand = Test-PathAny @(
                    (Join-Path $hit.InstallLocation "bin\chat.exe"),
                    (Join-Path $hit.InstallLocation "chat.exe"),
                    (Join-Path $hit.InstallLocation "gpt4all.exe")
                )
                if ($cand) { $exe = $cand }
            }
            if (-not $r.Version -and $hit.DisplayVersion) { $r.Version = [string]$hit.DisplayVersion }
        }
    }

    $data = Test-PathAny @(
        "$env:APPDATA\nomic.ai",
        "$env:LOCALAPPDATA\nomic.ai\GPT4All"
    )

    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        if (-not $r.Version) { $r.Version = Get-FileVersionSafe $exe }
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No GPT4All app found"
    }
    return $r
}

function Scan-Cursor {
    $r = New-Result "Cursor"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe",
        "${env:ProgramFiles}\cursor\Cursor.exe",
        "${env:ProgramFiles}\Cursor\Cursor.exe"
    )

    $regFound = $false
    try { $unHits = @(Get-UninstallApps @("Cursor*")) } catch { $unHits = @() }
    foreach ($item in $unHits) {
        $dn = [string]$item.DisplayName
        if ($dn -like "*Mouse*" -or $dn -like "*Cursor Hero*") { continue }
        $pub = [string]$item.Publisher
        $loc = [string]$item.InstallLocation
        $hasExe = $false
        if ($loc) {
            $cand = Join-Path $loc "Cursor.exe"
            if (Test-Path $cand) {
                $hasExe = $true
                if (-not $exe) { $exe = $cand }
            }
        }
        if (-not $hasExe -and $pub -notlike "*Anysphere*") { continue }
        $regFound = $true
        break
    }

    if ($exe -or $regFound) {
        $r.Installed = $true
        if ($exe) {
            $r.Details = "App: $exe"
            $r.Version = Get-FileVersionSafe $exe
        } else {
            $r.Details = "App: Cursor"
        }
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Cursor app found"
    }
    return $r
}

function Scan-WindowsAIComponents {
    $r = New-Result "Windows On-Device AI"
    # These are system components on Copilot+ and recent Windows 11

    # Common Appx / system packages related to Windows AI
    if ($null -eq $script:AllAppx) {
        $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    }
    # Known Windows AI packages only. A data folder is not the app.
    $aiNameRe = "Windows\.AI|Microsoft\.Windows\.AI|PhiSilica|AionInstruct|WindowsAI|AI\.Model|ImageCreation|ImageGeneration|ImageTransform|ContentExtraction|SemanticAnalysis"
    $aiPkgs = @($script:AllAppx | Where-Object { $_.Name -match $aiNameRe })
    $parts = @()

    if ($aiPkgs) {
        $r.Installed = $true
        $names = ($aiPkgs | Select-Object -First 6 -ExpandProperty Name) -join ", "
        $parts += "App: $names"
        $labels = [ordered]@{
            "Phi Silica" = "PhiSilica|AionInstruct"
            "Image Creation" = "ImageCreation|ImageGeneration"
            "Image Processing" = "ImageProcessing"
            "Image Transform" = "ImageTransform"
            "Image Search" = "ImageSearch"
            "Content Extraction" = "ContentExtraction"
            "Semantic Analysis" = "SemanticAnalysis"
            "Settings Model" = "SettingsModel"
            "Execution Provider" = "ExecutionProvider"
        }
        $found = @()
        foreach ($label in $labels.Keys) {
            $re = $labels[$label]
            if ($aiPkgs | Where-Object { $_.Name -match $re }) { $found += $label }
        }
        if ($found.Count -gt 0) {
            $parts += "AI components: " + ($found -join ", ")
        } else {
            $parts += "On-device AI packages present"
        }
        Set-ScanStatus $r "Installed"
    }

    $knownPackage = [bool]($aiPkgs)
    $possible = @(
        "$env:ProgramData\Microsoft\Windows\AI",
        "$env:LOCALAPPDATA\Microsoft\Windows\AI"
    )
    foreach ($p in $possible) {
        if (Test-Path $p) {
            $parts += "Data folder present: $p"
            break
        }
    }

    if (-not $knownPackage) {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed"
        if (-not ($parts | Where-Object { $_ -like "Data folder*" })) { $parts = @("No Windows On-Device AI app found") }
        else { $parts = @("Leftover folder; no app") + @($parts | Where-Object { $_ -like "Data folder*" }) }
    } elseif (-not $r.Activated -or $r.Activated -eq "Not Installed") {
        Set-ScanStatus $r "Installed"
    }
    $consent = Get-SystemAiConsent
    $privacyHow = "Windows Settings > Privacy & security > Text and image generation > turn off Windows AI if listed."
    if ($knownPackage -and $consent.Denied) {
        $parts += "Text and image generation off"
        Set-ScanStatus $r "Deactivated"
        $r.DisableHint = $privacyHow
    } elseif ($knownPackage -and $consent.Allowed) {
        $parts += "Text and image generation on"
        Set-ScanStatus $r "Activated"
        $r.DisableHint = $privacyHow
    } elseif ($knownPackage) {
        $r.DisableHint = $privacyHow
    }
    if ($r.Installed) {
        $lead = "AI on/off not read"
        if ($r.Activated -eq "Activated") { $lead = "AI on" }
        elseif ($r.Activated -eq "Deactivated") { $lead = "AI off" }
        $app = @($parts | Where-Object { $_ -like "App:*" } | Select-Object -First 1)
        $comp = @($parts | Where-Object { $_ -like "AI components:*" } | Select-Object -First 1)
        $extra = @($parts | Where-Object { $_ -like "Text and image generation*" })
        $parts = @($lead) + $app + $comp + $extra
    }
    $r.Details = ($parts | Where-Object { $_ }) -join " | "
    return $r
}

function Get-WindowsAiPolicyDword {
    param([string]$Name)
    foreach ($root in @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI",
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    )) {
        $v = Get-RegValueSafe -Path $root -Name $Name
        if ($null -ne $v) {
            try { return [int]$v } catch { return $null }
        }
    }
    return $null
}

function Scan-Recall {
    $r = New-Result "Recall (Windows)"
    $parts = @()
    $rawPkgs = @()
    foreach ($pat in @("*Windows*Recall*", "Microsoft.*Recall*")) {
        $hit = Get-AppxByName $pat
        if ($hit) { $rawPkgs += @($hit) }
    }
    $pkgs = @($rawPkgs | Where-Object {
        $_.Name -match '(?i)(Windows.*Recall|Microsoft.*Recall)'
    } | Select-Object -Unique)
    $ukp = Join-Path $env:LOCALAPPDATA "CoreAIPlatform.00\UKP"
    $hasUkp = $false
    try { $hasUkp = Test-Path -LiteralPath $ukp } catch { $hasUkp = $false }

    if ($pkgs) {
        $pkg = @($pkgs) | Select-Object -First 1
        $parts += "App: $($pkg.Name)"
        if (-not $r.Version) { $r.Version = $pkg.Version }
    }
    if ($hasUkp) { $parts += "Snapshot folder present" }

    $allow = Get-WindowsAiPolicyDword "AllowRecallEnablement"
    $disableSnap = Get-WindowsAiPolicyDword "DisableAIDataAnalysis"
    $userOn = Get-RegValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Recall" -Name "EnableRecall"

    if (-not $pkgs -and $hasUkp) {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Leftover folder; no app: $ukp"
        $r.DisableHint = ""
        return $r
    }
    if (-not $pkgs) {
        Set-ScanStatus $r "Not Installed"
        if ($hasUkp) { $r.Details = "Leftover folder; no app: $ukp" }
        else { $r.Details = "No Recall app or snapshot folder" }
        return $r
    }

    $r.Installed = $true
    $policyBlocks = ($null -ne $allow -and [int]$allow -eq 0) -or ($null -ne $disableSnap -and [int]$disableSnap -eq 1)
    $userOff = ($null -ne $userOn -and "$userOn" -eq "0")
    $userOnFlag = ($null -ne $userOn -and "$userOn" -eq "1")

    $userHow = "Windows Settings > Privacy & security > Recall & snapshots > turn off Save snapshots."
    if ($policyBlocks) {
        Set-ScanStatus $r "Deactivated"
        $parts = @("AI off", "turned off by policy") + @($parts | Where-Object { $_ -like "App:*" -or $_ -like "Snapshot*" })
        $r.DisableHint = "Controlled by your administrator."
    } elseif ($userOff) {
        Set-ScanStatus $r "Deactivated"
        $parts = @("AI off") + @($parts | Where-Object { $_ -like "App:*" -or $_ -like "Snapshot*" })
        $r.DisableHint = $userHow
    } elseif ($userOnFlag) {
        Set-ScanStatus $r "Activated"
        $parts = @("AI on") + @($parts | Where-Object { $_ -like "App:*" -or $_ -like "Snapshot*" })
        $r.DisableHint = $userHow
    } else {
        Set-ScanStatus $r "Installed"
        $parts = @("AI on/off not read") + @($parts | Where-Object { $_ -like "App:*" -or $_ -like "Snapshot*" })
        $r.DisableHint = $userHow
    }
    $r.Details = ($parts | Where-Object { $_ }) -join " | "
    return $r
}


function Scan-FileExplorerAI {
    $r = New-Result "File Explorer + AI"
    $pkgs = @()
    foreach ($pat in @("*FileExplorerAI*", "*AIActions*", "*ExplorerAIActions*")) {
        $hit = Get-AppxByName $pat
        if ($hit) { $pkgs += @($hit) }
    }
    $pkgs = @($pkgs | Select-Object -Unique)
    $how = "Settings > Apps > Actions, then turn off each action. Restart if the menu is still there."
    if (-not $pkgs) {
        if (Test-WindowsBuildAtLeast 26100) {
            Set-ScanStatus $r "Installed"
            $r.Installed = $true
            $r.Details = "Windows 11 24H2 or later. No AI actions package found. The menu may still be there."
            $r.DisableHint = $how
        } else {
            Set-ScanStatus $r "Not Installed"
            $r.Details = "No File Explorer + AI found"
        }
        return $r
    }
    $pkg = $pkgs | Select-Object -First 1
    $r.Installed = $true
    $r.Version = $pkg.Version
    $r.DisableHint = $how
    Set-ScanStatus $r "Installed"
    $r.Details = "App: $($pkg.Name) | Action toggles not read"
    return $r
}

function Scan-ClickToDo {
    $r = New-Result "Click to Do (Windows)"
    $parts = @()
    $pkgs = Get-AppxByName "*ClickToDo*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "*ClickToDoExperience*" }
    $disable = Get-WindowsAiPolicyDword "DisableClickToDo"

    if ($pkgs) {
        $pkg = @($pkgs) | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $parts += "App: $($pkg.Name)"
    }

    # Click to Do ships with Copilot+ / Recall stacks; treat policy + package.

    if (-not $r.Installed) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Click to Do app found"
        return $r
    }

    $userHow = "Windows Settings > Privacy & security > Click to Do > turn it Off."
    if ($null -ne $disable -and [int]$disable -eq 1) {
        Set-ScanStatus $r "Deactivated"
        $parts = @("AI off", "turned off by policy") + @($parts | Where-Object { $_ -like "App:*" })
        $r.DisableHint = "Controlled by your administrator."
    } else {
        Set-ScanStatus $r "Installed"
        $parts = @("AI on/off not read") + @($parts | Where-Object { $_ -like "App:*" })
        $r.DisableHint = $userHow
    }
    $r.Details = ($parts | Where-Object { $_ }) -join " | "
    return $r
}


function Test-WindowsBuildAtLeast {
    param([int]$Build)
    try {
        $b = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuild -ErrorAction Stop
        return ([int]$b.CurrentBuild -ge $Build)
    } catch { return $false }
}

function Get-SettingsAgentDisableText {
    $edition = ""
    $name = ""
    try {
        $cv = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $edition = [string]$cv.EditionID
        $name = [string]$cv.ProductName
    } catch {}
    $isHome = ($edition -match '^(Core|CoreSingleLanguage|CoreCountrySpecific)$') -or ($name -match 'Home')
    if ($isHome) { return "Home: there is no off switch in Settings." }
    return "Group Policy > Computer Configuration > Administrative Templates > Windows Components > Windows AI > turn on Disable Settings Agent."
}

function Scan-SettingsAgent {
    $r = New-Result "Agent in Settings (Windows)"
    $how = Get-SettingsAgentDisableText
    if (-not (Test-WindowsBuildAtLeast 26100)) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Not on this Windows. Settings agent is Windows 11 24H2 or later."
        return $r
    }
    if ($null -eq $script:AllAppx) {
        $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    }
    $aiNameRe = "Windows\.AI|Microsoft\.Windows\.AI|PhiSilica|AionInstruct|WindowsAI|AI\.Model|ImageCreation|ImageGeneration|ImageTransform|ContentExtraction|SemanticAnalysis"
    $aiPkgs = @($script:AllAppx | Where-Object { $_.Name -match $aiNameRe })
    if (-not $aiPkgs) {
        Set-ScanStatus $r "Installed"
        $r.Installed = $true
        $r.Details = "Windows 11 24H2 or later. No Copilot+ AI components found. Settings agent may not be on this PC."
        $r.DisableHint = $how
        return $r
    }
    $off = Get-WindowsAiPolicyDword "DisableSettingsAgent"
    $r.Installed = $true
    $parts = @("Windows 11 24H2 or later", "Copilot+ AI components present")
    if ($null -ne $off -and [int]$off -eq 1) {
        Set-ScanStatus $r "Deactivated"
        $parts = @("AI off", "turned off by policy", "App: Windows AI components")
        $r.DisableHint = "Controlled by your administrator. " + $how
    } else {
        Set-ScanStatus $r "Activated"
        $parts = @("AI on", "App: Windows AI components")
        $r.DisableHint = $how
    }
    $r.Details = ($parts | Where-Object { $_ }) -join " | "
    return $r
}

function Scan-GitHubCopilot {
    $r = New-Result "GitHub Copilot"
    # Extension folders
    $extPaths = @(
        "$env:USERPROFILE\.vscode\extensions",
        "$env:USERPROFILE\.vscode-insiders\extensions",
        "$env:APPDATA\Code\User\extensions",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\resources\app\extensions"
    )
    $found = $false
    $parts = @()
    foreach ($base in $extPaths) {
        if (Test-Path $base) {
            $copilotExt = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "github.copilot*" }
            if ($copilotExt) {
                $found = $true
                $parts += "Extension folder: $($copilotExt[0].FullName)"
                break
            }
        }
    }
    $dataOnly = $false
    if (Test-Path "$env:LOCALAPPDATA\GitHubCopilot") {
        $dataOnly = -not $found
        if ($found) { $parts += "Data folder present" }
    }

    if ($found) {
        $r.Installed = $true
        $r.Details = "App: " + ($parts[0] -replace '^Extension folder: ', '')
        if ($parts.Count -gt 1) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($dataOnly) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $env:LOCALAPPDATA\GitHubCopilot"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No GitHub Copilot app found"
    }
    return $r
}

function Scan-ComfyUI {
    $r = New-Result "ComfyUI"
    $markers = @(
        "$env:USERPROFILE\ComfyUI",
        "$env:USERPROFILE\Documents\ComfyUI",
        "C:\ComfyUI",
        "D:\ComfyUI",
        "$env:LOCALAPPDATA\Programs\ComfyUI"
    )
    $found = Test-PathAny $markers
    $launcher = $null
    if ($found) {
        $launcher = Test-PathAny @(
            (Join-Path $found "main.py"),
            (Join-Path $found "ComfyUI.exe"),
            (Join-Path $found "comfyui.exe")
        )
    }
    if ($launcher) {
        $r.Installed = $true
        $r.Details = "App: $launcher"
        Set-ScanStatus $r "Installed"
    } elseif ($found) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $found"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no launcher"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No ComfyUI app found"
    }
    return $r
}

function Scan-OperaAI {
    # Opera: Aria cutoff 100. Settings > Sidebar.
    $r = New-Result "Opera + Aria"
    $r.DisableHint = "Opera Settings > Sidebar > turn off Aria / Opera AI."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Opera\opera.exe",
        "$env:LOCALAPPDATA\Programs\Opera GX\opera.exe",
        "${env:ProgramFiles}\Opera\opera.exe",
        "${env:ProgramFiles(x86)}\Opera\opera.exe",
        "$env:LOCALAPPDATA\Programs\Opera Beta\opera.exe",
        "$env:LOCALAPPDATA\Programs\Opera developer\opera.exe"
    )
    if (-not $exe) {
        $reg = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\opera.exe" -ErrorAction SilentlyContinue
        if ($reg -and $reg.'(default)') {
            $r.Installed = $true
            $r.Details = "Browser: Opera"
            Set-ScanStatus $r "Unknown" "AI setting unknown"
            Move-BrowserPathLast $r
            return $r
        }
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Opera browser found"
        Move-BrowserPathLast $r
        return $r
    }

    $r.Installed = $true
    $r.Details = "Browser: $exe"
    $r.Version = Get-FileVersionSafe $exe
    $opMajor = 0
    if ($r.Version -match "^(\d+)") { $opMajor = [int]$Matches[1] }
    if ($opMajor -gt 0 -and $opMajor -lt 100) {
        $r.DisableHint = ""
        Set-ScanStatus $r "No AI Features" "Opera $opMajor present; no Aria on this version"
        $r.Details += " | AI not in this version"
        Move-BrowserPathLast $r
        return $r
    }
    Set-ScanStatus $r "Unknown" "AI setting unknown"
    Set-ScanProgressText "Reading Opera settings..."

    $prefCandidates = @(
        "$env:APPDATA\Opera Software\Opera Stable\Preferences",
        "$env:APPDATA\Opera Software\Opera GX Stable\Preferences",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\Preferences"
    )
    foreach ($opRoot in @("$env:APPDATA\Opera Software", "$env:LOCALAPPDATA\Opera Software")) {
        if (-not (Test-Path $opRoot)) { continue }
        try {
            foreach ($d in @(Get-ChildItem -LiteralPath $opRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 12)) {
                $p1 = Join-Path $d.FullName "Preferences"
                $p2 = Join-Path $d.FullName "Default\Preferences"
                if ((Test-Path $p1) -and ($prefCandidates -notcontains $p1)) { $prefCandidates += $p1 }
                if ((Test-Path $p2) -and ($prefCandidates -notcontains $p2)) { $prefCandidates += $p2 }
            }
        } catch {}
    }
    if ($prefCandidates.Count -gt 12) { $prefCandidates = $prefCandidates[0..11] }
    $prefsRead = $false
    $anyOn = $false
    $anyOff = $false
    foreach ($pref in $prefCandidates) {
        if (-not (Test-Path $pref)) { continue }
        try {
            $content = Get-PrefFileText $pref
            if ($null -eq $content) { continue }
            $prefsRead = $true
            $off = ($content -match '"aria_enabled"\s*:\s*false') -or ($content -match '"enable_aria"\s*:\s*false') -or ($content -match '"opera_aria_enabled"\s*:\s*false')
            $on  = ($content -match '"aria_enabled"\s*:\s*true') -or ($content -match '"enable_aria"\s*:\s*true') -or ($content -match '"opera_aria_enabled"\s*:\s*true')
            if ($on) { $anyOn = $true }
            elseif ($off) { $anyOff = $true }
        } catch {}
        $content = $null
    }
    $operaRoots = @(
        "$env:APPDATA\Opera Software\Opera Stable",
        "$env:APPDATA\Opera Software\Opera GX Stable",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable"
    )
    $guide = Get-OptGuideFolderDetail $operaRoots
    $modelDetail = [string]$guide.Detail
    if ($anyOn) {
        Set-ScanStatus $r "Activated" "Aria on in Preferences"
        $r.Details += " | AI on | $modelDetail"
        if ($anyOff) { $r.Details += " | on in at least one profile" }
    } elseif ($anyOff) {
        Set-ScanStatus $r "Deactivated" "Aria off in Preferences"
        $r.Details += " | AI off | $modelDetail"
    } elseif ($prefsRead -and $r.Activated -eq "Unknown") {
        $r.Details += " | AI on/off key not stored | $modelDetail"
    } else {
        $r.Details += " | $modelDetail"
    }
    Move-BrowserPathLast $r
    return $r
}

function Scan-BraveLeo {
    # Brave: Leo from 1.52 or Chromium 112. Settings > Leo.
    $r = New-Result "Brave + Leo"
    $r.DisableHint = "Brave Settings > Leo > turn off Leo AI."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    if (-not $exe) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Brave browser found"
        Move-BrowserPathLast $r
        return $r
    }

    $r.Installed = $true
    $r.Details = "Browser: $exe"
    $r.Version = Get-FileVersionSafe $exe
    $brMajor = 0
    $brMinor = 0
    if ($r.Version -match "^(\d+)\.(\d+)") {
        $brMajor = [int]$Matches[1]
        $brMinor = [int]$Matches[2]
    } elseif ($r.Version -match "^(\d+)") {
        $brMajor = [int]$Matches[1]
    }
    $brHasLeo = $false
    if ($brMajor -eq 1 -and $brMinor -ge 52) { $brHasLeo = $true }
    elseif ($brMajor -ge 112) { $brHasLeo = $true }
    if ($brMajor -gt 0 -and -not $brHasLeo) {
        $r.DisableHint = ""
        Set-ScanStatus $r "No AI Features" "Brave $brMajor present; no Leo on this version"
        $r.Details += " | AI not in this version"
        Move-BrowserPathLast $r
        return $r
    }
    Set-ScanStatus $r "Unknown" "AI setting unknown"
    Set-ScanProgressText "Reading Brave settings..."

    # Policy can disable Leo
    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave",
        "HKCU:\SOFTWARE\Policies\BraveSoftware\Brave"
    )) {
        try {
            $val = Get-ItemProperty -Path $p -Name "BraveAIChatEnabled" -ErrorAction SilentlyContinue
            if ($null -ne $val -and $val.BraveAIChatEnabled -eq 0) {
                Set-ScanStatus $r "Deactivated" "Leo disabled by policy"
                $r.Details += " | AI off"
                Move-BrowserPathLast $r
                return $r
            }
            if ($null -ne $val -and $val.BraveAIChatEnabled -eq 1) {
                Set-ScanStatus $r "Activated" "Leo enabled by policy"
                $r.Details += " | AI on"
            }
        } catch {}
    }

    $braveRoots = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Beta\User Data"
    )
    $prefsRead = $false
    $anyOn = $false
    $anyOff = $false
    foreach ($f in @(Get-ChromiumPrefFiles $braveRoots)) {
        try {
            $content = Get-PrefFileText $f
            if ($null -eq $content) { continue }
            $prefsRead = $true
            $off = ($content -match '"brave\.ai_chat\.enabled"\s*:\s*false') -or ($content -match '"ai_chat"\s*:\s*\{[^}]{0,400}"enabled"\s*:\s*false')
            $on  = ($content -match '"brave\.ai_chat\.enabled"\s*:\s*true') -or ($content -match '"ai_chat"\s*:\s*\{[^}]{0,400}"enabled"\s*:\s*true')
            if ($on) { $anyOn = $true }
            elseif ($off) { $anyOff = $true }
        } catch {}
        $content = $null
    }
    $guide = Get-OptGuideFolderDetail $braveRoots
    $modelDetail = [string]$guide.Detail
    if ($anyOn) {
        Set-ScanStatus $r "Activated" "Leo on in Preferences"
        $r.Details += " | AI on | $modelDetail"
        if ($anyOff) { $r.Details += " | on in at least one profile" }
    } elseif ($anyOff) {
        Set-ScanStatus $r "Deactivated" "Leo off in Preferences"
        $r.Details += " | AI off | $modelDetail"
    } elseif ($prefsRead -and $r.Activated -eq "Unknown") {
        $r.Details += " | AI on/off key not stored | $modelDetail"
    } else {
        $r.Details += " | $modelDetail"
    }
    Move-BrowserPathLast $r
    return $r
}

function Scan-Comet {
    # Comet: AI-native browser. Treat install as the product.
    $r = New-Result "Perplexity Comet + AI"
    $r.DisableHint = "Comet Settings > turn off AI features (or uninstall Comet from Windows Settings > Apps)."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Perplexity\Comet\Application\comet.exe",
        "$env:LOCALAPPDATA\Programs\Comet\comet.exe",
        "${env:ProgramFiles}\Comet\comet.exe"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Browser: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Unknown" "AI setting unknown"
    } elseif (Test-Path "$env:LOCALAPPDATA\Perplexity\Comet") {
        $r.Installed = $false
        $r.Details = "Leftover folder; no browser: $env:LOCALAPPDATA\Perplexity\Comet"
        Set-ScanStatus $r "Not Installed" "Leftover data folder"
        $r.DisableHint = ""
        Move-BrowserPathLast $r
        return $r
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Comet browser found"
        $r.DisableHint = ""
        Move-BrowserPathLast $r
        return $r
    }

    $anyOn = $false
    $anyOff = $false
    $prefsRead = $false
    $cometRoots = @(
        "$env:LOCALAPPDATA\Perplexity\Comet\User Data",
        "$env:LOCALAPPDATA\Comet\User Data"
    )
    foreach ($pref in @(Get-ChromiumPrefFiles -UserDataRoots $cometRoots)) {
        if (-not (Test-Path -LiteralPath $pref)) { continue }
        try {
            $pr = Get-PrefFileText $pref
            if ($null -eq $pr) { continue }
            $prefsRead = $true
            if ($pr -match '"ai_enabled"\s*:\s*false' -or $pr -match '"comet_ai"\s*:\s*false' -or $pr -match '"assistant_enabled"\s*:\s*false') { $anyOff = $true }
            if ($pr -match '"ai_enabled"\s*:\s*true' -or $pr -match '"comet_ai"\s*:\s*true' -or $pr -match '"assistant_enabled"\s*:\s*true') { $anyOn = $true }
        } catch {}
        $pr = $null
    }
    $guide = Get-OptGuideFolderDetail $cometRoots
    $modelDetail = [string]$guide.Detail
    if ($anyOn) {
        Set-ScanStatus $r "Activated" "AI setting on in Comet preferences"
        $r.Details += " | AI on | $modelDetail"
        if ($anyOff) { $r.Details += " | on in at least one profile" }
    } elseif ($anyOff) {
        Set-ScanStatus $r "Deactivated" "AI setting off in Comet preferences"
        $r.Details += " | AI off | $modelDetail"
    } elseif ($prefsRead) {
        Set-ScanStatus $r "Unknown" "Preferences read; AI on/off key not stored"
        $r.Details += " | AI on/off key not stored | $modelDetail"
    } else {
        $r.Details += " | $modelDetail"
    }
    Move-BrowserPathLast $r
    return $r
}

function Get-FirefoxExeFromUninstall {
    $hits = @()
    try { $hits = @(Get-UninstallApps @("Mozilla Firefox*", "Firefox*")) } catch { return $null }
    foreach ($hit in $hits) {
        $dn = [string]$hit.DisplayName
        if (-not $dn) { continue }
        if ($dn -match '(?i)thunderbird|maintenance service|crash reporter|mozilla vpn') { continue }
        $cands = @()
        $loc = [string]$hit.InstallLocation
        if ($loc) {
            $cands += (Join-Path $loc "firefox.exe")
            $cands += (Join-Path $loc "Firefox\firefox.exe")
        }
        $icon = [string]$hit.DisplayIcon
        if ($icon) {
            $iconPath = ($icon -split ',')[0].Trim().Trim('"')
            if ($iconPath -like "*.exe") { $cands += $iconPath }
        }
        $exe = Test-PathAny $cands
        if ($exe -and ([string]$exe -like "*firefox.exe")) { return $exe }
    }
    return $null
}

function Scan-Firefox {
    # Firefox: Labs 130-135, General Browsing 136-147, AI Controls 148+.
    # Last confirmed AI-default major is $ffAiSheetMajor (Firefox-AI-map.xlsx = 157).
    # When you add a newer Firefox version to this function AND confirm its
    # Settings path and about:config defaults, set $ffAiSheetMajor to that
    # major. Majors above that value with no pref lines stay Unknown.
    # Empty prefs: 148-157 Activated (AI Controls default is not blocked).
    # 130-147 empty prefs follow that version Default on the map (off).
    $r = New-Result "Mozilla Firefox + AI"
    $r.DisableHint = "Firefox Settings > AI Controls > turn on Block AI enhancements."
    $exe = Test-PathAny @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles}\Firefox Nightly\firefox.exe",
        "${env:ProgramFiles}\Firefox Developer Edition\firefox.exe",
        "$env:LOCALAPPDATA\Firefox Developer Edition\firefox.exe"
    )
    if (-not $exe) { $exe = Get-FirefoxExeFromUninstall }
    $profilesRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (-not $exe) {
        Set-ScanStatus $r "Not Installed"
        $r.DisableHint = ""
        if (Test-Path $profilesRoot) {
            $r.Details = "Leftover folder; no browser: $profilesRoot"
        } else {
            $r.Details = "No Firefox browser found"
        }
        Move-BrowserPathLast $r
        return $r
    }

    $r.Installed = $true
    $r.Details = "Browser: $exe"
    $r.Version = Get-FileVersionSafe $exe

    try {
        $ini = Join-Path (Split-Path $exe -Parent) "application.ini"
        if (Test-Path $ini) {
            foreach ($line in (Get-Content $ini -ErrorAction SilentlyContinue)) {
                if ($line -match '^\s*Version\s*=\s*(.+)$') {
                    $r.Version = $Matches[1].Trim()
                    break
                }
            }
        }
    } catch {}

    $ffMajor = 0
    if ($r.Version -match '^(\d+)') { $ffMajor = [int]$Matches[1] }
    # Bump this when a newer Firefox major is added with confirmed defaults.
    $ffAiSheetMajor = 157
    $ffHasAiBundle = ($ffMajor -ge 130)
    $ffHasAiControls = ($ffMajor -ge 148)

    if ($ffMajor -ge 148) {
        $r.DisableHint = "Firefox Settings > AI Controls > turn on Block AI enhancements."
    } elseif ($ffMajor -eq 147) {
        $r.DisableHint = "Firefox Settings > General > Browsing > turn off Enable link previews. Settings > General > Tabs > Interaction > turn off Use AI to suggest tabs and a name for tab groups."
    } elseif ($ffMajor -ge 143) {
        $r.DisableHint = "Firefox Settings > General > Browsing > turn off Enable link previews. Settings > General > Tabs > turn off Use AI to suggest tabs and a name for tab groups."
    } elseif ($ffMajor -eq 142) {
        $r.DisableHint = "Firefox Settings > General > Browsing > turn off Enable link previews and Allow AI to read the page for key points."
    } elseif ($ffMajor -eq 141) {
        $r.DisableHint = "Firefox 141 has no Settings page for link previews. Official help starts at 142 (Settings > General > Browsing)."
    } elseif ($ffMajor -ge 136) {
        $r.DisableHint = "Firefox 136: Settings > General > Browser Layout may list an AI chatbot in the sidebar. Labs AI chatbot is documented for 130-135. Update to 148+ for Settings > AI Controls."
    } elseif ($ffMajor -ge 130) {
        $r.DisableHint = "Firefox Settings > Firefox Labs > turn off AI chatbot."
    } else {
        $r.DisableHint = ""
    }

    $policyDefaultBlocked = $false
    $policyNote = ""
    try {
        $polPaths = @(
            "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\AIControls",
            "HKCU:\SOFTWARE\Policies\Mozilla\Firefox\AIControls"
        )
        $genPaths = @(
            "HKLM:\SOFTWARE\Policies\Mozilla\Firefox\GenerativeAI",
            "HKCU:\SOFTWARE\Policies\Mozilla\Firefox\GenerativeAI"
        )
        $polAi = $null
        $polGen = $null
        foreach ($p in $polPaths) {
            try {
                $hit = Get-ItemProperty $p -ErrorAction SilentlyContinue
                if ($hit) {
                    if (-not $polAi) { $polAi = $hit }
                    $defHit = [string]$hit.Default
                    if ($defHit -match '(?i)blocked') {
                        $policyDefaultBlocked = $true
                        $polAi = $hit
                    }
                }
            } catch {}
        }
        foreach ($p in $genPaths) {
            try {
                $hit = Get-ItemProperty $p -ErrorAction SilentlyContinue
                if ($hit -and -not $polGen) { $polGen = $hit }
            } catch {}
        }
        if ($polAi) {
            $def = [string]$polAi.Default
            if (-not $def) {
                foreach ($p in $polPaths) {
                    try {
                        $defKey = Get-ItemProperty ($p + "\Default") -ErrorAction SilentlyContinue
                        if ($defKey -and $defKey.Value) { $def = [string]$defKey.Value; break }
                    } catch {}
                }
            }
            if ($def -match '(?i)blocked') {
                $policyDefaultBlocked = $true
                $policyNote = "Windows policy blocks Firefox AI Controls (Default)"
            } else {
                $policyNote = "Policy keys present under Mozilla\Firefox"
            }
        } elseif ($polGen) {
            $policyNote = "Policy keys present under Mozilla\Firefox"
        }
    } catch {}

    if ($ffMajor -gt 0) {
        $r.Details += " | Firefox $ffMajor"
        if (-not $ffHasAiBundle) {
            $r.DisableHint = ""
            Set-ScanStatus $r "No AI Features" "Firefox $ffMajor present; no bundled generative AI"
            $r.Details = "Browser: $exe | AI not in this version"
            Move-BrowserPathLast $r
            return $r
        }
        if (-not $ffHasAiControls) {
            $r.Details += " | This version includes AI but has no Settings AI Controls page"
        }
    }

    $enabledFlags = @()
    $disabledFlags = @()
    $blockedControls = @()
    $availableControls = @()
    $providerSet = $false
    $profileChecked = $false

    $ffRoot = "$env:APPDATA\Mozilla\Firefox"
    if ((Test-Path $profilesRoot) -or (Test-Path (Join-Path $ffRoot "profiles.ini"))) {
        Set-ScanProgressText "Reading Firefox settings..."
        try {
            $files = @()
            $profileDirs = @()
            $ini = Join-Path $ffRoot "profiles.ini"
            if (Test-Path $ini) {
                $sections = @()
                $cur = $null
                foreach ($line in @(Get-Content $ini -ErrorAction SilentlyContinue)) {
                    if ($line -match '^\s*\[') {
                        if ($cur) { $sections += $cur }
                        $cur = @{ Rel = $true; Path = "" }
                        continue
                    }
                    if (-not $cur) { $cur = @{ Rel = $true; Path = "" } }
                    if ($line -match '^\s*IsRelative\s*=\s*(\d)') { $cur.Rel = ($Matches[1] -ne '0'); continue }
                    if ($line -match '^\s*Path\s*=\s*(.+)$') { $cur.Path = $Matches[1].Trim() }
                }
                if ($cur) { $sections += $cur }
                foreach ($sec in $sections) {
                    if (-not $sec.Path) { continue }
                    $p = $sec.Path
                    if ($sec.Rel) { $p = Join-Path $ffRoot $p }
                    $profileDirs += $p
                }
            }
            if ($profileDirs.Count -eq 0 -and (Test-Path $profilesRoot)) {
                $profileDirs = @(Get-ChildItem $profilesRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
            }
            foreach ($dir in $profileDirs) {
                foreach ($n in @("user.js", "prefs.js")) {
                    $pf = Join-Path $dir $n
                    if (Test-Path -LiteralPath $pf) { $files += Get-Item -LiteralPath $pf }
                }
            }

            foreach ($pf in $files) {
                $profileChecked = $true
                $c = Get-PrefFileText $pf.FullName
                if (-not $c) { continue }

                $onPrefs = @(
                    'browser\.ml\.enable',
                    'browser\.ml\.chat\.enabled',
                    'browser\.ml\.chat\.sidebar',
                    'browser\.ml\.chat\.menu',
                    'browser\.ml\.chat\.page',
                    'browser\.ml\.linkPreview\.enabled',
                    'browser\.ml\.linkPreview\.optin',
                    'browser\.ml\.pageAssist\.enabled',
                    'browser\.ml\.smartAssist\.enabled',
                    'browser\.tabs\.groups\.smart\.enabled',
                    'browser\.tabs\.groups\.smart\.userEnabled'
                )
                foreach ($p in $onPrefs) {
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*true\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($enabledFlags -notcontains $short) { $enabledFlags += $short }
                    }
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*false\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($disabledFlags -notcontains $short) { $disabledFlags += $short }
                    }
                }

                if ($c -match 'user_pref\(\s*"browser\.ml\.chat\.provider"\s*,\s*"(https?:[^"]+)"\s*\)') {
                    $providerSet = $true
                    if ($enabledFlags -notcontains 'browser.ml.chat.provider') { $enabledFlags += 'browser.ml.chat.provider' }
                }

                $controlPrefs = @(
                    'browser\.ai\.control\.default',
                    'browser\.ai\.control\.sidebarChatbot',
                    'browser\.ai\.control\.linkPreviewKeyPoints',
                    'browser\.ai\.control\.smartTabGroups',
                    'browser\.ai\.control\.translations',
                    'browser\.ai\.control\.pdfjsAltText',
                    'browser\.ai\.control\.smartWindow',
                    'browser\.ai\.control\.speechRecognition'
                )
                foreach ($p in $controlPrefs) {
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*`"blocked`"\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($blockedControls -notcontains $short) { $blockedControls += $short }
                    }
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*`"(enabled|available)`"\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($availableControls -notcontains $short) { $availableControls += $short }
                        if ($enabledFlags -notcontains $short) { $enabledFlags += $short }
                    }
                }
                $c = $null
            }
        } catch {
            Write-ErrorLog "Firefox prefs scan failed" -ErrorRecord $_
        }
    }

    $uncoveredOn = @()
    foreach ($u in @('browser.ml.pageAssist.enabled','browser.ml.smartAssist.enabled','browser.ml.enable')) {
        if ($enabledFlags -contains $u) { $uncoveredOn += $u }
    }
    $extMl = ($enabledFlags -contains 'extensions.ml.enabled')
    if ($policyDefaultBlocked -and $blockedControls -notcontains 'browser.ai.control.default') {
        $blockedControls += 'browser.ai.control.default'
    }
    if ($policyNote) { $r.Details += " | " + $policyNote }
    $masterBlocked = (($blockedControls -contains 'browser.ai.control.default') -or
                     ($disabledFlags -contains 'browser.ml.enable')) -and ($uncoveredOn.Count -eq 0)
    $chatOff = ($disabledFlags -contains 'browser.ml.chat.enabled')
    $sidebarBlocked = ($blockedControls -contains 'browser.ai.control.sidebarChatbot')
    if ($uncoveredOn.Count -gt 0) {
        $r.Details += " | Block/AI Controls does not cover: " + ($uncoveredOn -join ", ")
    }
    if ($extMl) { $r.Details += " | extensions.ml.enabled=true (Details only)" }

    $blockExcludedOn = @()
    if ($enabledFlags -contains "browser.ml.pageAssist.enabled") { $blockExcludedOn += "pageAssist" }
    if ($enabledFlags -contains "browser.ml.smartAssist.enabled") { $blockExcludedOn += "smartAssist" }
    if ($enabledFlags -contains "browser.ml.enable") { $blockExcludedOn += "browser.ml.enable" }

    if ($masterBlocked -and $enabledFlags.Count -eq 0) {
        Set-ScanStatus $r "Deactivated" "AI blocked in Firefox Settings"
        $parts = @()
        if ($blockedControls.Count -gt 0) { $parts += "blocked: $($blockedControls.Count) controls" }
        if ($disabledFlags.Count -gt 0) { $parts += "off: $($disabledFlags.Count) ml prefs" }
        $r.Details += " | " + ($parts -join "; ")
    } elseif ($chatOff -and $sidebarBlocked -and -not $providerSet) {
        Set-ScanStatus $r "Deactivated" "Chatbot off in prefs"
        $r.Details += " | browser.ml.chat.enabled=false"
    } elseif ($masterBlocked -and $blockExcludedOn.Count -gt 0 -and -not $providerSet) {
        Set-ScanStatus $r "Activated" "Block AI on; uncovered features still on"
        $r.Details += " | Block AI on but still on: " + ($blockExcludedOn -join ", ")
    } elseif ($enabledFlags.Count -gt 0 -or $providerSet) {
        Set-ScanStatus $r "Activated" "AI features enabled in prefs"
        $sample = ($enabledFlags | Select-Object -First 4) -join ", "
        $r.Details += " | Enabled: $sample"
        if ($providerSet) { $r.Details += " | chatbot provider set" }
        if ($blockedControls.Count -gt 0) {
            $r.Details += " | Some controls blocked: $($blockedControls.Count)"
        }
    } elseif ($disabledFlags.Count -gt 0 -or $blockedControls.Count -gt 0) {
        Set-ScanStatus $r "Deactivated" "AI prefs set off/blocked"
        $r.Details += " | disabled=$($disabledFlags.Count); blocked=$($blockedControls.Count)"
    } elseif ($profileChecked) {
        if ($ffMajor -gt $ffAiSheetMajor) {
            Set-ScanStatus $r "Unknown" "Firefox $ffMajor not in the AI sheet; defaults not confirmed"
            $r.Details += " | Firefox $ffMajor not in the AI sheet; defaults not confirmed"
        } elseif ($ffHasAiControls) {
            Set-ScanStatus $r "Activated" "No pref overrides; AI Controls default is not blocked"
            $r.Details += " | No pref overrides; AI Controls default is default (not blocked)"
        } elseif ($ffMajor -ge 130) {
            Set-ScanStatus $r "Deactivated" "Optional AI off (no pref overrides)"
            $r.Details += " | No browser.ml overrides in prefs. This version Default on the map is off"
        } else {
            $r.DisableHint = ""
            Set-ScanStatus $r "No AI Features" "No bundled generative AI"
        }
    } else {
        if ($ffHasAiControls) {
            Set-ScanStatus $r "Unknown" "Could not read Firefox prefs"
            $r.Details += " | Could not read settings"
        } elseif ($ffMajor -ge 130) {
            Set-ScanStatus $r "Unknown" "AI setting unknown"
            $r.Details += " | Could not read settings"
        } else {
            Set-ScanStatus $r "No AI Features" "Could not read prefs; this Firefox version has no bundled AI"
            $r.Details += " | Profiles folder missing or empty"
        }
    }

    $labsFact = "unknown"
    $tabsFact = "unknown"
    $previewFact = "unknown"
    $labsOn = ($enabledFlags -contains "browser.ml.chat.enabled") -or
              ($enabledFlags -contains "browser.ml.chat.sidebar") -or
              ($enabledFlags -contains "browser.ml.chat.menu") -or
              ($enabledFlags -contains "browser.ml.chat.page") -or
              $providerSet -or
              ($availableControls -contains "browser.ai.control.sidebarChatbot")
    $labsOff = ($disabledFlags -contains "browser.ml.chat.enabled") -or
               ($blockedControls -contains "browser.ai.control.sidebarChatbot")
    $tabsOn = ($enabledFlags -contains "browser.tabs.groups.smart.enabled") -or
              ($enabledFlags -contains "browser.tabs.groups.smart.userEnabled") -or
              ($availableControls -contains "browser.ai.control.smartTabGroups")
    $tabsOff = ($disabledFlags -contains "browser.tabs.groups.smart.enabled") -or
               ($disabledFlags -contains "browser.tabs.groups.smart.userEnabled") -or
               ($blockedControls -contains "browser.ai.control.smartTabGroups")
    $previewOn = ($enabledFlags -contains "browser.ml.linkPreview.enabled") -or
                 ($enabledFlags -contains "browser.ml.linkPreview.optin") -or
                 ($availableControls -contains "browser.ai.control.linkPreviewKeyPoints")
    $previewOff = ($disabledFlags -contains "browser.ml.linkPreview.enabled") -or
                  ($disabledFlags -contains "browser.ml.linkPreview.optin") -or
                  ($blockedControls -contains "browser.ai.control.linkPreviewKeyPoints")
    $pageAssistOn = ($enabledFlags -contains "browser.ml.pageAssist.enabled")
    $smartAssistOn = ($enabledFlags -contains "browser.ml.smartAssist.enabled")
    $mlCoreOn = ($enabledFlags -contains "browser.ml.enable")
    $extMlOn = ($enabledFlags -contains "extensions.ml.enabled")
    $smartMasterOn = ($enabledFlags -contains "browser.tabs.groups.smart.enabled")
    $smartUserOn = ($enabledFlags -contains "browser.tabs.groups.smart.userEnabled")
    if ($labsOn) { $labsFact = "on" }
    elseif ($labsOff) { $labsFact = "off" }
    if ($tabsOn) { $tabsFact = "on" }
    elseif ($tabsOff) { $tabsFact = "off" }
    if ($previewOn) { $previewFact = "on" }
    elseif ($previewOff) { $previewFact = "off" }

    $optinOn = ($enabledFlags -contains "browser.ml.linkPreview.optin")
    $optinOff = ($disabledFlags -contains "browser.ml.linkPreview.optin")
    $ffOn = @()
    if ($labsOn) { $ffOn += "chatbot" }
    if ($tabsOn) { $ffOn += "tab groups" }
    if ($previewOn) { $ffOn += "link previews" }
    if ($pageAssistOn) { $ffOn += "page assist" }
    if ($smartAssistOn) { $ffOn += "smart assist" }
    if ($optinOn) { $ffOn += "link preview key points" }
    if ($enabledFlags -contains "browser.ai.control.translations") { $ffOn += "translations" }
    if ($enabledFlags -contains "browser.ai.control.pdfjsAltText") { $ffOn += "PDF alt text" }
    if ($enabledFlags -contains "browser.ai.control.smartWindow") { $ffOn += "Smart Window" }
    if ($enabledFlags -contains "browser.ai.control.speechRecognition") { $ffOn += "speech recognition" }
    $ffOn = @($ffOn | Select-Object -Unique)
    if ($ffOn.Count -gt 0 -and [string]$r.Details -notmatch 'On:') {
        $r.Details += " | On: " + ($ffOn -join ", ")
    }

    $disableParts = @()
    if ($labsOn -or ($labsFact -eq "unknown" -and $r.Installed -and $r.Activated -ne "No AI Features")) {
        if ($ffMajor -ge 148) {
            $disableParts += "Firefox Settings > AI Controls > turn on Block AI enhancements (Labs chatbot)"
        } elseif ($ffMajor -ge 136) {
            $disableParts += "Firefox Settings > General > Browser Layout or the sidebar > turn off AI chatbot if listed. Labs AI chatbot is documented for 130-135"
        } elseif ($ffMajor -ge 130) {
            $disableParts += "Firefox Settings > Firefox Labs > turn off AI chatbot"
        }
    }
    if ($tabsOn) {
        if ($ffMajor -ge 147) {
            $disableParts += "Firefox Settings > General > Tabs > Interaction > turn off Use AI to suggest tabs and a name for tab groups"
        } elseif ($ffMajor -ge 143) {
            $disableParts += "Firefox Settings > General > Tabs > turn off Use AI to suggest tabs and a name for tab groups"
        }
    }
    if ($previewOn -or ($enabledFlags -contains "browser.ml.linkPreview.optin")) {
        if ($ffMajor -ge 142) {
            $disableParts += "Firefox Settings > General > Browsing > turn off Enable link previews and Allow AI to generate key points"
        }
    } elseif ($previewFact -eq "unknown" -and $ffMajor -ge 142 -and $ffMajor -le 147 -and $r.Installed) {
        $disableParts += "Firefox Settings > General > Browsing > turn off Enable link previews"
    }
    if ($disableParts.Count -gt 0) {
        $r.DisableHint = ($disableParts -join ". ") + "."
    }

    Move-BrowserPathLast $r
    return $r
}

function Scan-GrokNote {
    $r = New-Result "Grok (xAI)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Grok\Grok.exe",
        "$env:LOCALAPPDATA\Grok\Grok.exe",
        "${env:ProgramFiles}\Grok\Grok.exe"
    )
    $dataPaths = @("$env:APPDATA\Grok")
    $pkgRoot = "$env:LOCALAPPDATA\Packages"
    if (Test-Path $pkgRoot) {
        $grokPkg = Get-ChildItem $pkgRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "Grok*" } |
            Select-Object -First 1
        if ($grokPkg) { $dataPaths += $grokPkg.FullName }
    }
    $data = Test-PathAny $dataPaths
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Grok app found"
    }
    return $r
}

function Scan-Windsurf {
    $r = New-Result "Windsurf"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Windsurf\Windsurf.exe",
        "${env:ProgramFiles}\Windsurf\Windsurf.exe",
        "${env:ProgramFiles(x86)}\Windsurf\Windsurf.exe"
    )
    $data = Test-PathAny @(
        "$env:APPDATA\Windsurf",
        "$env:USERPROFILE\.codeium\windsurf"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Windsurf app found"
    }
    return $r
}

function Get-ModelStorageRoots {
    $roots = @(
        "$env:USERPROFILE\.ollama\models",
        "$env:USERPROFILE\.ollama",
        "$env:USERPROFILE\.lmstudio\models",
        "$env:USERPROFILE\.lmstudio",
        "$env:USERPROFILE\.cache\lm-studio",
        "$env:USERPROFILE\.cache\huggingface",
        "$env:USERPROFILE\.cache\huggingface\hub",
        "$env:LOCALAPPDATA\lm-studio",
        "$env:APPDATA\Jan\data",
        "$env:LOCALAPPDATA\nomic.ai\GPT4All",
        "$env:USERPROFILE\.cache\gpt4all",
        "$env:USERPROFILE\.msty",
        "$env:USERPROFILE\.cache\huggingface\transformers",
        "$env:USERPROFILE\gpt4all",
        "$env:USERPROFILE\models",
        "$env:USERPROFILE\LLM",
        "$env:USERPROFILE\llms",
        "$env:USERPROFILE\Documents\models",
        "C:\models",
        "D:\models"
    )
    if ($env:OLLAMA_MODELS -and (Test-Path $env:OLLAMA_MODELS)) {
        $roots += $env:OLLAMA_MODELS
    }
    if ($env:HF_HOME -and (Test-Path $env:HF_HOME)) {
        $roots += $env:HF_HOME
    }
    return $roots
}

function Get-DedupedModelRoots {
    $raw = @()
    foreach ($r in @(Get-ModelStorageRoots)) {
        if (-not $r) { continue }
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $n = $r.TrimEnd('\', '/')
        if ($raw -notcontains $n) { $raw += $n }
    }
    $kept = @()
    foreach ($r in ($raw | Sort-Object { $_.Length })) {
        $skip = $false
        foreach ($k in $kept) {
            if ($r.Length -gt $k.Length -and $r.StartsWith($k, [System.StringComparison]::OrdinalIgnoreCase)) {
                $next = $r.Substring($k.Length, 1)
                if ($next -eq '\' -or $next -eq '/') { $skip = $true; break }
            }
        }
        if (-not $skip) { $kept += $r }
    }
    return $kept
}

function Set-ScanProgressText {
    param([string]$Text)
    try {
        if ($script:ScanSync) { $script:ScanSync.Status = $Text }
        if ($script:ChromeRecheckPending) { return }
        if ($Text -and $lblStatus) {
            $lblStatus.Text = $Text
        }
    } catch {}
}

function Get-IndexFolderLabel {
    param([string]$Root)
    if (-not $Root) { return "model folders" }
    $low = $Root.ToLowerInvariant()
    if ($low -like "*\documents\models*") { return "Documents\models" }
    if ($low -like "*\documents*") { return "Documents" }
    # Desktop / Downloads labels only if a custom cache (HF_HOME, OLLAMA_MODELS) lives there.
    if ($low -like "*\desktop*") { return "Desktop" }
    if ($low -like "*\downloads*") { return "Downloads" }
    if ($low -match "huggingface|\\hub\\") { return "the Hugging Face cache" }
    if ($low -like "*\.ollama*") { return "Ollama models" }
    if ($low -like "*lm-studio*" -or $low -like "*lmstudio*") { return "LM Studio models" }
    if ($low -match "\\models$") { return $Root }
    $leaf = Split-Path $Root -Leaf
    if ($leaf) { return $leaf }
    return $Root
}

function Initialize-ModelNameIndex {
    if ($null -ne $script:ModelNameIndex) { return }

    $script:ModelGgufCount = 0
    $script:ModelGgufRoots = @()
    $names = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $add = {
        param([string]$n)
        if (-not $n) { return }
        if ($seen.ContainsKey($n)) { return }
        $seen[$n] = $true
        [void]$names.Add($n)
    }

    $indexStarted = Get-Date
    $indexFiles = 0
    $indexMaxFiles = 20000
    $indexMaxSec = 8
    # Time and file caps are checked between folders and every 200 files.
    # One extra folder can still be listed after the cap, then the walk stops.
    # Each folder lists at most 500 children so one huge cache cannot stall.
    $script:ModelIndexIncomplete = $false
    $indexMaxKids = 500
    foreach ($root in @(Get-DedupedModelRoots)) {
        if (Test-ScanCanceled) { break }
        if (((Get-Date) - $indexStarted).TotalSeconds -ge $indexMaxSec) { break }
        if (-not (Test-Path $root)) { continue }
        $rootLabel = Get-IndexFolderLabel $root
        try {
            $rootItem = Get-Item -LiteralPath $root -ErrorAction SilentlyContinue
            if ($rootItem -and ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            Set-ScanProgressText "Checking model files..."
            if (Test-ScanCanceled) { break }
            $dirQueue = New-Object System.Collections.Queue
            $dirQueue.Enqueue(@($root, 0))
            while ($dirQueue.Count -gt 0) {
                if (Test-ScanCanceled) { break }
                if ($indexFiles -ge $indexMaxFiles) { $script:ModelIndexIncomplete = $true; break }
                if (((Get-Date) - $indexStarted).TotalSeconds -ge $indexMaxSec) { $script:ModelIndexIncomplete = $true; break }
                $cur = $dirQueue.Dequeue()
                $dir = [string]$cur[0]
                $depth = [int]$cur[1]
                $kids = New-Object System.Collections.Generic.List[object]
                try {
                    $di = New-Object System.IO.DirectoryInfo($dir)
                    $nKids = 0
                    foreach ($ent in $di.EnumerateFileSystemInfos()) {
                        if (Test-ScanCanceled) { break }
                        $nKids++
                        if ($nKids -gt $indexMaxKids) {
                            $script:ModelIndexIncomplete = $true
                            break
                        }
                        [void]$kids.Add($ent)
                    }
                } catch { continue }
                foreach ($it in $kids) {
                    $isReparse = $false
                    try { $isReparse = [bool]($it.Attributes -band [IO.FileAttributes]::ReparsePoint) } catch {}
                    $isDir = $it -is [System.IO.DirectoryInfo]
                    if ($isDir) {
                        if ($isReparse) { continue }
                        if ($it.Name -match '^(blobs|sha256|\.git)$') { continue }
                        if ($it.Name -notmatch '^(blobs|sha256|\.git)$') { & $add $it.Name }
                        if ($depth -lt 4) { $dirQueue.Enqueue(@($it.FullName, ($depth + 1))) }
                    } else {
                        if ($isReparse) { continue }
                        if ($it.Extension -notmatch '^\.(gguf|safetensors|ggml|bin|ot)$') { continue }
                        if ($it.FullName -like '*\blobs\*' -or $it.FullName -like '*/blobs/*') { continue }
                        if ($it.Name -eq 'weights.bin' -and $it.FullName -notmatch 'OptGuideOnDeviceModel|OptimizationGuide|optimization-guide') { continue }
                        $indexFiles++
                        if (($indexFiles % 200) -eq 0 -and ((Get-Date) - $indexStarted).TotalSeconds -ge $indexMaxSec) {
                            $script:ModelIndexIncomplete = $true
                            break
                        }
                        & $add $it.Name
                        if ($it.Extension -match "^\.(gguf|safetensors|ggml)$") {
                            $script:ModelGgufCount++
                            if ($script:ModelGgufRoots -notcontains $root) { $script:ModelGgufRoots += $root }
                        }
                    }
                }
            }
        } catch {
            Write-ErrorLog "Error indexing models in $rootLabel" -ErrorRecord $_
        }
    }
    if (-not (Test-ScanCanceled)) {
    try {
        $apiTags = @(Get-OllamaInstalledTags)
        foreach ($tag in $apiTags) { & $add $tag }
    } catch {
        Write-ErrorLog "Ollama /api/tags check failed" -ErrorRecord $_
    }
    }

    $script:ModelNameIndex = @($names)
    Write-Log "Model name index size: $($script:ModelNameIndex.Count)"
    if ($script:ModelIndexIncomplete) {
        Write-Log "Model name index incomplete (time or file cap)"
        Set-ScanProgressText "Checking model files... (folder not fully listed)"
    }
}

function Get-CommunityNameLabels {
    param(
        [string[]]$Names,
        [string]$FamilyName = ""
    )
    $map = @(
        @{ Pat = '(?i)huihui'; Label = 'huihui' },
        @{ Pat = '(?i)hauhau'; Label = 'hauhau' },
        @{ Pat = '(?i)abliterat'; Label = 'abliterated' },
        @{ Pat = '(?i)uncensor'; Label = 'uncensored' },
        @{ Pat = '(?i)heretic'; Label = 'heretic' },
        @{ Pat = '(?i)dolphin'; Label = 'dolphin' },
        @{ Pat = '(?i)whiterabbitneo|white-?rabbit-?neo'; Label = 'whiterabbitneo' }
    )
    if ($FamilyName -like "Dolphin*") {
        $map = @($map | Where-Object { $_.Label -ne 'dolphin' })
    }
    $out = @()
    foreach ($item in $map) {
        foreach ($n in @($Names)) {
            if ($n -and ($n -match $item.Pat)) {
                if ($out -notcontains $item.Label) { $out += $item.Label }
                break
            }
        }
    }
    return $out
}

function Find-ModelFamilyOnDisk {
    param(
        [string[]]$Keywords,
        [string]$FamilyName = ""
    )
    Initialize-ModelNameIndex
    if (-not $script:ClaimedModelNames) { $script:ClaimedModelNames = @{} }
    $hits = @()
    $sampleFiles = @()
    foreach ($n in $script:ModelNameIndex) {
        if ($script:ClaimedModelNames.ContainsKey($n)) { continue }
        if ($FamilyName -like "Qwen*" -or $FamilyName -like "Llama*" -or $FamilyName -like "Mistral*" -or $FamilyName -like "Phi*" -or $FamilyName -like "Gemma*") {
            if ($n -match '(?i)deepseek|(?i)r1-distill|(?i)r1_distill|(?i)dolphin') { continue }
        }
        if ($FamilyName -like "Llama*") {
            if ($n -match '(?i)nemotron') { continue }
        }
        foreach ($kw in $Keywords) {
            if ($n -match $kw) {
                $hits += $n
                if ($sampleFiles.Count -lt 5 -and $sampleFiles -notcontains $n) {
                    $sampleFiles += $n
                }
                break
            }
        }
    }
    foreach ($n in $hits) {
        try {
            if ($FamilyName) { $script:ClaimedModelNames[$n] = $FamilyName }
            else { $script:ClaimedModelNames[$n] = $true }
        } catch {}
    }
    $variantHits = @($hits | Where-Object { $_ -match '(?i)huihui|hauhau|abliterat|uncensor|heretic|dolphin|whiterabbitneo|white-?rabbit-?neo' } | Select-Object -Unique)
    $ordered = @()
    foreach ($n in ($variantHits + $hits)) {
        if ($ordered -notcontains $n) { $ordered += $n }
    }
    return [PSCustomObject]@{
        Found = ($hits.Count -gt 0)
        Count = $hits.Count
        Samples = $sampleFiles
        UniqueHints = @($ordered | Select-Object -First 8)
    }
}

function New-ModelFamilyResult {
    param(
        [string]$DisplayName,
        [string[]]$Keywords,
        [string]$ProviderNote = ""
    )
    $r = New-Result $DisplayName
    $r.DisableHint = "Delete the model files shown in Details. If you use Ollama or LM Studio, open that app and remove this model."
    Set-ScanStatus $r "None Found on Disk"
    $search = Find-ModelFamilyOnDisk -Keywords $Keywords -FamilyName $DisplayName
    if ($search.Found) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Model weights found on disk"
        $parts = @()
        if ($ProviderNote) { $parts += $ProviderNote }
        if ($search.UniqueHints.Count -gt 0) {
            $parts += "Matches: " + ($search.UniqueHints -join ", ")
        }
        $labels = @(Get-CommunityNameLabels -Names $search.UniqueHints -FamilyName $DisplayName)
        if ($labels.Count -gt 0) {
            $parts += "Labels: " + ($labels -join ", ")
        }
        $parts += "Hit count: $($search.Count)"
        $r.Details = $parts -join " | "
    } else {
        $r.Details = "No matching model files or tags found"
        # Hits are not marked incomplete. Only a miss after a short walk gets this line.
        if ($script:ModelIndexIncomplete) {
            $r.Details += " | Model folder not fully listed"
        }
    }
    return $r
}

function Scan-Qwen {
    New-ModelFamilyResult -DisplayName "Qwen 3 / 4 (Alibaba)" -ProviderNote "Alibaba open-weight family (3.8-Omni-Flash Sep 2026; 3.8-Max / 27B / Flash-Next Aug 2026)" -Keywords @(
        '(?i)qwen3\.?8-omni-flash-realtime',
        '(?i)qwen3\.?8-omni-flash',
        '(?i)qwen3\.?8-omni',
        '(?i)qwen3-8-omni',
        '(?i)qwen38-omni',
        '(?i)qwen4-coder',
        '(?i)qwen4',
        '(?i)qwen3\.?8-flash-next',
        '(?i)qwen3\.?8-max-0902',
        '(?i)qwen3-8-max',
        '(?i)qwen3\.?8-flash',
        '(?i)qwen3\.?8-max',
        '(?i)qwen3\.?8-27b',
        '(?i)qwen3\.?8-2\.4t',
        '(?i)qwen3\.?8',
        '(?i)qwen3\.?7-plus',
        '(?i)qwen3\.?7-flash',
        '(?i)qwen3\.?7-max',
        '(?i)qwen3\.?7',
        '(?i)qwen3\.?6',
        '(?i)qwen3\.?5',
        '(?i)qwen3-vl',
        '(?i)qwen-vl',
        '(?i)qwen3-next',
        '(?i)qwen3-coder',
        '(?i)qwen3',
        '(?i)qwen2\.?5',
        '(?i)qwen2',
        '(?i)qwen-image-?3',
        '(?i)qwen-image',
        '(?i)qwen-coder',
        '(?i)qwq',
        '(?i)qwen'
    )
}

function Scan-Llama {
    New-ModelFamilyResult -DisplayName "Llama 3 / 4 (Meta)" -ProviderNote "Meta Llama family (Llama 5 not publicly released)" -Keywords @(
        '(?i)llama-?4-?(scout|maverick|behemoth)',
        '(?i)llama4-?(scout|maverick|behemoth)',
        '(?i)llama-?5',
        '(?i)llama-?4',
        '(?i)llama-?3\.3',
        '(?i)llama3\.3',
        '(?i)llama-?3\.2',
        '(?i)llama-?3\.1',
        '(?i)llama3\.2',
        '(?i)llama3\.1',
        '(?i)llama3',
        '(?i)meta-llama',
        '(?i)llama-?2'
    )
}

function Scan-DeepSeek {
    # DeepSeek R1 / V3 / V4 and related names on disk.
    New-ModelFamilyResult -DisplayName "DeepSeek R1 / V4 (DeepSeek)" -ProviderNote "DeepSeek family (R2 not released)" -Keywords @(
        '(?i)deepseek-v4\.1-flash',
        '(?i)deepseek_v4\.1-flash',
        '(?i)deepseek-v4-1-flash',
        '(?i)ds-v4\.1',
        '(?i)deepseek-v4\.1',
        '(?i)deepseek-v4-1-flash',
        '(?i)deepseek-v4-1',
        '(?i)deepseek-v4-flash-vision',
        '(?i)deepseek-v4-pro-0813',
        '(?i)deepseek-v4-flash-0731',
        '(?i)deepseek-v4-pro',
        '(?i)deepseek-v4-flash',
        '(?i)deepseek-v4\.0',
        '(?i)deepseek-v4-0',
        '(?i)deepseek-ocr',
        '(?i)deepseek-r1',
        '(?i)deepseek-v4',
        '(?i)deepseek-v3\.2',
        '(?i)deepseek-v3\.1',
        '(?i)deepseek-v3',
        '(?i)deepseek-coder',
        '(?i)deepseek-llm',
        '(?i)deepseek-moe',
        '(?i)deepseek-chat',
        '(?i)deepseek-reasoner',
        '(?i)deepseek',
        '(?i)r1-distill',
        '(?i)r1_distill',
        '(?i)deepseekr1',
        '(?i)ds-r1',
        '(?i)ds_r1',
        '(?i)ds-v3',
        '(?i)ds-v4',
        '(?i)deepseek-v4pro'
    )
}

function Scan-Gemma {
    New-ModelFamilyResult -DisplayName "Gemma 3 / 4 (Google)" -ProviderNote "Google Gemma family (Gemma 4 12B Unified Jun 2026; no Gemma 5)" -Keywords @(
        '(?i)translategemma',
        '(?i)functiongemma',
        '(?i)diffusiongemma',
        '(?i)vaultgemma',
        '(?i)medgemma-?1\.5',
        '(?i)medgemma',
        '(?i)med-gemma',
        '(?i)gemma-?4\.5',
        '(?i)gemma4-unified',
        '(?i)gemma4-e[24]b',
        '(?i)gemma-?4-31b',
        '(?i)gemma-?4-12b',
        '(?i)gemma-?4-26b',
        '(?i)gemma4-a4b',
        '(?i)gemma-?4',
        '(?i)gemma-?3',
        '(?i)gemma-?2',
        '(?i)gemma4',
        '(?i)gemma3',
        '(?i)gemma2',
        '(?i)gemma-?[0-9]'
    )
}


function Scan-Dolphin {
    New-ModelFamilyResult -DisplayName "Dolphin (Cognitive)" -ProviderNote "Cognitive Computations Dolphin instruct family" -Keywords @(
        '(?i)dolphin-?x1',
        '(?i)dolphin3\.0',
        '(?i)dolphin-?3',
        '(?i)dolphin3',
        '(?i)dolphincoder',
        '(?i)dolphin-?llama',
        '(?i)dolphin-?mistral',
        '(?i)dolphin-?mixtral',
        '(?i)dolphin-?phi',
        '(?i)dolphin-?qwen',
        '(?i)dolphin-?nemo',
        '(?i)dolphin-?yi',
        '(?i)dolphin'
    )
}

function Scan-Ornith {
    New-ModelFamilyResult -DisplayName "Ornith 1.5 (Ornith)" -ProviderNote "Ornith open-weight family (1.5 9B local GGUF pulls)" -Keywords @(
        '(?i)ornith-1\.5',
        '(?i)ornith-1',
        '(?i)ornith'
    )
}

function Scan-Phi {
    New-ModelFamilyResult -DisplayName "Phi-4 (Microsoft)" -ProviderNote "Microsoft Phi family (Phi-5 weights not public)" -Keywords @(
        '(?i)phi-?5',
        '(?i)phi-?4-reasoning-plus',
        '(?i)phi-?4-reasoning-vision',
        '(?i)phi-?4-mini-flash',
        '(?i)phi-?4-mini-reasoning',
        '(?i)phi-?4-reasoning',
        '(?i)phi-?4-multimodal',
        '(?i)phi-?4-mini',
        '(?i)phi-?4',
        '(?i)phi-?3',
        '(?i)phi5',
        '(?i)phi4',
        '(?i)phi3',
        '(?i)phi-mini',
        '(?i)phi-medium'
    )
}

function Scan-Granite {
    New-ModelFamilyResult -DisplayName "Granite 3 / 4 (IBM)" -ProviderNote "IBM Granite open-weight family" -Keywords @(
        '(?i)ibm-granite',
        '(?i)granite-?4',
        '(?i)granite4',
        '(?i)granite-?3',
        '(?i)granite3',
        '(?i)granite-code',
        '(?i)granite-guardian'
    )
}

function Scan-GLM {
    New-ModelFamilyResult -DisplayName "GLM 4.7 / 5 (Zhipu)" -ProviderNote "Zhipu / zai-org GLM family" -Keywords @(
        '(?i)glm-?5\.3-flash',
        '(?i)glm5\.3-flash',
        '(?i)ox-alpha',
        '(?i)glm-?5\.3',
        '(?i)glm-?5\.2',
        '(?i)glm-?5\.1',
        '(?i)glm-?5',
        '(?i)glm-?4\.7',
        '(?i)glm-?4\.6',
        '(?i)glm-?4\.5',
        '(?i)glm-?4',
        '(?i)glm4',
        '(?i)glm5',
        '(?i)chatglm'
    )
}

function Scan-MistralFamily {
    New-ModelFamilyResult -DisplayName "Mistral / Mixtral (Mistral)" -ProviderNote "Mistral AI family" -Keywords @(
        '(?i)mistral-voyage',
        '(?i)voyage-pro',
        '(?i)leanstral',
        '(?i)mistral-small-?4',
        '(?i)mistral-large-?3',
        '(?i)mistral-medium-?3\.5',
        '(?i)mistral-medium',
        '(?i)ministral-?3',
        '(?i)ministral',
        '(?i)magistral',
        '(?i)pixtral',
        '(?i)codestral',
        '(?i)voxtral',
        '(?i)devstral-?2',
        '(?i)devstral',
        '(?i)mixtral',
        '(?i)mistral-nemo',
        '(?i)mistral-large',
        '(?i)mistral-small',
        '(?i)mistral-7b',
        '(?i)mistral'
    )
}

function Scan-GptJPygmalion {
    New-ModelFamilyResult -DisplayName "GPT-J / Pygmalion" -ProviderNote "Older open-weight family (GPT-J 6B / Pygmalion; WormGPT-era backends)" -Keywords @(
        '(?i)gpt-j-6b',
        '(?i)gptj-6b',
        '(?i)gptj6b',
        '(?i)gpt-j',
        '(?i)gptj',
        '(?i)pygmalion-13b',
        '(?i)pygmalion-7b',
        '(?i)pygmalion'
    )
}

function Scan-GptOss {
    # Model used by PromptLock (ESET) via local Ollama API
    New-ModelFamilyResult -DisplayName "gpt-oss (OpenAI)" -ProviderNote "OpenAI gpt-oss family (seen with local Ollama in malware research)" -Keywords @(
        '(?i)gpt-oss',
        '(?i)gpt_oss',
        '(?i)gptoss',
        '(?i)gpt-oss:20b',
        '(?i)gpt-oss-20b',
        '(?i)gpt-oss:120b',
        '(?i)gpt-oss-120b',
        '(?i)gpt-oss-safeguard',
        '(?i)safeguard-20b',
        '(?i)safeguard-120b',
        '(?i)openai-gpt-oss'
    )
}

function Scan-Nemotron {
    New-ModelFamilyResult -DisplayName "Nemotron 3 (NVIDIA)" -ProviderNote "NVIDIA Nemotron open models (local agent use)" -Keywords @(
        '(?i)nemotron-3\.5',
        '(?i)nemotron3\.5',
        '(?i)nemotron-lightning',
        '(?i)nemotron-3-ultra',
        '(?i)nemotron-3-nano',
        '(?i)nemotron-3-super',
        '(?i)nano-omni',
        '(?i)nemotron',
        '(?i)nvidia-nemotron',
        '(?i)nemotron-3',
        '(?i)nemotron-4',
        '(?i)nemotron-mini',
        '(?i)llama-3\.1-nemotron',
        '(?i)llama-3\.3-nemotron'
    )
}

function Scan-MuseGlimmer {
    New-ModelFamilyResult -DisplayName "Muse Glimmer (Meta)" -ProviderNote "Meta Superintelligence Labs (Glimmer open weights; Spark if downloaded)" -Keywords @(
        '(?i)muse-glimmer',
        '(?i)muse_glimmer',
        '(?i)museglimmer',
        '(?i)glimmer-30b',
        '(?i)muse-spark-1\.3',
        '(?i)muse-spark',
        '(?i)muse_spark',
        '(?i)musespark',
        '(?i)muse-voice',
        '(?i)spark-1\.3',
        '(?i)spark-1\.2',
        '(?i)spark-1\.1',
        '(?i)glimmer-30b'
    )
}

function Scan-Kimi {
    New-ModelFamilyResult -DisplayName "Kimi K2 / K3 (Moonshot)" -ProviderNote "Moonshot open-weight family (popular local pulls)" -Keywords @(
        '(?i)kimi-k3',
        '(?i)kimi_k3',
        '(?i)kimi-k2\.7',
        '(?i)kimi-k2\.6',
        '(?i)kimi-k2\.5',
        '(?i)kimi-k2',
        '(?i)kimi-k1',
        '(?i)moonshot-kimi'
    )
}

function Scan-Hunyuan {
    New-ModelFamilyResult -DisplayName "Hunyuan 3 / 4 (Tencent)" -ProviderNote "Tencent Hunyuan open-weight family" -Keywords @(
        '(?i)hunyuan-hy4',
        '(?i)hunyuan-hy3',
        '(?i)hunyuan4',
        '(?i)hunyuan3',
        '(?i)tencent-hunyuan',
        '(?i)hunyuan'
    )
}

function Scan-Ling {
    New-ModelFamilyResult -DisplayName "Ling 3 / 3.1 (Ant)" -ProviderNote "Ant Group inclusionAI Ling open-weight family (Ling-3.1-Flash Oct 2026)" -Keywords @(
        '(?i)ling-3\.1-flash',
        '(?i)ling-3\.1',
        '(?i)ling-3\.0-flash',
        '(?i)ling-3-flash',
        '(?i)ling-3\.0',
        '(?i)ling3\.0',
        '(?i)inclusionai-ling'
    )
}

function Scan-MiniCPM {
    New-ModelFamilyResult -DisplayName "MiniCPM 4 / 5 (ModelBest)" -ProviderNote "On-device / edge open-weight family (MiniCPM5-2B Sep 2026)" -Keywords @(
        '(?i)minicpm-?5',
        '(?i)minicpm5',
        '(?i)minicpm-?4',
        '(?i)minicpm4',
        '(?i)minicpm-2b',
        '(?i)minicpm'
    )
}

function Scan-MiniMax {
    New-ModelFamilyResult -DisplayName "MiniMax M2 / M3 (MiniMax)" -ProviderNote "MiniMax open-weight family (M3 widely pulled in 2026)" -Keywords @(
        '(?i)minimax-m3',
        '(?i)minimax-m2\.7',
        '(?i)minimax-m2\.5',
        '(?i)minimax-m2',
        '(?i)minimax-text',
        '(?i)minimax-vl',
        '(?i)minimax'
    )
}

function Scan-MiMo {
    New-ModelFamilyResult -DisplayName "MiMo V2 (Xiaomi)" -ProviderNote "Xiaomi open-weight family (V2.5 / V2.6 pulls)" -Keywords @(
        '(?i)mimo-v2\.6',
        '(?i)mimo-v2\.5',
        '(?i)mimo-v2',
        '(?i)mimo_v2',
        '(?i)xiaomi-mimo',
        '(?i)xiaomi_mimo'
    )
}

function Get-FoundryUninstallInfo {
    try {
        $hits = @(Get-UninstallApps @("*Foundry Local*", "*FoundryLocal*", "Microsoft.FoundryLocal*"))
    } catch { $hits = @() }
    return ($hits | Select-Object -First 1)
}


function New-UninstallAppsCache {
    $cache = New-Object System.Collections.ArrayList
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $keys) {
        try {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if (-not $item.DisplayName) { continue }
                [void]$cache.Add($item)
            }
        } catch {}
    }
    return @($cache)
}

function Get-UninstallApps {
    param([string[]]$NameLike)
    if ($null -eq $script:UninstallAppsCache) {
        $script:UninstallAppsCache = @(New-UninstallAppsCache)
    }
    $hits = @()
    foreach ($item in @($script:UninstallAppsCache)) {
        $ok = $false
        foreach ($pat in $NameLike) {
            if ($item.DisplayName -like $pat) { $ok = $true; break }
        }
        if ($ok) { $hits += $item }
    }
    return $hits
}

function Scan-FoundryLocal {
    $r = New-Result "Foundry Local"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\FoundryLocal\foundry.exe",
        "${env:ProgramFiles}\Microsoft Foundry Local\foundry.exe",
        "$env:LOCALAPPDATA\FoundryLocal\foundry.exe"
    )
    if (-not $exe) {
        $wg = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
        if (Test-Path $wg) {
            $hit = Get-ChildItem $wg -Directory -Filter "Microsoft.FoundryLocal*" -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ChildItem $_.FullName -Depth 2 -Filter "foundry.exe" -File -ErrorAction SilentlyContinue } |
                Select-Object -First 1
            if ($hit) { $exe = $hit.FullName }
        }
    }
    if (-not $exe) {
        $exe = Get-KnownCommandSource -Name foundry -PathLike @("*\Foundry*\*", "*\Microsoft Foundry Local\*")
    }
    $uninst = Get-FoundryUninstallInfo
    if (-not $exe -and $uninst) {
        $locs = @()
        if ($uninst.InstallLocation) {
            $locs += (Join-Path $uninst.InstallLocation "foundry.exe")
            $locs += (Join-Path $uninst.InstallLocation "bin\foundry.exe")
        }
        if ($uninst.DisplayIcon) {
            $icon = [string]$uninst.DisplayIcon
            if ($icon -match '\.exe') { $locs += ($icon -split ',')[0].Trim('"') }
        }
        if ($locs) { $exe = Test-PathAny $locs }
    }
    $data = Test-PathAny @(
        "$env:USERPROFILE\.foundry",
        "$env:LOCALAPPDATA\Microsoft\FoundryLocal",
        "$env:LOCALAPPDATA\FoundryLocal"
    )
    $regVer = $null
    if ($uninst -and $uninst.DisplayVersion) { $regVer = [string]$uninst.DisplayVersion }

    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $fileVer = Get-FileVersionSafe $exe
        if ($regVer) { $r.Version = $regVer }
        elseif ($fileVer) { $r.Version = $fileVer }
        if ($data) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($uninst) {
        $r.Installed = $true
        $r.Details = "App: $($uninst.DisplayName)"
        if ($regVer) { $r.Version = $regVer }
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe or Apps entry"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Foundry Local app found"
    }
    return $r
}

function Scan-LlamaCpp {
    $r = New-Result "llama.cpp"
    $exes = @(
        "$env:USERPROFILE\llama.cpp\llama-server.exe",
        "$env:USERPROFILE\llama.cpp\llama-cli.exe",
        "$env:USERPROFILE\llama.cpp\main.exe",
        "$env:LOCALAPPDATA\llama.cpp\llama-server.exe",
        "${env:ProgramFiles}\llama.cpp\llama-server.exe",
        "C:\llama.cpp\llama-server.exe",
        "D:\llama.cpp\llama-server.exe"
    )
    $foundExe = Test-PathAny $exes
    if (-not $foundExe) {
        $want = @("llama-server.exe","llama-cli.exe","llama-bench.exe")
        $walkWatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\llama.cpp", "$env:USERPROFILE\llamacpp")) {
            if (Test-ScanCanceled) { break }
            if ($walkWatch.ElapsedMilliseconds -gt 8000) { break }
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            $q = New-Object System.Collections.Queue
            $q.Enqueue(@($dir, 0))
            while ($q.Count -gt 0) {
                if (Test-ScanCanceled) { break }
                if ($walkWatch.ElapsedMilliseconds -gt 8000) { break }
                $cur = $q.Dequeue()
                $here = [string]$cur[0]
                $depth = [int]$cur[1]
                try {
                    $di = New-Object System.IO.DirectoryInfo($here)
                    $nKids = 0
                    foreach ($f in $di.EnumerateFiles()) {
                        if (Test-ScanCanceled) { break }
                        $nKids++
                        if ($nKids -gt 500) { break }
                        if ($want -contains $f.Name) { $foundExe = $f.FullName; break }
                    }
                    if ($foundExe) { break }
                    if ($depth -ge 2) { continue }
                    foreach ($sub in $di.EnumerateDirectories()) {
                        if (Test-ScanCanceled) { break }
                        $nKids++
                        if ($nKids -gt 500) { break }
                        $q.Enqueue(@($sub.FullName, ($depth + 1)))
                    }
                } catch { continue }
            }
            if ($foundExe) { break }
        }
    }
    $folder = Test-PathAny @(
        "$env:USERPROFILE\llama.cpp",
        "$env:USERPROFILE\llamacpp",
        "C:\llama.cpp"
    )
    if (-not $foundExe) {
        $foundExe = Get-KnownCommandSource -Name llama-server -PathLike @("*\llama.cpp\*", "*\llamacpp\*")
    }
    if ($foundExe) {
        $r.Installed = $true
        $r.Details = "App: $foundExe"
        $r.Version = Get-FileVersionSafe $foundExe
        Set-ScanStatus $r "Installed"
    } elseif ($folder) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $folder"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No llama.cpp app found"
    }
    return $r
}

function Scan-Vllm {
    $r = New-Result "vLLM"
    $found = $null
    $leftover = $null

    $userDirs = @(
        "$env:USERPROFILE\vllm",
        "$env:USERPROFILE\vLLM"
    )
    foreach ($d in $userDirs) {
        if (-not (Test-Path $d)) { continue }
        $pkg = $null
        if (Test-Path (Join-Path $d "__init__.py")) { $pkg = $d }
        elseif (Test-Path (Join-Path $d "vllm\__init__.py")) { $pkg = (Join-Path $d "vllm") }
        elseif (Test-Path (Join-Path $d "vllm\engine")) { $pkg = (Join-Path $d "vllm") }
        if ($pkg) { $found = $pkg; break }
        if (-not $leftover) { $leftover = $d }
    }

    if (-not $found) {
        foreach ($g in @(
            "$env:LOCALAPPDATA\Programs\Python\*\Lib\site-packages\vllm",
            "$env:USERPROFILE\AppData\Local\Programs\Python\*\Lib\site-packages\vllm"
        )) {
            $hit = Get-Item $g -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit -and (Test-Path (Join-Path $hit.FullName "__init__.py"))) {
                $found = $hit.FullName
                break
            }
        }
    }

    if (-not $found) {
        $pyRoots = @(
            "$env:LOCALAPPDATA\Programs\Python",
            "$env:USERPROFILE\AppData\Local\Programs\Python",
            "$env:USERPROFILE\miniconda3",
            "$env:USERPROFILE\anaconda3"
        )
        $vllmWatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($root in $pyRoots) {
            if (Test-ScanCanceled) { break }
            if ($vllmWatch.ElapsedMilliseconds -gt 8000) { break }
            if (-not (Test-Path $root)) { continue }
            $dirQueue = New-Object System.Collections.Queue
            $dirQueue.Enqueue(@($root, 0))
            while ($dirQueue.Count -gt 0) {
                if (Test-ScanCanceled) { break }
                if ($vllmWatch.ElapsedMilliseconds -gt 8000) { break }
                $cur = $dirQueue.Dequeue()
                $dir = [string]$cur[0]
                $depth = [int]$cur[1]
                $kids = New-Object System.Collections.Generic.List[object]
                try {
                    $di = New-Object System.IO.DirectoryInfo($dir)
                    $nKids = 0
                    foreach ($ent in $di.EnumerateDirectories()) {
                        if (Test-ScanCanceled) { break }
                        $nKids++
                        if ($nKids -gt 500) { break }
                        [void]$kids.Add($ent)
                    }
                } catch { continue }
                foreach ($it in $kids) {
                    if (Test-ScanCanceled) { break }
                    if ($it.Name -eq "vllm" -and $it.FullName -match 'site-packages\\vllm$' -and (Test-Path -LiteralPath (Join-Path $it.FullName "__init__.py"))) {
                        $found = $it.FullName
                        break
                    }
                    if ($depth -lt 5) { $dirQueue.Enqueue(@($it.FullName, ($depth + 1))) }
                }
                if ($found) { break }
            }
            if ($found) { break }
        }
    }

    if ($found) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Python package present"
        $r.Details = "App: $found"
    } elseif ($leftover) {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no package"
        $r.Details = "Leftover folder; no app: $leftover"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No vLLM app found"
    }
    return $r
}

function Scan-LocalAI {
    $r = New-Result "LocalAI"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\LocalAI\local-ai.exe",
        "$env:LOCALAPPDATA\Programs\LocalAI\localai.exe",
        "$env:LOCALAPPDATA\Programs\localai\local-ai.exe",
        "${env:ProgramFiles}\LocalAI\local-ai.exe",
        "${env:ProgramFiles}\LocalAI\localai.exe",
        "${env:ProgramFiles(x86)}\LocalAI\local-ai.exe"
    )
    if (-not $exe) {
        $un = @(Get-UninstallApps @("LocalAI","Local AI*","local-ai*"))
        foreach ($u in $un) {
            $loc = [string]$u.InstallLocation
            if ($loc) {
                $c1 = Join-Path $loc "local-ai.exe"
                $c2 = Join-Path $loc "localai.exe"
                if (Test-Path -LiteralPath $c1) { $exe = $c1; break }
                if (Test-Path -LiteralPath $c2) { $exe = $c2; break }
            }
        }
    }
    $data = Test-PathAny @(
        "$env:APPDATA\LocalAI",
        "$env:LOCALAPPDATA\LocalAI",
        "$env:USERPROFILE\.localai"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No LocalAI app found"
    }
    return $r
}

function Scan-Llamafile {
    $r = New-Result "Llamafile"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\llamafile\llamafile.exe",
        "$env:USERPROFILE\llamafile\llamafile.exe",
        "${env:ProgramFiles}\llamafile\llamafile.exe"
    )
    if (-not $exe) {
        foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")) {
            if (Test-ScanCanceled) { break }
            if (-not (Test-Path $dir)) { continue }
            $hit = Get-ChildItem $dir -Filter "llamafile.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $hit) {
                $hit = Get-ChildItem $dir -Filter "*.llamafile" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($hit) { $exe = $hit.FullName; break }
        }
    }
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Llamafile app found"
    }
    return $r
}

function Scan-Msty {
    $r = New-Result "Msty"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Msty\Msty.exe",
        "$env:LOCALAPPDATA\Msty\Msty.exe",
        "${env:ProgramFiles}\Msty\Msty.exe",
        "$env:LOCALAPPDATA\Programs\msty\Msty.exe"
    )
    $data = Test-PathAny @(
        "$env:APPDATA\Msty",
        "$env:LOCALAPPDATA\Msty",
        "$env:USERPROFILE\.msty"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Msty app found"
    }
    return $r
}

function Scan-KoboldCpp {
    $r = New-Result "KoboldCPP"
    $exe = Test-PathAny @(
        "$env:USERPROFILE\koboldcpp\koboldcpp.exe",
        "$env:USERPROFILE\KoboldCPP\koboldcpp.exe",
        "$env:LOCALAPPDATA\Programs\KoboldCPP\koboldcpp.exe",
        "${env:ProgramFiles}\KoboldCPP\koboldcpp.exe"
    )
    # Also search common download folders for koboldcpp*.exe (shallow)
    if (-not $exe) {
        foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "C:\koboldcpp", "D:\koboldcpp")) {
            if (Test-ScanCanceled) { break }
            if (-not (Test-Path $dir)) { continue }
            $hit = Get-ChildItem $dir -Filter "koboldcpp*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $exe = $hit.FullName; break }
        }
    }
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No KoboldCPP app found"
    }
    return $r
}

function Scan-OpenWebUI {
    $r = New-Result "Open WebUI"
    $r.DisableHint = "If Open WebUI appears in Windows Settings > Apps, click Uninstall. If you use Docker Desktop, open Docker Desktop and stop or delete the Open WebUI container."
    $folder = Test-PathAny @(
        "$env:USERPROFILE\open-webui",
        "$env:USERPROFILE\OpenWebUI",
        "$env:LOCALAPPDATA\open-webui",
        "$env:APPDATA\open-webui"
    )
    $dot = "$env:USERPROFILE\.open-webui"
    $launcher = $null
    $searchRoots = @()
    if ($folder) { $searchRoots += $folder }
    if (Test-Path $dot) { $searchRoots += $dot }
    foreach ($root in $searchRoots) {
        $hit = Test-PathAny @(
            (Join-Path $root "OpenWebUI.exe"),
            (Join-Path $root "open-webui.exe"),
            (Join-Path $root "docker-compose.yml"),
            (Join-Path $root "docker-compose.yaml")
        )
        if ($hit) { $launcher = $hit; break }
    }
    if (-not $launcher) {
        $launcher = Get-KnownCommandSource -Name open-webui -PathLike @("*\open-webui*", "*\OpenWebUI*")
    }
    $un = $null
    try { $un = Get-UninstallApps @("Open WebUI*") } catch {}
    if ($launcher -or $un) {
        $r.Installed = $true
        if ($launcher) { $r.Details = "App: $launcher" }
        elseif ($un) { $r.Details = "App: $($un[0].DisplayName)" }
        if ($folder) { $r.Details += " | Folder: $folder" }
        elseif (Test-Path $dot) { $r.Details += " | Folder: $dot" }
        Set-ScanStatus $r "Installed"
    } elseif ($folder -or (Test-Path $dot)) {
        $r.Installed = $false
        $where = $(if ($folder) { $folder } else { $dot })
        $r.Details = "Leftover folder; no app: $where"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no launcher"
        $r.DisableHint = ""
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Open WebUI app found"
        $r.DisableHint = ""
    }
    return $r
}

function Scan-AnythingLLM {
    $r = New-Result "AnythingLLM"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\AnythingLLM\AnythingLLM.exe",
        "$env:LOCALAPPDATA\Programs\anythingllm\AnythingLLM.exe",
        "${env:ProgramFiles}\AnythingLLM\AnythingLLM.exe"
    )
    $data = Test-PathAny @(
        "$env:APPDATA\anythingllm-desktop",
        "$env:APPDATA\AnythingLLM",
        "$env:LOCALAPPDATA\anythingllm-desktop"
    )
    if ($exe -and ([string]$exe).Contains("*")) { $exe = $null }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "App: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $data"
        Set-ScanStatus $r "Not Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No AnythingLLM app found"
    }
    return $r
}

function Scan-TextGenWebUI {
    $r = New-Result "text-generation-webui"
    $markers = @(
        "$env:USERPROFILE\text-generation-webui",
        "$env:USERPROFILE\oobabooga",
        "$env:USERPROFILE\Documents\text-generation-webui",
        "C:\text-generation-webui",
        "D:\text-generation-webui"
    )
    $found = Test-PathAny $markers
    $exe = $null
    if ($found) {
        $hit = Get-ChildItem -Path $found -Depth 2 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)^(webui\.py|server\.py|one_click\.py|start_windows\.bat|start_wsl\.bat|oobabooga\.exe)$' } |
            Select-Object -First 1
        if ($hit) { $exe = $hit.FullName }
    }
    if ($exe) {
        $r.Installed = $true
        $r.Details = $(if ($exe) { "App: $exe" } else { "App: $found" })
        Set-ScanStatus $r "Installed" "Install folder present"
    } elseif ($found) {
        $r.Installed = $false
        $r.Details = "Leftover folder; no app: $found"
        Set-ScanStatus $r "Not Installed" "Leftover data folder; no exe"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No text-generation-webui app found"
    }
    return $r
}

function Scan-LocalModels {
    $r = New-Result "Other Local Models"
    Set-ScanStatus $r "None Found on Disk"
    Initialize-ModelNameIndex
    $roots = @(Get-ModelStorageRoots | Where-Object { Test-Path $_ })
    if (-not $script:ClaimedModelNames) { $script:ClaimedModelNames = @{} }
    $left = @()
    foreach ($n in @($script:ModelNameIndex)) {
        if ($n -notmatch "\.(gguf|safetensors|ggml)$") { continue }
        if ($script:ClaimedModelNames.ContainsKey($n)) { continue }
        $left += $n
    }
    $leftCount = @($left).Count
    $foundPaths = @()
    if ($script:ModelGgufRoots) { $foundPaths = @($script:ModelGgufRoots) }
    if ($foundPaths.Count -eq 0) { $foundPaths = @($roots) }

    if ($leftCount -gt 0) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Leftover model files found"
        $pref = @($left | Where-Object { $_ -match '(?i)huihui|hauhau|abliterat|uncensor|heretic|dolphin|whiterabbitneo|white-?rabbit' })
        $orderedLeft = @()
        foreach ($n in ($pref + $left)) { if ($orderedLeft -notcontains $n) { $orderedLeft += $n } }
        $sample = ($orderedLeft | Select-Object -First 4) -join "; "
        $labelTxt = ""
        $labels = @(Get-CommunityNameLabels $orderedLeft)
        if ($labels.Count -gt 0) { $labelTxt = " | Labels: " + ($labels -join ", ") }
        $r.Details = "Leftover model files: $leftCount | Sample: $sample$labelTxt | Folders: " + (($foundPaths | Select-Object -First 4) -join "; ")
    } elseif ($roots.Count -gt 0) {
        Set-ScanStatus $r "None Found on Disk" "Storage folders present; no leftover model files"
        $r.Details = "Leftover model files: 0 | Folders: " + (($roots | Select-Object -First 4) -join "; ")
    } else {
        $r.Details = "No model folders or leftover model files found in standard locations"
    }
    # Incomplete walk is noted here and on family rows that found nothing.
    if ($script:ModelIndexIncomplete) {
        $r.Details = (($r.Details + " | Model folder not fully listed").Trim(" |"))
    }
    return $r
}

function Resize-NameAndDisableColumns {
    param($ListView)
    if (-not $ListView) { return }
    if ($ListView.Columns.Count -lt 7) { return }
    $min0 = 72
    $min6 = 96
    try {
        $g = $ListView.CreateGraphics()
        try {
            $min0 = [Math]::Max($min0, [int]$g.MeasureString($ListView.Columns[0].Text, $ListView.Font).Width + 24)
            $min6 = [Math]::Max($min6, [int]$g.MeasureString($ListView.Columns[6].Text, $ListView.Font).Width + 24)
        } finally { $g.Dispose() }
    } catch {}
    $w0 = [int]$script:ColWidth0
    $w6 = [int]$script:ColWidth6
    if ($w0 -lt $min0) { $w0 = $min0 }
    if ($w6 -lt $min6) { $w6 = $min6 }
    $ListView.Columns[0].Width = $w0
    $ListView.Columns[6].Width = $w6
    $script:ColWidth0 = $w0
    $script:ColWidth6 = $w6
}

function Update-TrackedNameDisableWidth {
    param($ListView, [string]$NameText, [string]$DisableText)
    if (-not $ListView) { return }
    $font = $ListView.Font
    try {
        $g = $script:ColMeasureGraphics
        if (-not $g) {
            $g = $ListView.CreateGraphics()
            $script:ColMeasureGraphics = $g
        }
        if ($NameText) {
            $w = [int]$g.MeasureString($NameText, $font).Width + 24
            if ($w -gt [int]$script:ColWidth0) { $script:ColWidth0 = $w }
        }
        if ($DisableText) {
            $w6 = [int]$g.MeasureString($DisableText, $font).Width + 24
            if ($w6 -gt [int]$script:ColWidth6) { $script:ColWidth6 = $w6 }
        }
    } catch {}
}

function Test-UiAlive {
    try {
        if (-not $form) { return $false }
        if ($form.IsDisposed) { return $false }
        if (-not $form.IsHandleCreated) { return $false }
        if ($lv -and $lv.IsDisposed) { return $false }
        return $true
    } catch {
        return $false
    }
}

function Test-ScanCanceled {
    if ($script:CancelScan) { return $true }
    try {
        if ($script:ScanSync -and $script:ScanSync.Cancel) { return $true }
    } catch {}
    return $false
}

function Request-ScanCancel {
    $script:CancelScan = $true
    try {
        if ($script:ScanSync) { $script:ScanSync.Cancel = $true }
    } catch {}
}

function Stop-PasBackground {
    param([switch]$WaitIfDone)
    try { if ($script:PasBgPS) { $script:PasBgPS.Stop() } } catch {}
    $ms = 250
    if ($WaitIfDone) { $ms = 800 }
    $deadline = [datetime]::UtcNow.AddMilliseconds($ms)
    while ($script:PasBgHandle -and -not $script:PasBgHandle.IsCompleted) {
        if ([datetime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 25
    }
    $done = $false
    try { if ($script:PasBgHandle) { $done = [bool]$script:PasBgHandle.IsCompleted } } catch {}
    if ($done -and $script:PasBgPS -and $script:PasBgHandle) {
        try { [void]$script:PasBgPS.EndInvoke($script:PasBgHandle) } catch {}
    }
    try { if ($script:PasBgPS) { $script:PasBgPS.Dispose() } } catch {}
    try {
        if ($script:PasBgRunspace) {
            $script:PasBgRunspace.Close()
            $script:PasBgRunspace.Dispose()
        }
    } catch {}
    $script:PasBgPS = $null
    $script:PasBgHandle = $null
    $script:PasBgRunspace = $null
}

function Start-PasBackground {
    param([string]$Kind)
    Stop-PasBackground
    if (-not $script:ScanSync) {
        $script:ScanSync = [hashtable]::Synchronized(@{ Cancel = $false })
    }
    $sync = $script:ScanSync
    if ($Kind -eq "appx") {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            try { @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { @() }
        })
        $script:PasBgPS = $ps
        $script:PasBgHandle = $ps.BeginInvoke()
        return $true
    }
    if ($Kind -eq "prep") {
        try {
            $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            foreach ($name in @("New-LoopbackListenOwnerMap", "New-UninstallAppsCache")) {
                $cmd = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
                if (-not $cmd) { continue }
                try {
                    [void]$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($cmd.Name, $cmd.Definition)))
                } catch {}
            }
            $rs = [runspacefactory]::CreateRunspace($iss)
            $rs.ApartmentState = "MTA"
            $rs.ThreadOptions = "ReuseThread"
            $rs.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({
                $listen = @{}
                try { $listen = New-LoopbackListenOwnerMap } catch { $listen = @{} }
                $apps = @()
                try { $apps = @(New-UninstallAppsCache) } catch { $apps = @() }
                return [pscustomobject]@{
                    ListenMap = $listen
                    Uninstall = @($apps)
                }
            })
            $script:PasBgPS = $ps
            $script:PasBgRunspace = $rs
            $script:PasBgHandle = $ps.BeginInvoke()
            return $true
        } catch {
            Write-ErrorLog "Background prep failed to start" -ErrorRecord $_
            Stop-PasBackground
            return $false
        }
    }
    if ($Kind -ne "index") { return $false }
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $need = @(
            "Initialize-ModelNameIndex","Get-DedupedModelRoots","Get-ModelStorageRoots","Get-IndexFolderLabel",
            "Get-OllamaInstalledTags","Test-ScanCanceled","Set-ScanProgressText",
            "Write-Log","Write-ErrorLog","Ensure-LogFile","Initialize-Log",
            "Convert-LocalHttpJson","Get-LocalHttpResponse","Test-LocalPortOpen","Test-LocalAiPortAllowed","Test-PathAny",
            "Get-LoopbackListenOwnerMap","Test-LoopbackListenOwnerName","Test-PortOwnerMatchesProduct","Get-KnownCommandSource"
        )
        foreach ($name in $need) {
            $cmd = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            try {
                [void]$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($cmd.Name, $cmd.Definition)))
            } catch {}
        }
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.ApartmentState = "MTA"
        $rs.ThreadOptions = "ReuseThread"
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $listenMap = $script:ListenOwnerMap
        if ($null -eq $listenMap) { $listenMap = @{} }
        [void]$ps.AddScript({
            param($Sync, $LogDir, $LogPath, $ListenMap)
            $script:ScanSync = $Sync
            $script:CancelScan = [bool]$Sync.Cancel
            $script:LogDir = $LogDir
            $script:LogPath = $LogPath
            $script:ListenOwnerMap = $ListenMap
            $script:ModelNameIndex = $null
            $script:ModelGgufCount = 0
            $script:ModelGgufRoots = @()
            $script:ModelIndexIncomplete = $false
            Initialize-ModelNameIndex
            return [pscustomobject]@{
                Names       = @($script:ModelNameIndex)
                GgufCount   = [int]$script:ModelGgufCount
                GgufRoots   = @($script:ModelGgufRoots)
                Incomplete  = [bool]$script:ModelIndexIncomplete
            }
        }).AddArgument($sync).AddArgument($script:LogDir).AddArgument($script:LogPath).AddArgument($listenMap)
        $script:PasBgPS = $ps
        $script:PasBgRunspace = $rs
        $script:PasBgHandle = $ps.BeginInvoke()
        return $true
    } catch {
        Write-ErrorLog "Background model index failed to start" -ErrorRecord $_
        Stop-PasBackground
        return $false
    }
}

function Test-AppxListUsable {
    param($List)
    foreach ($p in @($List)) {
        if ($null -eq $p) { continue }
        try {
            if ([string]$p.Name) { return $true }
        } catch {}
    }
    return $false
}

function Read-PasBackground {
    if (-not $script:PasBgPS) { return @{ Done = $true; Result = @(); Failed = $true } }
    if ($script:PasBgHandle -and -not $script:PasBgHandle.IsCompleted) {
        return @{ Done = $false; Result = @(); Failed = $false }
    }
    $result = @()
    $failed = $false
    try {
        $inv = $script:PasBgPS.EndInvoke($script:PasBgHandle)
        if ($null -ne $inv) { $result = @($inv) } else { $result = @() }
    } catch {
        $failed = $true
        $result = @()
        Write-ErrorLog "Background scan step failed" -ErrorRecord $_
    }
    try { if ($script:PasBgPS) { $script:PasBgPS.Dispose() } } catch {}
    try {
        if ($script:PasBgRunspace) {
            $script:PasBgRunspace.Close()
            $script:PasBgRunspace.Dispose()
        }
    } catch {}
    $script:PasBgPS = $null
    $script:PasBgHandle = $null
    $script:PasBgRunspace = $null
    return @{ Done = $true; Result = $result; Failed = $failed }
}


function Add-SectionHeaderToListView {
    param($ListView, [string]$Title)
    if (-not (Test-UiAlive)) { return }
    if (-not $ListView -or -not $Title) { return }
    $item = New-Object System.Windows.Forms.ListViewItem($Title)
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.SubItems.Add("") | Out-Null
    $item.ForeColor = [System.Drawing.Color]::DimGray
    $item.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $item.Font = New-Object System.Drawing.Font($ListView.Font, [System.Drawing.FontStyle]::Bold)
    $item.Tag = "section"
    Add-ListViewItemSafe -ListView $ListView -Item $item
    Add-ToLvCache $item
    if (-not $script:SkipListLayout) {
        Update-TrackedNameDisableWidth -ListView $ListView -NameText $Title -DisableText ""
    }
}

function Add-ResultToListView {
    param($ListView, $r)
    if (-not (Test-UiAlive)) { return }
    if (-not $ListView -or -not $r) { return }
    $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
    $item.SubItems.Add( $(if ($r.Installed) { "Yes" } else { "No" }) ) | Out-Null
    $item.SubItems.Add( $r.Running ) | Out-Null
    $item.SubItems.Add( $r.Activated ) | Out-Null
    $item.SubItems.Add( $r.Version ) | Out-Null
    $item.SubItems.Add( $r.Details ) | Out-Null
    $disableText = ""
    if ($r.Installed) {
        $stShow = [string]$r.Activated
        $hideDisable = @("Not Installed", "None Found on Disk", "No AI Features", "Deactivated", "Unknown")
        if ($hideDisable -contains $stShow) {
            $showOff = $false
            if ($r.DisableHint) {
                foreach ($pat in @("Notepad*","Copilot (Microsoft)","Microsoft 365 Copilot*","Paint*","Recall*","Click to Do*","Windows On-Device AI","Microsoft Edge*","Agent in Settings*","File Explorer + AI*")) {
                    if ($r.Name -like $pat) { $showOff = $true; break }
                }
            }
            if ($showOff -and $stShow -eq "Unknown" -and $r.Name -like "Microsoft Edge*") { $showOff = $false }
            if ($showOff -and $stShow -eq "Unknown" -and $r.Name -notlike "Microsoft 365 Copilot*" -and $r.Name -notlike "Paint*" -and $r.Name -notlike "Notepad*") { $showOff = $false }
            if ($showOff) {
                $disableText = [string]$r.DisableHint
            } else {
                $disableText = ""
            }
        } elseif ($r.DisableHint) {
            $disableText = [string]$r.DisableHint
        } else {
            $disableText = Get-HowToDisable -Name $r.Name
        }
    }
    $item.SubItems.Add( $disableText ) | Out-Null
    $tip = @()
    if ($r.Details) { $tip += [string]$r.Details }
    if ($disableText) { $tip += [string]$disableText }
    if ($tip.Count -gt 0) {
        $tipText = $tip -join " | "
        if ($tipText.Length -gt 1000) { $tipText = $tipText.Substring(0, 997) + "..." }
        $item.ToolTipText = $tipText
    }
    if (-not $script:SkipListLayout) {
        Update-TrackedNameDisableWidth -ListView $ListView -NameText $r.Name -DisableText $disableText
    }
    $item.Tag = $r

    $st = [string]$r.Activated
    $runYes = ([string]$r.Running -like "Yes*")
    $aiHot = ($st -eq "Activated" -or $st -eq "Model loaded")
    # Activated includes Copilot / M365 when the app is present and not
    # policy-off. Blue on a stock Win11 PC is intended. Red only if Running.
    if ($runYes -and $aiHot) {
        $item.ForeColor = [System.Drawing.Color]::Firebrick
    } elseif ($aiHot) {
        $item.ForeColor = [System.Drawing.Color]::DarkBlue
    } elseif ($st -eq "Installed" -or $st -eq "Deactivated" -or $st -eq "Unknown") {
        $item.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $item.ForeColor = [System.Drawing.Color]::Gray
    }
    Add-ListViewItemSafe -ListView $ListView -Item $item
    Add-ToLvCache $item
}

function Set-ListViewItemAppearance {
    param($Item, $r)
    if (-not $Item -or -not $r) { return }
    try {
        if ($Item.SubItems.Count -gt 1) { $Item.SubItems[1].Text = $(if ($r.Installed) { "Yes" } else { "No" }) }
        if ($Item.SubItems.Count -gt 2) { $Item.SubItems[2].Text = [string]$r.Running }
        if ($Item.SubItems.Count -gt 3) { $Item.SubItems[3].Text = [string]$r.Activated }
        if ($Item.SubItems.Count -gt 4) { $Item.SubItems[4].Text = [string]$r.Version }
        if ($Item.SubItems.Count -gt 5) { $Item.SubItems[5].Text = [string]$r.Details }
    } catch {}
    $st = [string]$r.Activated
    $runYes = ([string]$r.Running -like "Yes*")
    $aiHot = ($st -eq "Activated" -or $st -eq "Model loaded")
    if ($runYes -and $aiHot) {
        $Item.ForeColor = [System.Drawing.Color]::Firebrick
    } elseif ($aiHot) {
        $Item.ForeColor = [System.Drawing.Color]::DarkBlue
    } elseif ($st -eq "Installed" -or $st -eq "Deactivated" -or $st -eq "Unknown") {
        $Item.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $Item.ForeColor = [System.Drawing.Color]::Gray
    }
}

function Update-LiveListViewRows {
    param($ListView)
    if (-not $ListView) { return }
    $ListView.BeginUpdate()
    try {
        $src = $script:LvCache
        if ($src -and $src.Count -gt 0) {
            foreach ($it in $src) {
                if (-not $it -or $it.Tag -eq "section") { continue }
                $r = $it.Tag
                if (-not $r) { continue }
                Set-ListViewItemAppearance -Item $it -r $r
            }
        } else {
            $n = 0
            try { $n = $ListView.Items.Count } catch { $n = 0 }
            for ($i = 0; $i -lt $n; $i++) {
                $it = Get-ListViewItemAt $ListView $i
                if (-not $it -or $it.Tag -eq "section") { continue }
                $r = $it.Tag
                if (-not $r) { continue }
                Set-ListViewItemAppearance -Item $it -r $r
            }
        }
    } finally {
        try { $ListView.EndUpdate() } catch {}
    }
}

function Enable-ControlDoubleBuffer {
    param($Control)
    if (-not $Control) { return }
    try {
        $flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $prop = $Control.GetType().GetProperty("DoubleBuffered", $flags)
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch {}
}

function Enable-ListViewDoubleBuffer {
    param($ListView)
    if (-not $ListView) { return }
    try {
        $flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $prop = $ListView.GetType().GetProperty("DoubleBuffered", $flags)
        if ($prop) { $prop.SetValue($ListView, $true, $null) }
    } catch {}
    try {
        if (-not $ListView.IsHandleCreated) { return }
        if (-not ("PasListViewNative" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class PasListViewNative {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
"@ -ErrorAction SilentlyContinue
        }
        if ("PasListViewNative" -as [type]) {
            $ex = [IntPtr]0x10000
            [void][PasListViewNative]::SendMessage($ListView.Handle, 0x1036, $ex, $ex)
        }
    } catch {}
}


function Add-ListViewItemSafe {
    param($ListView, $Item)
    if (-not $ListView -or -not $Item) { return }
    if ($script:ScanListHeld) {
        [void]$ListView.Items.Add($Item)
        return
    }
    try {
        $ListView.BeginUpdate()
        [void]$ListView.Items.Add($Item)
    } finally {
        try { $ListView.EndUpdate() } catch {}
    }
}

function Set-ListViewRedraw {
    param($ListView, [bool]$On)
    if (-not $ListView -or -not $ListView.IsHandleCreated) { return }
    try {
        if (-not ("PasListViewNative" -as [type])) { return }
        $w = if ($On) { [IntPtr]1 } else { [IntPtr]::Zero }
        [void][PasListViewNative]::SendMessage($ListView.Handle, 0x000B, $w, [IntPtr]::Zero)
    } catch {}
}

function Start-ScanListHold {
    $script:ScanListHeld = $true
    $script:ScanPaintN = 0
    $script:ScanPaintWatch = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not (Test-UiAlive) -or -not $lv) { return }
    try { $lv.BeginUpdate() } catch {}
    Set-ListViewRedraw -ListView $lv -On $false
}

function Pulse-ScanListPaint {
    if (-not $script:ScanListHeld) { return }
    $script:ScanPaintN = [int]$script:ScanPaintN + 1
    $ms = 0
    if ($script:ScanPaintWatch) { $ms = [int]$script:ScanPaintWatch.ElapsedMilliseconds }
    if ($script:ScanPaintN -lt 5 -and $ms -lt 150) { return }
    $script:ScanPaintN = 0
    if ($script:ScanPaintWatch) { $script:ScanPaintWatch.Restart() }
    if (-not (Test-UiAlive) -or -not $lv) { return }
    Set-ListViewRedraw -ListView $lv -On $true
    try { $lv.EndUpdate() } catch {}
    try { $lv.Update() } catch {}
    try { $lv.BeginUpdate() } catch {}
    Set-ListViewRedraw -ListView $lv -On $false
}

function Stop-ScanListHold {
    if (-not $script:ScanListHeld) { return }
    $script:ScanListHeld = $false
    $script:ScanPaintN = 0
    if (-not (Test-UiAlive) -or -not $lv) { return }
    Set-ListViewRedraw -ListView $lv -On $true
    try { $lv.EndUpdate() } catch {}
    try { $lv.Invalidate() } catch {}
}

function New-LvCache {
    $script:LvCache = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
}

function Add-ToLvCache {
    param($Item)
    if (-not $Item) { return }
    if (-not $script:LvCache) { New-LvCache }
    [void]$script:LvCache.Add($Item)
}

function Get-ListViewItemAt {
    param($ListView, [int]$Index)
    if (-not $ListView) { return $null }
    try {
        if ($Index -lt 0 -or $Index -ge $ListView.Items.Count) { return $null }
        return $ListView.Items[$Index]
    } catch { return $null }
}

function Test-RowIsDetected {
    param($r)
    if (-not $r) { return $false }
    $st = [string]$r.Activated
    return ($st -eq "Installed" -or $st -eq "Deactivated" -or $st -eq "Unknown" -or $st -eq "Activated" -or $st -eq "Model loaded" -or $st -eq "Error")
}

function Update-DetectedButtonStyle {
    if (-not $btnDetected) { return }
    if ($script:FilterDetected) {
        $btnDetected.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $btnDetected.ForeColor = [System.Drawing.Color]::White
        $btnDetected.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 90, 160)
    } else {
        $btnDetected.BackColor = [System.Drawing.SystemColors]::Control
        $btnDetected.ForeColor = [System.Drawing.SystemColors]::ControlText
        $btnDetected.FlatAppearance.BorderColor = [System.Drawing.Color]::Black
    }
    $btnDetected.FlatAppearance.BorderSize = 1
}

function Show-PostScanActionButtons {
    param([bool]$Show)
    foreach ($b in @($btnDetected, $btnExport)) {
        if (-not $b) { continue }
        $b.Visible = $Show
        $b.Enabled = $Show
        try { $b.TabStop = $Show } catch {}
    }
    if ($Show) {
        # Detected last so a neighbor cannot sit on top of it.
        if ($btnExport) { $btnExport.BringToFront() }
        if ($btnDetected) { $btnDetected.BringToFront() }
        try { $btnDetected.Refresh() } catch {}
        try { $btnExport.Refresh() } catch {}
    }
    Update-DetectedButtonStyle
}

function Invoke-DetectedFilterToggle {
    if ($script:FilterBusy) { return }
    if ($script:ScanBusy) { return }
    if (-not $script:HasScanResults) { return }
    if ($btnDetected -and (-not $btnDetected.Visible -or -not $btnDetected.Enabled)) { return }
    $script:FilterBusy = $true
    try {
        $script:FilterDetected = -not $script:FilterDetected
        Update-DetectedButtonStyle
        Apply-DetectedFilterView -ListView $lv
        try { if ($lv -and $lv.IsHandleCreated) { [void]$lv.Focus() } } catch {}
    } finally {
        $script:FilterBusy = $false
    }
}

function Show-ScanRows {
    param($ListView, [switch]$Fast)
    if (-not (Test-UiAlive)) { return }
    if (-not $ListView) { $ListView = $lv }
    if (-not $ListView) { return }
    $prevSkip = [bool]$script:SkipListLayout
    if ($Fast) { $script:SkipListLayout = $true }
    $ListView.BeginUpdate()
    try {
        $ListView.Items.Clear()
        New-LvCache
        $pendingHeader = $null
        foreach ($row in @($script:ScanRows)) {
            if ($row.Kind -eq "section") {
                $pendingHeader = $row.Title
                continue
            }
            $r = $row.Result
            if ($script:FilterDetected -and -not (Test-RowIsDetected $r)) { continue }
            if ($pendingHeader) {
                Add-SectionHeaderToListView -ListView $ListView -Title $pendingHeader
                $pendingHeader = $null
            }
            Add-ResultToListView -ListView $ListView -r $r
        }
    } finally {
        $ListView.EndUpdate()
        $script:SkipListLayout = $prevSkip
    }
    if (-not $Fast) {
        Resize-NameAndDisableColumns -ListView $ListView
        if (-not $script:FilterDetected -and $ListView.Items.Count -gt 0 -and (-not $script:LvCache -or $script:LvCache.Count -lt 1)) {
            Save-ListViewCache -ListView $ListView
        }
    }
}

function Save-ListViewCache {
    param($ListView)
    New-LvCache
    if (-not $ListView) { return }
    $n = 0
    try { $n = $ListView.Items.Count } catch { return }
    for ($i = 0; $i -lt $n; $i++) {
        $it = Get-ListViewItemAt $ListView $i
        if ($it) { [void]$script:LvCache.Add($it) }
    }
}

function Apply-DetectedFilterView {
    param($ListView)
    if (-not $ListView) { $ListView = $lv }
    if (-not $ListView) { return }
    if (-not $script:LvCache -or $script:LvCache.Count -lt 1) {
        Save-ListViewCache -ListView $ListView
    }
    if (-not $script:LvCache -or $script:LvCache.Count -lt 1) { return }
    $batch = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
    $pending = $null
    foreach ($src in $script:LvCache) {
        if (-not $src) { continue }
        if ($src.Tag -eq "section") {
            $pending = $src
            continue
        }
        if ($script:FilterDetected -and -not (Test-RowIsDetected $src.Tag)) { continue }
        if ($pending) {
            [void]$batch.Add($pending)
            $pending = $null
        }
        [void]$batch.Add($src)
    }
    try { Set-ListViewRedraw -ListView $ListView -On $false } catch {}
    try { $ListView.BeginUpdate() } catch {}
    try {
        $ListView.Items.Clear()
        if ($batch.Count -gt 0) {
            [void]$ListView.Items.AddRange($batch.ToArray())
        }
    } catch {
        Write-Log "FILTER: list filter failed, showing current rows"
    } finally {
        try { $ListView.EndUpdate() } catch {}
        try { Set-ListViewRedraw -ListView $ListView -On $true } catch {}
    }
}


function Compare-AppVersionToTag {
    param([string]$AppVer, [string]$Tag)
    $a = ($AppVer -replace '^[vV]', '')
    $t = ($Tag -replace '^[vV]', '')
    try {
        $va = [version]$a
        $vt = [version]$t
        if ($vt -gt $va) { return 1 }
        if ($vt -lt $va) { return -1 }
        return 0
    } catch {
        if ($t -eq $a) { return 0 }
        return 2
    }
}

function Stop-UpdateBackground {
    try {
        if ($script:UpdHandle -and $script:UpdPs) {
            if ($script:UpdHandle.IsCompleted) {
                try { [void]$script:UpdPs.EndInvoke($script:UpdHandle) } catch {}
            } else {
                try { $script:UpdPs.Stop() } catch {}
                try { [void]$script:UpdPs.EndInvoke($script:UpdHandle) } catch {}
            }
        }
    } catch {}
    try { if ($script:UpdPs) { $script:UpdPs.Dispose() } } catch {}
    $script:UpdPs = $null
    $script:UpdHandle = $null
    try { if ($timerUpdate) { $timerUpdate.Stop() } } catch {}
}

function Apply-UpdateCheckResult {
    param($Snap)
    if (-not $btnUpdate) { return }
    if (-not $Snap -or -not $Snap.Tag) {
        $btnUpdate.Text = "Could not check"
        $script:UpdateUrl = ""
        Write-Log "UPDATE: failed"
        return
    }
    $cmp = Compare-AppVersionToTag $script:AppVersion ([string]$Snap.Tag)
    $verNum = ([string]$Snap.Tag) -replace '^[vV]', ''
    if (-not $verNum) { $verNum = "unknown" }
    $shown = "v$verNum"
    $html = [string]$Snap.HtmlUrl
    $allow = "https://github.com/" + $script:GitHubRepo + "/releases/"
    if ($html -and $html.StartsWith($allow)) { $script:UpdateUrl = $html } else { $script:UpdateUrl = $allow + "latest" }
    $btnUpdate.Font = New-Object System.Drawing.Font($form.Font.FontFamily, $form.Font.Size, [System.Drawing.FontStyle]::Bold)
    if ($cmp -eq 1) {
        $btnUpdate.Text = "Download $shown"
        Write-Log "UPDATE: new $shown"
    } elseif ($cmp -eq 0) {
        $btnUpdate.Text = "Found: $shown (Latest)"
        Write-Log "UPDATE: latest $shown"
    } elseif ($cmp -eq -1) {
        $btnUpdate.Text = "Found: $shown (Old)"
        Write-Log "UPDATE: old $shown"
    } else {
        $btnUpdate.Text = "Found: $shown"
        Write-Log "UPDATE: tag $shown"
    }
}

function Start-UpdateBackground {
    if ($script:UpdHandle -and -not $script:UpdHandle.IsCompleted) { return }
    Stop-UpdateBackground
    $repo = [string]$script:GitHubRepo
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            param($Repo)
            $url = "https://api.github.com/repos/$Repo/releases/latest"
            $page = "https://github.com/$Repo/releases/latest"
            $resp = $null
            $stream = $null
            $ms = $null
            $tlsPrev = $null
            try {
                $tlsPrev = [System.Net.ServicePointManager]::SecurityProtocol
                try { [System.Net.ServicePointManager]::SecurityProtocol = $tlsPrev -bor [System.Net.SecurityProtocolType]::Tls12 } catch {}
                $req = [System.Net.HttpWebRequest]::Create($url)
                $req.Method = "GET"
                $req.UserAgent = "PortableAIScanner"
                $req.Timeout = 8000
                $req.ReadWriteTimeout = 8000
                $req.AllowAutoRedirect = $false
                $req.Accept = "application/vnd.github+json"
                $resp = $req.GetResponse()
                $maxBytes = 65536
                try {
                    if ($resp.ContentLength -gt $maxBytes) { return $null }
                } catch {}
                $stream = $resp.GetResponseStream()
                $ms = New-Object System.IO.MemoryStream
                $buf = New-Object byte[] 4096
                $total = 0
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    $total += $n
                    if ($total -gt $maxBytes) { return $null }
                    $ms.Write($buf, 0, $n)
                }
                $json = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                if (-not $json) { return $null }
                $obj = $json | ConvertFrom-Json
                $tag = [string]$obj.tag_name
                if (-not $tag) { return $null }
                $html = [string]$obj.html_url
                $allow = "https://github.com/$Repo/releases/"
                if (-not $html -or -not $html.StartsWith($allow)) { $html = $page }
                return [pscustomobject]@{ Tag = $tag; HtmlUrl = $html }
            } catch {
                return $null
            } finally {
                if ($ms) { try { $ms.Dispose() } catch {} }
                if ($stream) { try { $stream.Close() } catch {} }
                if ($resp) { try { $resp.Close() } catch {} }
                if ($null -ne $tlsPrev) {
                    try { [System.Net.ServicePointManager]::SecurityProtocol = $tlsPrev } catch {}
                }
            }
        }).AddArgument($repo)
        $script:UpdPs = $ps
        $script:UpdHandle = $ps.BeginInvoke()
        if ($timerUpdate) { $timerUpdate.Start() }
    } catch {
        $script:UpdPs = $null
        $script:UpdHandle = $null
        if ($btnUpdate) { $btnUpdate.Text = "Could not check" }
    }
}

function Poll-UpdateBackground {
    if (-not $script:UpdHandle) {
        try { if ($timerUpdate) { $timerUpdate.Stop() } } catch {}
        return
    }
    if (-not $script:UpdHandle.IsCompleted) { return }
    $snap = $null
    try {
        $inv = $script:UpdPs.EndInvoke($script:UpdHandle)
        if ($inv -and @($inv).Count -gt 0) { $snap = @($inv)[-1] }
    } catch {}
    try { if ($script:UpdPs) { $script:UpdPs.Dispose() } } catch {}
    $script:UpdPs = $null
    $script:UpdHandle = $null
    try { if ($timerUpdate) { $timerUpdate.Stop() } } catch {}
    Apply-UpdateCheckResult $snap
}

function Stop-GpuBackground {
    try {
        if ($script:GpuHandle -and $script:GpuPs) {
            if ($script:GpuHandle.IsCompleted) {
                try { [void]$script:GpuPs.EndInvoke($script:GpuHandle) } catch {}
            } else {
                try { $script:GpuPs.Stop() } catch {}
                try { [void]$script:GpuPs.EndInvoke($script:GpuHandle) } catch {}
            }
        }
    } catch {}
    try { if ($script:GpuPs) { $script:GpuPs.Dispose() } } catch {}
    $script:GpuPs = $null
    $script:GpuHandle = $null
}

function Apply-GpuSnapshot {
    param($Snap)
    if (-not $lblGpu) { return }
    $util = -1.0
    $gpuUsed = 0.0
    try { if ($null -ne $Snap.Util) { $util = [double]$Snap.Util } } catch {}
    try { if ($null -ne $Snap.Used) { $gpuUsed = [double]$Snap.Used } } catch {}
    if ($util -lt 0 -and $gpuUsed -le 0) {
        $script:GpuFailCount = [int]$script:GpuFailCount + 1
        $lblGpu.Text = "GPU: --"
        $lblGpu.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
        if ($script:GpuFailCount -ge 2 -and $timerGpu) {
            try { $timerGpu.Stop() } catch {}
            Stop-GpuBackground
        }
        return
    }
    $script:GpuFailCount = 0
    $utilText = "n/a"
    if ($util -ge 0) { $utilText = ("{0:N0}%" -f $util) }
    $memText = "n/a"
    if ($gpuUsed -gt 0) {
        $memText = ("{0:N1} GB" -f [math]::Round($gpuUsed / 1GB, 1))
    }
    $lblGpu.Text = "GPU Utilization: $utilText    GPU Memory: $memText"
    $lblGpu.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
}

function Start-GpuBackground {
    if ($script:GpuHandle -and -not $script:GpuHandle.IsCompleted) { return }
    if ($script:GpuHandle -and $script:GpuHandle.IsCompleted) {
        try { [void]$script:GpuPs.EndInvoke($script:GpuHandle) } catch {}
        try { if ($script:GpuPs) { $script:GpuPs.Dispose() } } catch {}
        $script:GpuPs = $null
        $script:GpuHandle = $null
    }
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            $util = -1.0
            $dedUsed = 0.0
            $shaUsed = 0.0
            try {
                $engines = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
                foreach ($eng in $engines) {
                    $n = ""
                    try { $n = [string]$eng.Name } catch {}
                    if ($n -notmatch 'engtype_3D|engtype_Compute') { continue }
                    $p = 0.0
                    try { $p = [double]$eng.UtilizationPercentage } catch {}
                    if ($p -gt $util) { $util = $p }
                }
            } catch {}
            try {
                $rows = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop)
                foreach ($row in $rows) {
                    $d = 0.0
                    $s = 0.0
                    try { $d = [double]$row.DedicatedUsage } catch {}
                    try { $s = [double]$row.SharedUsage } catch {}
                    $sum = $d + $s
                    if ($sum -ge ($dedUsed + $shaUsed)) {
                        $dedUsed = $d
                        $shaUsed = $s
                    }
                }
            } catch {}
            return [pscustomobject]@{ Util = $util; Used = ($dedUsed + $shaUsed) }
        })
        $script:GpuPs = $ps
        $script:GpuHandle = $ps.BeginInvoke()
    } catch {
        $script:GpuPs = $null
        $script:GpuHandle = $null
    }
}

function Update-GpuLabel {
    if (-not $lblGpu) { return }
    if ($script:GpuHandle -and $script:GpuHandle.IsCompleted) {
        $snap = $null
        try {
            $inv = $script:GpuPs.EndInvoke($script:GpuHandle)
            if ($inv -and @($inv).Count -gt 0) { $snap = @($inv)[-1] }
        } catch {}
        try { if ($script:GpuPs) { $script:GpuPs.Dispose() } } catch {}
        $script:GpuPs = $null
        $script:GpuHandle = $null
        if ($snap) { Apply-GpuSnapshot $snap }
        else { Apply-GpuSnapshot ([pscustomobject]@{ Util = -1.0; Used = 0.0 }) }
    }
    if ($script:GpuFailCount -ge 2) { return }
    if (-not $script:GpuHandle) { Start-GpuBackground }
}

function Move-UpdateControls {
    try {
        if (-not $form -or -not $btnUpdate) { return }
        $btnUpdate.Top = 10
        $btnUpdate.Left = $form.ClientSize.Width - 16 - $btnUpdate.Width
        if ($lblGpu) {
            $lblGpu.AutoEllipsis = $true
            $titleRight = 20
            if ($lblTitle) { $titleRight = $lblTitle.Right }
            $maxW = $btnUpdate.Left - $titleRight - 16
            if ($maxW -lt 80) { $maxW = 80 }
            if ($maxW -gt 430) { $maxW = 430 }
            $lblGpu.Width = $maxW
            $lblGpu.Top = 14
            $lblGpu.Left = $btnUpdate.Left - 10 - $lblGpu.Width
        }
        if ($progress -and $lblBarEnd) {
            $rightPad = 8
            $gap = 2
            $lblBarEnd.Width = 48
            $lblBarEnd.Height = 16
            $lblBarEnd.Top = $progress.Top
            $lblBarEnd.Left = $form.ClientSize.Width - $rightPad - $lblBarEnd.Width
            $barW = $lblBarEnd.Left - $progress.Left - $gap
            if ($barW -lt 80) { $barW = 80 }
            $progress.Width = $barW
            if ($lblStatus) {
                $lblStatus.Width = ($lblBarEnd.Left + $lblBarEnd.Width) - $lblStatus.Left
                if ($lblStatus.Width -lt 80) { $lblStatus.Width = 80 }
            }
        }
    } catch {}
}

function Set-ScanBarEnd {
    param([int]$Percent = -1)
    if (-not (Test-UiAlive)) { return }
    if ($Percent -lt 0) { return }
    $p = $Percent
    if ($p -gt 100) { $p = 100 }
    if ($progress) {
        try { $progress.Value = $p } catch {}
    }
    if ($lblBarEnd) { $lblBarEnd.Text = "$p%" }
}

function Get-ScanStepLabel {
    param([string]$Hint)
    $key = [string]$Hint
    if ($key -like "Scan-*") { $key = $key.Substring(5) }
    $map = @{
        "ChatGPT" = "ChatGPT (OpenAI)"
        "Claude" = "Claude (Anthropic)"
        "GeminiDesktop" = "Gemini (Google)"
        "GrokNote" = "Grok (xAI)"
        "Copilot" = "Copilot (Microsoft)"
        "Ollama" = "Ollama"
        "Perplexity" = "Perplexity"
        "DeepSeek" = "DeepSeek R1 / V4 (DeepSeek)"
        "Gemma" = "Gemma 3 / 4 (Google)"
        "Granite" = "Granite 3 / 4 (IBM)"
        "GLM" = "GLM 4.7 / 5 (Zhipu)"
        "GptOss" = "gpt-oss (OpenAI)"
        "GptJPygmalion" = "GPT-J / Pygmalion"
        "Hunyuan" = "Hunyuan 3 / 4 (Tencent)"
        "Kimi" = "Kimi K2 / K3 (Moonshot)"
        "Ling" = "Ling 3 / 3.1 (Ant)"
        "Llama" = "Llama 3 / 4 (Meta)"
        "MiniCPM" = "MiniCPM 4 / 5 (ModelBest)"
        "MiniMax" = "MiniMax M2 / M3 (MiniMax)"
        "MistralFamily" = "Mistral / Mixtral (Mistral)"
        "MuseGlimmer" = "Muse Glimmer (Meta)"
        "Nemotron" = "Nemotron 3 (NVIDIA)"
        "Ornith" = "Ornith 1.5 (Ornith)"
        "Dolphin" = "Dolphin (Cognitive)"
        "Phi" = "Phi-4 (Microsoft)"
        "Qwen" = "Qwen 3 / 4 (Alibaba)"
        "LocalModels" = "Other Local Models"
        "BraveLeo" = "Brave + Leo"
        "GeminiChrome" = "Google Chrome + Gemini"
        "EdgeCopilot" = "Microsoft Edge + Copilot"
        "Firefox" = "Mozilla Firefox + AI"
        "OperaAI" = "Opera + Aria"
        "Comet" = "Perplexity Comet + AI"
        "FoundryLocal" = "Foundry Local"
        "GitHubCopilot" = "GitHub Copilot"
        "M365Copilot" = "Microsoft 365 Copilot"
        "NotepadAI" = "Notepad + AI"
        "PaintAI" = "Paint + AI"
        "WindowsAIComponents" = "Windows On-Device AI"
        "AnythingLLM" = "AnythingLLM"
        "ChatRTX" = "ChatRTX (NVIDIA)"
        "CherryStudio" = "Cherry Studio"
        "ClaudeCode" = "Claude Code (Anthropic)"
        "ComfyUI" = "ComfyUI"
        "Cursor" = "Cursor"
        "GAssist" = "G-Assist (NVIDIA)"
        "GPT4All" = "GPT4All"
        "Jan" = "Jan"
        "KoboldCpp" = "KoboldCPP"
        "LibreChat" = "LibreChat"
        "LlamaCpp" = "llama.cpp"
        "Llamafile" = "Llamafile"
        "LocalAI" = "LocalAI"
        "LMStudio" = "LM Studio"
        "Msty" = "Msty"
        "OpenWebUI" = "Open WebUI"
        "TextGenWebUI" = "text-generation-webui"
        "Vllm" = "vLLM"
        "Windsurf" = "Windsurf"
        "Recall" = "Recall (Windows)"
        "SettingsAgent" = "Agent in Settings (Windows)"
        "FileExplorerAI" = "File Explorer + AI"
        "ClickToDo" = "Click to Do (Windows)"
        "MiMo" = "MiMo V2 (Xiaomi)"
    }
    if ($map.ContainsKey($key)) { return [string]$map[$key] }
    if ($Hint) { return [string]$Hint }
    return "item"
}

function Test-FamilyRowWiring {
    $rows = @(
        @{ Name = "Qwen 3 / 4 (Alibaba)"; Scan = "Qwen"; Needle = "qwen3" },
        @{ Name = "Llama 3 / 4 (Meta)"; Scan = "Llama"; Needle = "llama-3" },
        @{ Name = "DeepSeek R1 / V4 (DeepSeek)"; Scan = "DeepSeek"; Needle = "deepseek" },
        @{ Name = "Gemma 3 / 4 (Google)"; Scan = "Gemma"; Needle = "gemma" },
        @{ Name = "Dolphin (Cognitive)"; Scan = "Dolphin"; Needle = "dolphin" },
        @{ Name = "Phi-4 (Microsoft)"; Scan = "Phi"; Needle = "phi-4" },
        @{ Name = "Granite 3 / 4 (IBM)"; Scan = "Granite"; Needle = "granite" },
        @{ Name = "GLM 4.7 / 5 (Zhipu)"; Scan = "GLM"; Needle = "glm" },
        @{ Name = "Mistral / Mixtral (Mistral)"; Scan = "MistralFamily"; Needle = "mistral" },
        @{ Name = "GPT-J / Pygmalion"; Scan = "GptJPygmalion"; Needle = "gpt-j" },
        @{ Name = "gpt-oss (OpenAI)"; Scan = "GptOss"; Needle = "gpt-oss" },
        @{ Name = "Nemotron 3 (NVIDIA)"; Scan = "Nemotron"; Needle = "nemotron-3" },
        @{ Name = "Muse Glimmer (Meta)"; Scan = "MuseGlimmer"; Needle = "muse-glimmer" },
        @{ Name = "Kimi K2 / K3 (Moonshot)"; Scan = "Kimi"; Needle = "kimi" },
        @{ Name = "Hunyuan 3 / 4 (Tencent)"; Scan = "Hunyuan"; Needle = "hunyuan" },
        @{ Name = "Ling 3 / 3.1 (Ant)"; Scan = "Ling"; Needle = "ling-3.1" },
        @{ Name = "Ornith 1.5 (Ornith)"; Scan = "Ornith"; Needle = "ornith-1.5" },
        @{ Name = "MiniCPM 4 / 5 (ModelBest)"; Scan = "MiniCPM"; Needle = "minicpm" },
        @{ Name = "MiniMax M2 / M3 (MiniMax)"; Scan = "MiniMax"; Needle = "minimax" },
        @{ Name = "MiMo V2 (Xiaomi)"; Scan = "MiMo"; Needle = "mimo-v2.5" }
    )
    foreach ($row in $rows) {
        $miss = @()
        $label = ""
        try { $label = [string](Get-ScanStepLabel $row.Scan) } catch { $label = "" }
        if (-not $label -or $label -eq [string]$row.Scan -or $label -like "Scan-*") {
            $miss += "label"
        }
        $run = "No"
        try {
            $run = [string](Test-IsRunning -AiName $row.Name -OllamaLoadedModels @($row.Needle))
        } catch { $run = "No" }
        if ($run -notlike "Yes*") { $miss += "running" }
        $claimed = @()
        try {
            $claimed = @(Get-LoadedModelsMatching -Loaded @($row.Needle) -Patterns @(Get-KnownFamilyPatterns))
        } catch { $claimed = @() }
        if ($claimed -notcontains $row.Needle) { $miss += "patterns" }
        $hint = ""
        try { $hint = [string](Get-HowToDisable -Name $row.Name) } catch { $hint = "" }
        if (-not $hint -or $hint -like "*find this app*") { $miss += "hint" }
        if ($miss.Count -gt 0) {
            Write-Log ("LOAD: family wiring miss " + $row.Name + " [" + ($miss -join ",") + "]")
        }
    }
}

# ========== GUI ==========
Write-Log "LOAD: building window"
try { Test-FamilyRowWiring } catch { Write-Log "LOAD: family wiring check failed" }

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName v$script:AppVersion Build $script:AppBuild"
$form.Size = New-Object System.Drawing.Size(900, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
# Start maximized on purpose. Size and MinimumSize apply after Restore.
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
try { Enable-ControlDoubleBuffer -Control $form } catch {}

$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Height = 122
$pnlTop.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlTop.TabStop = $false
try { Enable-ControlDoubleBuffer -Control $pnlTop } catch {}

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "$script:AppName"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.AutoSize = $true
$pnlTop.Controls.Add($lblTitle)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = "Check for update"
$btnUpdate.Size = New-Object System.Drawing.Size(178, 28)
$btnUpdate.Location = New-Object System.Drawing.Point(700, 10)
$btnUpdate.FlatStyle = "Flat"
$btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.TextAlign = "MiddleCenter"
$btnUpdate.Anchor = "Top, Right"
$script:UpdateUrl = ""
$pnlTop.Controls.Add($btnUpdate)

$lblOS = New-Object System.Windows.Forms.Label
$lblOS.Text = "Windows: " + (Get-WindowsVersionInfo)
$lblOS.Location = New-Object System.Drawing.Point(20, 48)
$lblOS.Size = New-Object System.Drawing.Size(760, 22)
$lblOS.ForeColor = [System.Drawing.Color]::DarkBlue
$pnlTop.Controls.Add($lblOS)

$script:FilterDetected = $false
$script:FilterBusy = $false
$script:SkipListLayout = $false
$script:LvCache = $null
$script:ScanRows = @()
$script:HasScanResults = $false
$script:ScanBusy = $false
$script:ScanPass = 0
$script:ChromeRecheckTimer = $null
$script:ChromeRecheckPending = $false
$script:ChromeRecheckStep = 0
$script:ChromeStatusBaseline = ""
$script:ScanBeganAt = $null
$script:LastScanSummary = ""
$script:GpuFailCount = 0

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Scan"
$btnScan.Location = New-Object System.Drawing.Point(20, 78)
$btnScan.Size = New-Object System.Drawing.Size(90, 34)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = "Flat"
$btnScan.Anchor = "Top, Left"
$btnScan.Enabled = $true
$btnScan.TabStop = $true
$btnScan.TabIndex = 0
$pnlTop.Controls.Add($btnScan)
$form.AcceptButton = $btnScan

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(116, 78)
$btnCancel.Size = New-Object System.Drawing.Size(80, 34)
$btnCancel.FlatStyle = "Flat"
$btnCancel.Anchor = "Top, Left"
$btnCancel.Visible = $false
$btnCancel.Enabled = $false
$pnlTop.Controls.Add($btnCancel)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export list"
$btnExport.Location = New-Object System.Drawing.Point(296, 78)
$btnExport.Size = New-Object System.Drawing.Size(100, 34)
$btnExport.FlatStyle = "Flat"
$btnExport.Anchor = "Top, Left"
$btnExport.Visible = $false
$btnExport.Enabled = $false
$pnlTop.Controls.Add($btnExport)

$btnDetected = New-Object System.Windows.Forms.Button
$btnDetected.Text = "Detected"
$btnDetected.Location = New-Object System.Drawing.Point(202, 78)
$btnDetected.Size = New-Object System.Drawing.Size(88, 34)
$btnDetected.FlatStyle = "Flat"
$btnDetected.FlatAppearance.BorderSize = 1
$btnDetected.FlatAppearance.BorderColor = [System.Drawing.Color]::Black
$btnDetected.Anchor = "Top, Left"
$btnDetected.Visible = $false
$btnDetected.Enabled = $false
$pnlTop.Controls.Add($btnDetected)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(408, 78)
$lblStatus.Size = New-Object System.Drawing.Size(452, 18)
$lblStatus.Anchor = "Top, Left, Right"
$pnlTop.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(408, 98)
$progress.Size = New-Object System.Drawing.Size(382, 16)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Style = "Continuous"
$progress.Anchor = "Top, Left, Right"
$pnlTop.Controls.Add($progress)

$lblBarEnd = New-Object System.Windows.Forms.Label
$lblBarEnd.Text = ""
$lblBarEnd.Location = New-Object System.Drawing.Point(816, 98)
$lblBarEnd.Size = New-Object System.Drawing.Size(48, 16)
$lblBarEnd.TextAlign = "MiddleLeft"
$lblBarEnd.Anchor = "Top, Right"
$lblBarEnd.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$pnlTop.Controls.Add($lblBarEnd)

$lblGpu = New-Object System.Windows.Forms.Label
$lblGpu.Text = "GPU Utilization: ...    GPU Memory: ..."
$lblGpu.Location = New-Object System.Drawing.Point(300, 14)
$lblGpu.Size = New-Object System.Drawing.Size(430, 22)
$lblGpu.TextAlign = "MiddleRight"
$lblGpu.Anchor = "Top, Right"
$lblGpu.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$pnlTop.Controls.Add($lblGpu)

$timerGpu = New-Object System.Windows.Forms.Timer
$timerGpu.Interval = 2000
$timerGpu.Add_Tick({ Update-GpuLabel })

$timerUpdate = New-Object System.Windows.Forms.Timer
$timerUpdate.Interval = 250
$timerUpdate.Add_Tick({ Poll-UpdateBackground })

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 125)
$lv.Size = New-Object System.Drawing.Size(840, 450)
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.ShowItemToolTips = $true
$lv.Dock = [System.Windows.Forms.DockStyle]::Fill
$lv.Columns.Add("AI Name", 170) | Out-Null
$lv.Columns.Add("Installed", 58) | Out-Null
$lv.Columns.Add("Running", 58) | Out-Null
$lv.Columns.Add("Status", 160) | Out-Null
$lv.Columns.Add("Version", 120) | Out-Null
$lv.Columns.Add("Details", 120) | Out-Null
$lv.Columns.Add("How to disable", 640) | Out-Null
try { Enable-ListViewDoubleBuffer -ListView $lv } catch {}
$form.Controls.Add($lv)
$form.Controls.Add($pnlTop)

$form.Add_Shown({
    try { Enable-ListViewDoubleBuffer -ListView $lv } catch {}
    Resize-NameAndDisableColumns -ListView $lv
    try { Move-UpdateControls } catch {}
    try {
        if ($timerGpu -and -not $timerGpu.Enabled) { $timerGpu.Start() }
        Start-GpuBackground
    } catch {}
    try {
        $form.Activate()
        if (-not $script:ScanBusy -and $btnScan) {
            $btnScan.Enabled = $true
            $btnScan.Visible = $true
            $btnScan.Select()
        }
    } catch {}
})
$form.Add_Resize({ try { Move-UpdateControls } catch {} })
$form.Add_FormClosing({
    # Window is allowed to close. Cancel is set. Leftover scan work must not touch the window.
    try { Stop-ChromeSettingsRecheck } catch {}
    if ($script:ScanBusy) {
        Request-ScanCancel
        try { Write-Log "SCAN: window closing, cancel requested" } catch {}
        try { if ($script:ScanTimer) { $script:ScanTimer.Stop() } } catch {}
        Stop-PasBackground
    }
})


$lv.Add_SelectedIndexChanged({
    if ($lv.SelectedItems.Count -gt 0 -and $lv.SelectedItems[0].Tag -eq "section") {
        $lv.SelectedItems.Clear()
    }
})

$cmsCopy = New-Object System.Windows.Forms.ContextMenuStrip
$miCopyRow = New-Object System.Windows.Forms.ToolStripMenuItem
$miCopyRow.Text = "Copy row"
$miCopyRow.Add_Click({
    if ($lv.SelectedItems.Count -lt 1) { return }
    $it = $lv.SelectedItems[0]
    if ($it.Tag -eq "section") { return }
    $labels = @("Name","Installed","Running","Status","Version","Details","How to disable")
    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $val = ""
        if ($i -lt $it.SubItems.Count) { $val = [string]$it.SubItems[$i].Text }
        $val = $val -replace "[\r\n]+", " "
        [void]$lines.Add(($labels[$i] + ": " + $val))
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
        if ($lblStatus) { $lblStatus.Text = "Copied row" }
    } catch {}
})
[void]$cmsCopy.Items.Add($miCopyRow)
$lv.ContextMenuStrip = $cmsCopy
$lv.Add_MouseDown({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    $hit = $lv.GetItemAt($_.X, $_.Y)
    if (-not $hit) { return }
    $lv.SelectedItems.Clear()
    $hit.Selected = $true
    $lv.FocusedItem = $hit
})


$script:CancelScan = $false
$btnCancel.Add_Click({
    Request-ScanCancel
    if (Test-UiAlive -and $lblStatus) { $lblStatus.Text = "Canceling scan..." }
    Write-Log "SCAN: cancel requested"
})

$btnUpdate.Add_Click({
    if ($script:UpdateUrl -and ([string]$btnUpdate.Text -like "Download v*")) {
        try { if ([string]$script:UpdateUrl -like ("https://github.com/" + $script:GitHubRepo + "/releases/*")) { Start-Process $script:UpdateUrl } } catch {}
        return
    }
    if ($script:UpdHandle -and -not $script:UpdHandle.IsCompleted) { return }
    $btnUpdate.Text = "Checking..."
    $script:UpdateUrl = ""
    Write-Log "UPDATE: checking AndrewTools/PortableAIScanner"
    Start-UpdateBackground
})


function Invoke-ScanFn {
    param($fn)
    $script:LastScanStepError = $null
    if (-not $fn) { return $null }
    trap {
        Write-ErrorLog "Scan step failed" -ErrorRecord $_
        $script:LastScanStepError = $_
        break
    }
    return (& $fn)
}

function Get-ScanWorkGroups {
    # Keep rows inside each group A-Z by the name shown in the list.
    # Local Models: leftover "Local AI Models" row stays last on purpose.
    return @(
        @{ Header = "Major Apps"; Fns = @(
            { Scan-ChatGPT }, { Scan-Claude }, { Scan-Copilot }, { Scan-GeminiDesktop },
            { Scan-GrokNote }, { Scan-Ollama }, { Scan-Perplexity }
        )},
        @{ Header = "Local Models"; Fns = @(
            { Scan-DeepSeek }, { Scan-Dolphin }, { Scan-Gemma }, { Scan-GLM }, { Scan-GptJPygmalion },
            { Scan-GptOss }, { Scan-Granite }, { Scan-Hunyuan }, { Scan-Kimi }, { Scan-Ling },
            { Scan-Llama }, { Scan-MiMo }, { Scan-MiniCPM }, { Scan-MiniMax }, { Scan-MistralFamily },
            { Scan-MuseGlimmer }, { Scan-Nemotron }, { Scan-Ornith }, { Scan-Phi }, { Scan-Qwen }, { Scan-LocalModels }
        )},
        @{ Header = "Browser-based"; Fns = @(
            { Scan-BraveLeo }, { Scan-GeminiChrome }, { Scan-EdgeCopilot }, { Scan-Firefox },
            { Scan-OperaAI }, { Scan-Comet }
        )},
        @{ Header = "Microsoft Apps"; Fns = @(
            { Scan-SettingsAgent }, { Scan-ClickToDo }, { Scan-FileExplorerAI }, { Scan-FoundryLocal }, { Scan-GitHubCopilot }, { Scan-M365Copilot },
            { Scan-NotepadAI }, { Scan-PaintAI }, { Scan-Recall }, { Scan-WindowsAIComponents }
        )},
        @{ Header = "Other Apps"; Fns = @(
            { Scan-AnythingLLM }, { Scan-ChatRTX }, { Scan-CherryStudio }, { Scan-ClaudeCode },
            { Scan-ComfyUI }, { Scan-Cursor }, { Scan-GAssist }, { Scan-GPT4All }, { Scan-Jan },
            { Scan-KoboldCpp }, { Scan-LibreChat }, { Scan-LlamaCpp }, { Scan-Llamafile },
            { Scan-LMStudio }, { Scan-LocalAI }, { Scan-Msty }, { Scan-OpenWebUI },
            { Scan-TextGenWebUI }, { Scan-Vllm }, { Scan-Windsurf }
        )}
    )
}

function Complete-AiScan {
    if ($script:ScanTimer) {
        try { $script:ScanTimer.Stop() } catch {}
    }
    Stop-ScanListHold
    Stop-PasBackground -WaitIfDone
    $results = @($script:ScanWork.Results)
    $ollamaLoaded = @($script:ScanWork.OllamaLoaded)
    $lmStudioLoaded = @($script:ScanWork.LmStudioLoaded)
    $compatLoaded = @($script:ScanWork.CompatLoaded)
    $scanWatch = $script:ScanWork.Watch
    try {
        if ((Test-UiAlive) -and @($results).Count -gt 0) {
            try { $script:ProcSnap = @(Get-Process -ErrorAction SilentlyContinue) } catch { $script:ProcSnap = @() }
            foreach ($rr in $results) {
                $modelRun = Test-IsRunning -AiName $rr.Name -OllamaLoadedModels $ollamaLoaded -LmStudioLoadedModels $lmStudioLoaded -CompatLoadedModels $compatLoaded
                [void](Set-RunningAndStatus $rr $modelRun)
            }
            $liveCount = 0
            try { $liveCount = $lv.Items.Count } catch {}
            if ($liveCount -gt 0) {
                Update-LiveListViewRows -ListView $lv
            } else {
                Show-ScanRows -ListView $lv
            }
        }
        if (Test-UiAlive) {
            $rowCount = @($results).Count
            if ((Test-ScanCanceled) -and $rowCount -eq 0) {
                if ($scanWatch) { try { $scanWatch.Stop() } catch {} }
                Set-ScanBarEnd -Percent 0
                $lblStatus.Text = "Scan canceled."
            } else {
                $runningCount = @($results | Where-Object {
                    ($_.Running -like "Yes*") -and ($_.Activated -eq "Activated" -or $_.Activated -eq "Model loaded")
                }).Count
                $activatedCount = @($results | Where-Object {
                    ($_.Activated -eq "Activated" -or $_.Activated -eq "Model loaded") -and ($_.Running -notlike "Yes*")
                }).Count
                $installedCount = @($results | Where-Object {
                    $_.Activated -eq "Installed" -or $_.Activated -eq "Unknown" -or $_.Activated -eq "Deactivated"
                }).Count
                $script:SkipListLayout = $false
                if ($lv) {
                    $widthSrc = $script:LvCache
                    if (-not $widthSrc -or $widthSrc.Count -lt 1) {
                        Save-ListViewCache -ListView $lv
                        $widthSrc = $script:LvCache
                    }
                    if ($widthSrc) {
                        foreach ($it in $widthSrc) {
                            if (-not $it) { continue }
                            $nm = ""
                            $ds = ""
                            try { if ($it.SubItems.Count -gt 0) { $nm = [string]$it.SubItems[0].Text } } catch {}
                            try { if ($it.SubItems.Count -gt 6) { $ds = [string]$it.SubItems[6].Text } } catch {}
                            Update-TrackedNameDisableWidth -ListView $lv -NameText $nm -DisableText $ds
                        }
                    }
                }
                Resize-NameAndDisableColumns -ListView $lv
                if (-not $script:LvCache -or $script:LvCache.Count -lt 1) {
                    Save-ListViewCache -ListView $lv
                }
                if ($scanWatch) { try { $scanWatch.Stop() } catch {} }
                $sec = if ($scanWatch) { [Math]::Round($scanWatch.Elapsed.TotalSeconds, 1) } else { 0 }
                Set-ScanBarEnd -Percent 100
                $summary = "Green: $installedCount | Blue (AI on, not running): $activatedCount | Red (running and AI on): $runningCount | Time: $sec sec"
                if (Test-ScanCanceled) {
                    $lblStatus.Text = "Scan canceled. $summary"
                    Write-Log "Scan canceled. $summary"
                    $script:LastScanSummary = $lblStatus.Text
                } else {
                    $lblStatus.Text = "Scan complete. $summary"
                    Write-Log "Scan finished. $summary"
                    $script:LastScanSummary = $lblStatus.Text
                }
                $script:HasScanResults = $true
            }
        }
    } catch {
        Write-ErrorLog "Error updating UI after scan" -ErrorRecord $_
        if (Test-UiAlive) {
            $lblStatus.Text = "Scan finished with errors. See Log.txt"
            $script:HasScanResults = $true
        }
    } finally {
        $script:ScanBusy = $false
        $script:SkipListLayout = $false
        if (Test-UiAlive) {
            try {
                $btnCancel.Visible = $true
                $btnCancel.Enabled = $false
                $btnScan.Enabled = $true
                $btnScan.Text = "Rescan"
                Show-PostScanActionButtons -Show ([bool]$script:HasScanResults)
                if ((Test-ScanCanceled) -and -not $script:HasScanResults) { Set-ScanBarEnd -Percent 0 }
            } catch [System.ObjectDisposedException] {
            } catch {}
        }
        if (Test-ScanCanceled) { Write-Log "SCAN: canceled" }
        $script:ScanWork = $null
        if (-not (Test-ScanCanceled) -and $script:HasScanResults) {
            try { Start-ChromeSettingsRecheck } catch {}
        }
    }
}

function Step-AiScan {
    if (-not $script:ScanWork) { return }
    if (-not (Test-UiAlive)) {
        Request-ScanCancel
        try { if ($script:ScanTimer) { $script:ScanTimer.Stop() } } catch {}
        Stop-PasBackground
        $script:ScanBusy = $false
        $script:ScanWork = $null
        return
    }
    if (Test-ScanCanceled -and $script:ScanWork.Phase -ne "done") {
        $script:ScanWork.Phase = "done"
        Complete-AiScan
        return
    }
    $w = $script:ScanWork
    try {
        switch ($w.Phase) {
            "proc" {
                $lblStatus.Text = "Checking apps..."
                Set-ScanBarEnd -Percent 3
                $script:ProcSnap = $null
                $script:ProcImageHint = @{}
                try { $script:ProcSnap = @(Get-Process -ErrorAction SilentlyContinue) } catch { $script:ProcSnap = @() }
                $w.Phase = "prep"
            }
            "prep" {
                $lblStatus.Text = "Checking installed programs..."
                Set-ScanBarEnd -Percent 4
                if (-not $w.BgKind) {
                    if (Start-PasBackground -Kind "prep") {
                        $w.BgKind = "prep"
                        return
                    }
                    try { $script:ListenOwnerMap = New-LoopbackListenOwnerMap } catch { $script:ListenOwnerMap = @{} }
                    try { $script:UninstallAppsCache = @(New-UninstallAppsCache) } catch { $script:UninstallAppsCache = @() }
                    $w.Phase = "appx"
                    return
                }
                $bg = Read-PasBackground
                if (-not $bg.Done) { return }
                $prep = $null
                if (-not $bg.Failed -and $bg.Result -and @($bg.Result).Count -gt 0) { $prep = @($bg.Result)[-1] }
                if ($prep -and $prep.PSObject.Properties.Name -contains "ListenMap") {
                    $script:ListenOwnerMap = $prep.ListenMap
                    if ($null -eq $script:ListenOwnerMap) { $script:ListenOwnerMap = @{} }
                    try { $script:UninstallAppsCache = @($prep.Uninstall) } catch { $script:UninstallAppsCache = @() }
                } else {
                    try { $script:ListenOwnerMap = New-LoopbackListenOwnerMap } catch { $script:ListenOwnerMap = @{} }
                    try { $script:UninstallAppsCache = @(New-UninstallAppsCache) } catch { $script:UninstallAppsCache = @() }
                }
                $w.BgKind = $null
                try {
                    $nListen = 0
                    if ($script:ListenOwnerMap) { $nListen = @($script:ListenOwnerMap.Keys).Count }
                    $nApps = @($script:UninstallAppsCache).Count
                    Write-Log ("SCAN: local-port list $nListen, Apps list $nApps")
                } catch {}
                $w.Phase = "appx"
            }
            "appx" {
                $lblStatus.Text = "Checking apps..."
                if (-not $w.BgKind) {
                    $script:AllAppx = @()
                    if (Start-PasBackground -Kind "appx") {
                        $w.BgKind = "appx"
                        return
                    }
                    try { $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $script:AllAppx = @() }
                    $w.Phase = "ollama"
                    return
                }
                $bg = Read-PasBackground
                if (-not $bg.Done) { return }
                if (-not $bg.Failed -and (Test-AppxListUsable $bg.Result)) {
                    $script:AllAppx = @($bg.Result)
                } else {
                    try { $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch { $script:AllAppx = @() }
                }
                $w.BgKind = $null
                $w.Phase = "ollama"
            }
            "ollama" {
                $lblStatus.Text = "Checking model files..."
                Set-ScanBarEnd -Percent 6
                $w.OllamaLoaded = @(Get-OllamaLoadedModels)
                Write-Log ("Ollama loaded models: " + $(if ($w.OllamaLoaded.Count -gt 0) { $w.OllamaLoaded -join ", " } else { "(none)" }))
                $w.Phase = "lmstudio"
            }
            "lmstudio" {
                $w.LmStudioLoaded = @(Get-LmStudioLoadedModels)
                Write-Log ("LM Studio loaded models: " + $(if ($w.LmStudioLoaded.Count -gt 0) { $w.LmStudioLoaded -join ", " } else { "(none)" }))
                $w.Phase = "compat"
            }
            "compat" {
                $w.CompatLoaded = @(Get-OpenAiCompatLoadedModels)
                foreach ($extra in @((Get-LlamaCppLoadedModels) + (Get-LocalAiLoadedModels) + (Get-KoboldCppLoadedModels))) {
                    if ($extra -and $w.CompatLoaded -notcontains $extra) { $w.CompatLoaded += $extra }
                }
                Write-Log ("OpenAI-compat (llama.cpp/etc) models: " + $(if ($w.CompatLoaded.Count -gt 0) { $w.CompatLoaded -join ", " } else { "(none)" }))
                $w.Phase = "index"
            }
            "index" {
                $lblStatus.Text = "Checking model files..."
                Set-ScanBarEnd -Percent 10
                if (-not $w.BgKind) {
                    $script:ModelNameIndex = $null
                    $script:ModelGgufCount = 0
                    $script:ModelGgufRoots = @()
                    $script:ClaimedModelNames = @{}
                    $script:SystemAiConsentCache = $null
                    if (Start-PasBackground -Kind "index") {
                        $w.BgKind = "index"
                        return
                    }
                    Initialize-ModelNameIndex
                    Set-ScanBarEnd -Percent 12
                    $w.Phase = "scan"
                    return
                }
                $bg = Read-PasBackground
                if (-not $bg.Done) {
                    if ($script:ScanSync -and $script:ScanSync.Status) {
                        $lblStatus.Text = [string]$script:ScanSync.Status
                    }
                    return
                }
                $idx = $null
                if ($bg.Result -and @($bg.Result).Count -gt 0) { $idx = @($bg.Result)[-1] }
                if ($idx -and $idx.PSObject.Properties.Name -contains "Names") {
                    $script:ModelNameIndex = @($idx.Names)
                    $script:ModelGgufCount = [int]$idx.GgufCount
                    $script:ModelGgufRoots = @($idx.GgufRoots)
                    $script:ModelIndexIncomplete = [bool]$idx.Incomplete
                } else {
                    Initialize-ModelNameIndex
                }
                $w.BgKind = $null
                Set-ScanBarEnd -Percent 12
                $w.Phase = "scan"
            }
            "scan" {
                $scanBatch = 0
                while ($scanBatch -lt 3) {
                $scanBatch++
                if (Test-ScanCanceled) { break }
                $groups = $w.Groups
                if ($w.GroupIndex -ge @($groups).Count) { $w.Phase = "done"; Complete-AiScan; return }
                $group = $groups[$w.GroupIndex]
                $fns = @($group.Fns)
                if ($w.FnIndex -eq 0 -and $group.Header) {
                    $script:ScanRows += @{ Kind = "section"; Title = [string]$group.Header }
                    if (-not $script:FilterDetected) {
                        Add-SectionHeaderToListView -ListView $lv -Title ([string]$group.Header)
                        Pulse-ScanListPaint
                    }
                }
                if ($w.FnIndex -ge $fns.Count) {
                    $w.GroupIndex++
                    $w.FnIndex = 0
                    continue
                }
                $w.Step++
                $fn = $fns[$w.FnIndex]
                $hint = (($fn.ToString() -replace '(?s).*Scan-', 'Scan-') -replace '\s.*', '')
                $hint = Get-ScanStepLabel $hint
                $totalSteps = [Math]::Max(1, $w.TotalSteps)
                $pct = 12 + [int][Math]::Floor((($w.Step - 1) / $totalSteps) * 87)
                if ($pct -gt 99) { $pct = 99 }
                if ($pct -lt 12) { $pct = 12 }
                Set-ScanBarEnd -Percent $pct
                $lblStatus.Text = "Scanning $($w.Step) of $totalSteps : $hint"
                try {
                    $script:LastScanStepError = $null
                    $r = Invoke-ScanFn $fn
                    if ($script:LastScanStepError) {
                        throw $script:LastScanStepError
                    }
                    if ($r) {
                        $r.Running = ""
                        if ($r.Name -like "Ollama*") {
                            if ($w.OllamaLoaded.Count -gt 0) {
                                $r.Details = (($r.Details + " | Loaded in memory: " + ($w.OllamaLoaded -join ", ")).Trim(" |"))
                                $watchNote = Get-WatchedLoadedModelNote $w.OllamaLoaded
                                if ($watchNote) { $r.Details = (($r.Details + " | " + $watchNote).Trim(" |")) }
                            } elseif ($r.Installed) {
                                $r.Details = (($r.Details + " | No model loaded in memory").Trim(" |"))
                            }
                        } elseif ($r.Name -like "LM Studio*") {
                            if ($w.LmStudioLoaded.Count -gt 0) {
                                $r.Details = (($r.Details + " | Loaded in memory: " + ($w.LmStudioLoaded -join ", ")).Trim(" |"))
                                $watchNote = Get-WatchedLoadedModelNote $w.LmStudioLoaded
                                if ($watchNote) { $r.Details = (($r.Details + " | " + $watchNote).Trim(" |")) }
                            } elseif ($r.Installed) {
                                $r.Details = (($r.Details + " | No model loaded in memory").Trim(" |"))
                            }
                        } elseif ($r.Name -like "llama.cpp*") {
                            $llamaIds = @(Get-LlamaCppLoadedModels)
                            if ($llamaIds.Count -gt 0) {
                                $r.Details = (($r.Details + " | Loaded in memory: " + ($llamaIds -join ", ")).Trim(" |"))
                                $watchNote = Get-WatchedLoadedModelNote $llamaIds
                                if ($watchNote) { $r.Details = (($r.Details + " | " + $watchNote).Trim(" |")) }
                            }
                        } elseif ($r.Name -like "LocalAI*") {
                            $localAiIds = @(Get-LocalAiLoadedModels)
                            if ($localAiIds.Count -gt 0) {
                                $r.Details = (($r.Details + " | Loaded in memory: " + ($localAiIds -join ", ")).Trim(" |"))
                                $watchNote = Get-WatchedLoadedModelNote $localAiIds
                                if ($watchNote) { $r.Details = (($r.Details + " | " + $watchNote).Trim(" |")) }
                            }
                        } elseif ($r.Name -like "KoboldCPP*") {
                            $kbIds = @(Get-KoboldCppLoadedModels)
                            if ($kbIds.Count -gt 0) {
                                $r.Details = (($r.Details + " | Loaded in memory: " + ($kbIds -join ", ")).Trim(" |"))
                                $watchNote = Get-WatchedLoadedModelNote $kbIds
                                if ($watchNote) { $r.Details = (($r.Details + " | " + $watchNote).Trim(" |")) }
                            }
                        }
                        $w.Results += $r
                        $script:ScanRows += @{ Kind = "result"; Result = $r }
                        if (-not $script:FilterDetected -or (Test-RowIsDetected $r)) {
                            Add-ResultToListView -ListView $lv -r $r
                            Pulse-ScanListPaint
                        }
                        if ($r.Installed -or ($r.Running -like "Yes*")) {
                            $tag = "FOUND"
                            if ($r.Activated -eq "Deactivated") { $tag = "FOUND (AI off)" }
                            Write-Log ("{0}: {1} | Installed={2} | Running={3} | Status={4} | Version={5} | Details={6}" -f $tag, $r.Name, $(if ($r.Installed) {"Yes"} else {"No"}), $r.Running, $r.Activated, $r.Version, $r.Details)
                        }
                    }
                } catch {
                    Write-ErrorLog "Error running scanner: $($fn.ToString())" -ErrorRecord $_
                    $errResult = New-Result "Scanner Error" $false "Error" $_.Exception.Message
                    $errResult.Running = "No"
                    $w.Results += $errResult
                    $script:ScanRows += @{ Kind = "result"; Result = $errResult }
                    if (-not $script:FilterDetected -or (Test-RowIsDetected $errResult)) {
                        Add-ResultToListView -ListView $lv -r $errResult
                        Pulse-ScanListPaint
                    }
                }
                $w.FnIndex++
                }
            }
            default { Complete-AiScan }
        }
    } catch {
        Write-ErrorLog "SCAN step failed" -ErrorRecord $_
        $w.Phase = "done"
        Complete-AiScan
    }
}

function Start-AiScanSession {
    if ($script:ScanBusy) { return }
    try { Stop-ChromeSettingsRecheck } catch {}
    $script:CancelScan = $false
    $script:ListenOwnerMap = $null
    $script:UninstallAppsCache = $null
    $script:ScanBusy = $true
    $script:ScanPass = [int]$script:ScanPass + 1
    $script:ScanBeganAt = Get-Date
    if (-not $script:ScanSync) {
        $script:ScanSync = [hashtable]::Synchronized(@{ Cancel = $false })
    }
    $script:ScanSync.Cancel = $false
    $btnScan.Enabled = $false
    $btnCancel.Visible = $true
    $btnCancel.Enabled = $true
    $btnExport.Visible = $false
    $btnDetected.Visible = $false
    $btnDetected.Enabled = $false
    $btnExport.Enabled = $false
    $lblStatus.Text = "Starting scan..."
    Set-ScanBarEnd -Percent 0
    $lv.Items.Clear()
    Start-ScanListHold
    $script:SkipListLayout = $true
    $script:ScanRows = @()
    $script:HasScanResults = $false
    $script:FilterDetected = $false
    $script:FilterBusy = $false
    New-LvCache
    $script:ColWidth0 = 0
    $script:ColWidth6 = 0
    if ($script:ColMeasureGraphics) {
        try { $script:ColMeasureGraphics.Dispose() } catch {}
        $script:ColMeasureGraphics = $null
    }
    Update-DetectedButtonStyle
    Write-Log "SCAN: started by user"
    $groups = @(Get-ScanWorkGroups)
    $total = 0
    foreach ($g in $groups) { $total += @($g.Fns).Count }
    $script:ScanWork = @{
        Phase = "proc"
        Groups = $groups
        GroupIndex = 0
        FnIndex = 0
        Step = 0
        TotalSteps = $total
        Results = @()
        OllamaLoaded = @()
        LmStudioLoaded = @()
        CompatLoaded = @()
        BgKind = $null
        Watch = [System.Diagnostics.Stopwatch]::StartNew()
    }
    if (-not $script:ScanTimer) {
        $script:ScanTimer = New-Object System.Windows.Forms.Timer
        $script:ScanTimer.Interval = 15
        $script:ScanTimer.Add_Tick({ Step-AiScan })
    }
    $script:ScanTimer.Start()
}

$btnScan.Add_Click({
    Start-AiScanSession
})

$btnDetected.Add_Click({
    Invoke-DetectedFilterToggle
})

$btnExport.Add_Click({
    if ($script:ScanBusy) { return }
    if (-not $script:HasScanResults) { return }
    $stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = "Export list"
    $dlg.Filter = "CSV (Excel, LibreOffice) (*.csv)|*.csv|All files (*.*)|*.*"
    $dlg.DefaultExt = "csv"
    $dlg.FileName = "AI_Scanner_export_$stamp.csv"
    $dlg.InitialDirectory = $script:LogDir
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $outPath = $dlg.FileName
    try {
        function Escape-CsvField([string]$Text) {
            $t = [string]$Text
            $t = $t -replace '[\r\n]+', ' '
            if ($t.Length -gt 0 -and ([string]$t[0] -in @('=', '+', '-', '@'))) {
                $t = "`t" + $t
            }
            $t = $t -replace '"', '""'
            return '"' + $t + '"'
        }
        $lines = New-Object System.Collections.Generic.List[string]
        $headers = @("AI Name","Installed","Running","Status","Version","Details","How to disable")
        [void]$lines.Add(($headers | ForEach-Object { Escape-CsvField $_ }) -join ",")
        $sectionNames = @("Major Apps","Local Models","Browser-based","Microsoft Apps","Other Apps")
        foreach ($item in $lv.Items) {
            $name0 = ""
            if ($item.SubItems.Count -gt 0) { $name0 = [string]$item.SubItems[0].Text }
            $inst = ""
            $stat = ""
            if ($item.SubItems.Count -gt 1) { $inst = [string]$item.SubItems[1].Text }
            if ($item.SubItems.Count -gt 3) { $stat = [string]$item.SubItems[3].Text }
            if ($sectionNames -contains $name0) { continue }
            if (-not $inst -and -not $stat) { continue }
            $cols = @()
            foreach ($si in $item.SubItems) { $cols += (Escape-CsvField $si.Text) }
            [void]$lines.Add(($cols -join ","))
        }
        $utf8bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllLines($outPath, $lines.ToArray(), $utf8bom)
        Write-Log "EXPORT: $outPath"
        $lblStatus.Text = "Exported to $outPath"
    } catch {
        Write-ErrorLog "Export failed" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show("Could not write the export file.`r`nSee Log.txt", "$script:AppName", "OK", "Error") | Out-Null
    }
})

try {
    Write-Log "LOAD: window ready, opening"
    [void]$form.ShowDialog()
    Write-Log "LOAD: window closed normally"
} catch {
    $disposed = $false
    $ex = $_.Exception
    while ($ex) {
        if ($ex -is [System.ObjectDisposedException]) { $disposed = $true; break }
        $ex = $ex.InnerException
    }
    if ($disposed) {
        Write-Log "LOAD: window closed during scan"
    } else {
        Write-Log "LOAD ERROR: window failed to open" -ErrorRecord $_
        [System.Windows.Forms.MessageBox]::Show("A critical error occurred. Details were written to Log.txt", "$script:AppName v$script:AppVersion Error", "OK", "Error")
    }
} finally {
    try {
        if ($timerGpu) { $timerGpu.Stop(); $timerGpu.Dispose() }
        if ($timerUpdate) { $timerUpdate.Stop(); $timerUpdate.Dispose() }
        Stop-GpuBackground
        Stop-UpdateBackground
    } catch {}
    try { if ($form) { $form.Dispose() } } catch {}
    try { if ($script:InstanceMutex) { $script:InstanceMutex.ReleaseMutex(); $script:InstanceMutex.Dispose() } } catch {}
    Write-Log "LOAD: process exiting"
    if (-not $script:KeepHostPrompt) {
        try { [Environment]::Exit(0) } catch { exit 0 }
    }
}
