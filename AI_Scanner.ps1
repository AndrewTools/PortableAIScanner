# Portable AI Scanner - Windows 10/11 App
# No installation required. Run with: powershell -ExecutionPolicy Bypass -File AI_Scanner.ps1
# Or double-click Run_AI_Scanner.bat
# Changelog: Version.txt (keep in sync with $script:AppVersion)
#
# Version history (semantic: MAJOR.MINOR.PATCH)
# 1.0.0 - Baseline: desktop/browser/local model scan, Running column, disable hints
# 1.0.1 - Local AI Models last; log each positive finding to error_log.txt
# 1.1.0 - Tighter family keywords, model-file-only disk scan, Ollama /api/tags,
#         fewer browser false activations, extra runtime ports, Windsurf
# 1.1.1 - Scan progress bar and per-item status text
# 1.1.2 - Hide console window (not minimize); maximize GUI on startup
# 1.1.3 - Newer model-family versions (Qwen 3.7/4 preview, GLM-5.3, Mistral Small 4,
#         Nemotron 3.5 Lightning, Llama 3.3/4 Scout-Maverick, Kimi)
# 1.1.4 - Faster scan: one model-name index, cached Appx list, TCP probe before HTTP
# 1.1.5 - How to disable for every installed item (mouse-only, shown only if Installed=Yes)
# 1.1.6 - Auto-size AI Name and How to Disable columns to longest text
# 1.1.7 - Extra Copilot surfaces: M365, Notepad, Paint, Photos
# 1.1.8 - Read policy/registry/settings.dat for Notepad, Paint, Photos AI toggles
# 1.2.0 - Photos row = Copilot-like / on-device generative AI only
# 1.2.1 - Log.txt from launch; load steps and load errors
# 1.2.2 - List fills live as each item is scanned
# 1.3.0 - Remove Photos; Sep 2026 family keywords
# 1.3.1 - Build.txt (how to make the exe)
# 1.3.2 - Status column short vocabulary
# 1.3.3 - Section headers in the list
# 1.3.4 - No Major brands header; other headers ALL CAPS, no dashes
# 1.3.5 - No Model files header; remaining headers title case
# 1.3.6 - Other Apps header; Details wording cleanup
# 1.3.7 - Remove bottom details box
# 1.3.8 - Green count matches row color; Chrome Gemini Installed only if model exists
# 1.3.9 - Log FOUND (AI off) when browser AI is present but off
# 1.4.0 - Tighter M365, Windows on-device AI, local models, Copilot, Comet
# 1.4.1 - Faster GPT4All scan; DeepSeek V4.1 name match
# 1.4.2 - Standalone brand Status: no optional-AI-off on Copilot

$script:AppName = "Portable AI Scanner"
$script:AppVersion = "1.4.2"

# ========== Logging (Log.txt, overwritten at each launch) ==========
$script:LogDir = $PSScriptRoot
if (-not $script:LogDir) { $script:LogDir = (Get-Location).Path }
$script:LogPath = Join-Path -Path $script:LogDir -ChildPath "Log.txt"

function Write-Log {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )
    if (-not $script:LogPath) { return }
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
    $entry += "`r`n"
    try {
        Add-Content -Path $script:LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

function Write-ErrorLog {
    param(
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null
    )
    Write-Log -Message $Message -ErrorRecord $ErrorRecord
}

function Initialize-Log {
    $header = @"
$($script:AppName) v$($script:AppVersion) Log
====================
Started : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Version : $($script:AppVersion)
Script  : $PSCommandPath
Folder  : $script:LogDir
User    : $env:USERNAME
Computer: $env:COMPUTERNAME
PS      : $($PSVersionTable.PSVersion)
64-bit  : $([Environment]::Is64BitProcess)
====================

"@
    try {
        $fromExe = ($env:PAS_FROM_EXE -eq "1")
        if ($fromExe -and (Test-Path $script:LogPath)) {
            Add-Content -Path $script:LogPath -Value $header -Encoding UTF8 -ErrorAction Stop
        } else {
            Set-Content -Path $script:LogPath -Value $header -Encoding UTF8 -Force -ErrorAction Stop
        }
    } catch {
        $alt = Join-Path -Path $env:TEMP -ChildPath "PortableAIScanner_Log.txt"
        try {
            $script:LogPath = $alt
            Set-Content -Path $script:LogPath -Value $header -Encoding UTF8 -Force -ErrorAction Stop
        } catch {
            $script:LogPath = $null
        }
    }
}

Initialize-Log
Write-Log "LOAD: script file started"
trap {
    Write-Log "LOAD ERROR (trap): $_" -ErrorRecord $_
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
    Add-Type -TypeDefinition $hideConsoleSrc -ErrorAction SilentlyContinue
    $con = [NativeConsole]::GetConsoleWindow()
    if ($con -ne [IntPtr]::Zero) {
        [void][NativeConsole]::ShowWindow($con, 0)
        Write-Log "LOAD: console window hidden"
    } else {
        Write-Log "LOAD: no console window attached"
    }
} catch {
    Write-Log "LOAD ERROR: hide-console step failed (non-fatal)" -ErrorRecord $_
}
Write-Log "LOAD: helpers starting"

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
        if (-not $pkgs -or $pkgs.Count -eq 0) {
            $pkgs = @($script:AllAppx | Where-Object { $_.Name -match ($Pattern.Replace('*', '.*')) })
        }
        if ($pkgs.Count -gt 0) { return $pkgs }
        return $null
    } catch { return $null }
}

function Test-LocalPortOpen {
    param([int]$Port, [int]$TimeoutMs = 200)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            $client.Close()
            return $false
        }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Test-PathAny {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-FileVersionSafe {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            return (Get-Item $Path).VersionInfo.FileVersion
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

function Get-NotepadRewriteSetting {
    # User toggle lives in Notepad's settings.dat registry hive (RewriteEnabled 0/1)
    $pkgRoot = "$env:LOCALAPPDATA\Packages"
    if (-not (Test-Path $pkgRoot)) { return $null }
    $hive = Get-ChildItem $pkgRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Microsoft.WindowsNotepad_*" } |
        ForEach-Object { Join-Path $_.FullName "Settings\settings.dat" } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if (-not $hive) { return $null }

    $tmp = Join-Path $env:TEMP ("pas_notepad_settings_{0}.dat" -f [guid]::NewGuid().ToString("N"))
    $mount = "HKU\PASNotepadScan"
    try {
        Copy-Item -Path $hive -Destination $tmp -Force -ErrorAction Stop
        $null = & reg.exe load $mount $tmp 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $roots = @(
            "Registry::HKEY_USERS\PASNotepadScan",
            "Registry::HKEY_USERS\PASNotepadScan\LocalState"
        )
        try {
            $roots += @(Get-ChildItem "Registry::HKEY_USERS\PASNotepadScan" -ErrorAction SilentlyContinue | ForEach-Object { $_.PSPath })
        } catch {}
        foreach ($rp in $roots) {
            foreach ($valName in @("RewriteEnabled", "CopilotEnabled", "AIFeaturesEnabled", "EnableCopilot")) {
                $v = Get-RegValueSafe -Path $rp -Name $valName
                if ($null -ne $v) {
                    return [PSCustomObject]@{ Name = $valName; Value = $v }
                }
            }
        }
    } catch {
        Write-ErrorLog "Notepad settings.dat read failed" -ErrorRecord $_
    } finally {
        try { $null = & reg.exe unload $mount 2>$null } catch {}
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Get-SystemAiConsent {
    $signals = @()
    $denied = $false
    $allowed = $false
    foreach ($p in @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI"
    )) {
        $v = Get-RegValueSafe -Path $p -Name "Value"
        if ($v) {
            $signals += "$p Value=$v"
            if ("$v" -eq "Deny") { $denied = $true }
            if ("$v" -eq "Allow") { $allowed = $true }
        }
    }
    return [PSCustomObject]@{ Denied = $denied; Allowed = $allowed; Signals = $signals }
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
        [string]$Running = "No",
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
        "Microsoft Copilot" { return "$apps > Copilot > Uninstall. Also Settings > Personalization > Taskbar > turn off Copilot." }
        "Microsoft 365 Copilot*" { return "$apps > Microsoft 365 Copilot > Uninstall. In Word, Excel, or PowerPoint: File > Options > Copilot > turn off Enable Copilot." }
        "Notepad*" { return "Open Notepad > gear icon (Settings) > AI Features > turn off Copilot / Writing tools." }
        "Paint*" { return "Windows Settings > Privacy & security > Text and image generation > turn off Paint if listed. Paint itself has no simple off switch for every AI tool." }
        "Google Gemini (in Chrome)" { return "Open Chrome > three-dot menu > Settings > System > turn off On-device AI." }
        "ChatGPT*" { return "$apps > ChatGPT > Uninstall." }
        "Claude*" { return "$apps > Claude > Uninstall." }
        "Perplexity" { return "$apps > Perplexity > Uninstall." }
        "Microsoft Edge*" { return "Open Edge > three-dot menu > Settings > Sidebar > turn off Copilot." }
        "Ollama*" { return "$apps > Ollama > Uninstall. That also removes its downloaded models." }
        "LM Studio*" { return "Open LM Studio > My Models > remove models you do not want. Or $apps > LM Studio > Uninstall." }
        "Jan*" { return "Open Jan > Hub / Models > delete models. Or $apps > Jan > Uninstall." }
        "GPT4All*" { return "Open GPT4All > Downloads / Models > remove models. Or $apps > GPT4All > Uninstall." }
        "Cursor*" { return "$apps > Cursor > Uninstall." }
        "Windows On-Device*" { return "Windows Settings > Privacy & security > Text and image generation > turn the feature off. Also Privacy & security > Click to Do / Recall if those pages appear, and turn them off." }
        "GitHub Copilot*" { return "Open VS Code or Visual Studio > Extensions > GitHub Copilot > Disable or Uninstall." }
        "ComfyUI*" { return "$apps > ComfyUI if listed > Uninstall. If it is only a folder app, open Start > right-click the app shortcut > Uninstall." }
        "Opera*" { return "Open Opera > Settings > Sidebar > turn off Aria / Opera AI." }
        "Brave*" { return "Open Brave > Settings > Leo > turn off Leo AI." }
        "Perplexity Comet*" { return "Open Comet > Settings > turn off AI features. Or $apps > Comet > Uninstall." }
        "Mozilla Firefox*" { return "Open Firefox > Settings > AI Controls > turn on Block AI enhancements." }
        "Grok*" { return "$apps > Grok > Uninstall if listed. Otherwise use the website only and sign out." }
        "Windsurf*" { return "$apps > Windsurf > Uninstall." }
        "llama.cpp*" { return "If llama.cpp appears in $apps, click Uninstall. If you only have a program file, delete that app shortcut from Start by right-click > Uninstall when Windows offers it." }
        "vLLM*" { return "If vLLM appears in $apps, click Uninstall. Otherwise open the Start menu, find the Python app you used, and uninstall that app." }
        "Msty*" { return "$apps > Msty > Uninstall." }
        "KoboldCPP*" { return "If KoboldCPP appears in $apps, click Uninstall. If it is only a downloaded program, right-click it in Start or Downloads and choose Uninstall when Windows offers it." }
        "Open WebUI*" { return "If Open WebUI appears in $apps, click Uninstall. If you use Docker Desktop, open Docker Desktop and stop or delete the Open WebUI container." }
        "AnythingLLM*" { return "$apps > AnythingLLM > Uninstall." }
        "text-generation-webui*" { return "If it appears in $apps, click Uninstall. If it is only a folder app, use Start > right-click the shortcut > Uninstall when offered." }
        "Local AI Models*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove the listed models. Or $apps > uninstall that app." }
        "Qwen*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Qwen. Or $apps > uninstall the app that downloaded it." }
        "Llama *" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Llama. Or $apps > uninstall the app that downloaded it." }
        "DeepSeek*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove DeepSeek. Or $apps > uninstall the app that downloaded it." }
        "Gemma*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Gemma. Or $apps > uninstall the app that downloaded it." }
        "Phi*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Phi. Or $apps > uninstall the app that downloaded it." }
        "Granite*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Granite. Or $apps > uninstall the app that downloaded it." }
        "GLM*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove GLM. Or $apps > uninstall the app that downloaded it." }
        "Mistral*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Mistral. Or $apps > uninstall the app that downloaded it." }
        "gpt-oss*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove gpt-oss. Or $apps > uninstall the app that downloaded it." }
        "Nemotron*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Nemotron. Or $apps > uninstall the app that downloaded it." }
        "Muse *" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Muse. Or $apps > uninstall the app that downloaded it." }
        "Kimi*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove Kimi. Or $apps > uninstall the app that downloaded it." }
        "MiniMax*" { return "Open Ollama, LM Studio, GPT4All, or Jan > Models > remove MiniMax. Or $apps > uninstall the app that downloaded it." }
        "Foundry Local*" { return "$apps > Foundry Local > Uninstall. Or Settings > System > AI components if listed." }
        default { return "$apps > find this app > Uninstall. If it is a browser feature, open that browser Settings and turn the AI option off." }
    }
}

# Running = Yes ONLY when an on-device model is actively loaded in memory.
# Browsers, host apps, and idle servers do NOT count as Running.

function Get-OllamaLoadedModels {
    # Returns model names currently loaded in Ollama memory (CLI + API). Empty array = none loaded.
    $models = @()

    # 1) Preferred: HTTP API /api/ps (works even if CLI not on PATH)
    try {
        if (Test-LocalPortOpen -Port 11434) {
        foreach ($uri in @("http://127.0.0.1:11434/api/ps")) {
            try {
                $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
                if ($resp.StatusCode -ne 200) { continue }
                $json = $resp.Content | ConvertFrom-Json
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

    # 2) CLI: ollama ps
    try {
        $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
        if (-not $ollamaCmd) {
            foreach ($c in @(
                "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
                "${env:ProgramFiles}\Ollama\ollama.exe",
                "$env:USERPROFILE\AppData\Local\Programs\Ollama\ollama.exe"
            )) {
                if (Test-Path $c) { $ollamaCmd = $c; break }
            }
        }
        if ($ollamaCmd) {
            $exe = if ($ollamaCmd -is [string]) { $ollamaCmd } else { $ollamaCmd.Source }
            $output = & $exe ps 2>$null
            if ($output) {
                foreach ($line in ($output | Select-Object -Skip 1)) {
                    $trimmed = "$line".Trim()
                    if ($trimmed -eq "") { continue }
                    $name = ($trimmed -split '\s+')[0]
                    if ($name -and $name -ne "NAME" -and $models -notcontains $name) { $models += $name }
                }
            }
        }
    } catch {
        Write-ErrorLog "ollama ps CLI check failed" -ErrorRecord $_
    }

    return $models
}

function Get-OllamaInstalledTags {
    # Installed (on-disk) Ollama tags via API, not loaded-in-memory
    $tags = @()
    if (-not (Test-LocalPortOpen -Port 11434)) { return $tags }
    foreach ($uri in @("http://127.0.0.1:11434/api/tags")) {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($resp.StatusCode -ne 200) { continue }
            $json = $resp.Content | ConvertFrom-Json
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
    if (Test-LocalPortOpen -Port 1234) {
        $uris += "http://127.0.0.1:1234/v1/models"
        $uris += "http://127.0.0.1:1234/api/v0/models"
    }
    if (Test-LocalPortOpen -Port 4891) {
        $uris += "http://127.0.0.1:4891/v1/models"
    }
    foreach ($uri in $uris) {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($resp.StatusCode -ne 200) { continue }
            $json = $resp.Content | ConvertFrom-Json
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
        11434 = @("http://127.0.0.1:11434/v1/models")
    }
    $uris = @()
    foreach ($p in $portMap.Keys) {
        if (Test-LocalPortOpen -Port $p) { $uris += $portMap[$p] }
    }
    foreach ($uri in $uris) {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
            if ($resp.StatusCode -ne 200) { continue }
            $json = $resp.Content | ConvertFrom-Json
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

function Get-LoadedModelsMatching {
    param(
        [string[]]$Loaded,
        [string[]]$Patterns
    )
    if (-not $Loaded -or $Loaded.Count -eq 0) { return @() }
    $matched = @()
    foreach ($m in $Loaded) {
        foreach ($p in $Patterns) {
            if ($m -match $p) {
                $matched += $m
                break
            }
        }
    }
    return $matched
}

function Test-IsRunning {
    param(
        [string]$AiName,
        [string[]]$OllamaLoadedModels = $null,
        [string[]]$LmStudioLoadedModels = $null,
        [string[]]$CompatLoadedModels = $null
    )

    # Strict rule: Running = Yes only if an on-device model is loaded in memory.
    # No browser, no host app, no empty server.

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
        "Ollama (Local LLM Runtime)" {
            return (Format-Yes $OllamaLoadedModels)
        }
        "LM Studio (Local LLM GUI)" {
            return (Format-Yes $LmStudioLoadedModels)
        }
        "llama.cpp*" {
            $m = Get-LoadedModelsMatching -Loaded $CompatLoadedModels -Patterns @('(?i).')
            if ($m.Count -gt 0) { return (Format-Yes $m) }
            # If llama-server process is up but API has no model id, still No (need loaded model)
            return "No"
        }
        "Local AI Models*" {
            return (Format-Yes $allLoaded)
        }
        "Qwen*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)qwen')))
        }
        "Llama 3*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @(
                '(?i)meta-llama',
                '(?i)llama-?[345]',
                '(?i)llama3',
                '(?i)llama2',
                '(?i)llama-?2',
                '(?i)scout',
                '(?i)maverick'
            )))
        }
        "DeepSeek*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @(
                '(?i)deepseek', '(?i)r1-distill', '(?i)r1_distill', '(?i)ds-r1', '(?i)ds-v3', '(?i)ds-v4'
            )))
        }
        "Gemma*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)gemma', '(?i)medgemma', '(?i)functiongemma', '(?i)translategemma')))
        }
        "Phi*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)phi-?[0-9]', '(?i)phi4', '(?i)phi5', '(?i)phi-mini')))
        }
        "GLM*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)glm', '(?i)chatglm')))
        }
        "Mistral*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)mistral', '(?i)mixtral', '(?i)devstral', '(?i)magistral', '(?i)ministral', '(?i)pixtral', '(?i)voyage')))
        }
        "gpt-oss*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)gpt-oss', '(?i)gpt_oss', '(?i)gptoss')))
        }
        "Nemotron*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)nemotron')))
        }
        "Muse *" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)muse-?glimmer', '(?i)muse_glimmer', '(?i)museglimmer', '(?i)muse-?spark', '(?i)spark-1\.[123]')))
        }
        "Kimi*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)kimi', '(?i)moonshot')))
        }
        "Granite*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)granite', '(?i)ibm-granite')))
        }
        "MiniMax*" {
            return (Format-Yes (Get-LoadedModelsMatching -Loaded $allLoaded -Patterns @('(?i)minimax')))
        }
        default {
            return "No"
        }
    }
}

# ========== Scanners ==========

function Scan-Copilot {
    $r = New-Result "Microsoft Copilot"

    $pkgs = Get-AppxByName "*Copilot*"
    if ($pkgs) {
        $pkg = $pkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $allNames = ($pkgs | Select-Object -ExpandProperty Name -Unique) -join ", "
        $r.Details = "Package: $($pkg.Name) | Status: $($pkg.Status) | All Copilot packages: $allNames"
    }

    if (-not $r.Installed) {
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\WindowsUdk.UI.Shell.WindowsCopilot") {
            $r.Installed = $true
            $r.Details = "Detected via registry (WindowsCopilot activatable class)"
        } elseif (Test-Path "HKCR:\ms-copilot") {
            $r.Installed = $true
            $r.Details = "Detected via ms-copilot protocol"
        }
    }

    if ($r.Installed) {
        $turnedOff = $false
        foreach ($p in @("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
            $val = Get-ItemProperty -Path $p -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
            if ($val -and $val.TurnOffWindowsCopilot -eq 1) { $turnedOff = $true }
        }
        $showBtn = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -ErrorAction SilentlyContinue
        if ($turnedOff) {
            Set-ScanStatus $r "Deactivated" "Disabled by policy"
        } else {
            Set-ScanStatus $r "Installed" "Windows Copilot app present"
            if ($null -eq $showBtn) {
                $r.Details += " | Taskbar button setting not set"
            } elseif ($showBtn.ShowCopilotButton -eq 0) {
                $r.Details += " | Taskbar button hidden"
            } elseif ($showBtn.ShowCopilotButton -eq 1) {
                $r.Details += " | Taskbar button on"
            }
        }
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Copilot package, registry class, or ms-copilot protocol found"
    }
    return $r
}

function Scan-M365Copilot {
    $r = New-Result "Microsoft 365 Copilot (Office)"
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
        $r.Details = "Package: $($pkg.Name)"
        Set-ScanStatus $r "Installed" "Microsoft 365 Copilot app present"
        if ($officeExe) { $r.Details += " | Office desktop: $officeExe" }
    } elseif ($officeExe) {
        $r.Installed = $false
        $r.Version = Get-FileVersionSafe $officeExe
        Set-ScanStatus $r "None Found on Disk" "Office found; Microsoft 365 Copilot app not found"
        $r.Details = "Office desktop: $officeExe"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Microsoft 365 Copilot app found"
    }
    return $r
}

function Scan-NotepadAI {
    $r = New-Result "Notepad (AI / Copilot features)"
    $pkgs = Get-AppxByName "Microsoft.WindowsNotepad*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "*Notepad*" }
    if (-not $pkgs) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Notepad app package not found"
        return $r
    }
    $pkg = $pkgs | Select-Object -First 1
    $r.Installed = $true
    $r.Version = $pkg.Version
    $hints = @("Package: $($pkg.Name)")

    $pol = Get-RegValueSafe -Path "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures"
    $user = Get-RegValueSafe -Path "HKCU:\SOFTWARE\Microsoft\Notepad" -Name "EnableCopilot"
    $rewrite = Get-NotepadRewriteSetting

    if ($null -ne $pol -and [int]$pol -eq 1) {
        Set-ScanStatus $r "Deactivated" "Group Policy DisableAIFeatures=1"
        $hints += "Policy HKLM\SOFTWARE\Policies\WindowsNotepad\DisableAIFeatures=1"
    } elseif ($null -ne $user -and [int]$user -eq 0) {
        Set-ScanStatus $r "Deactivated" "user EnableCopilot=0"
        $hints += "HKCU\SOFTWARE\Microsoft\Notepad\EnableCopilot=0"
    } elseif ($rewrite -and ("$($rewrite.Value)" -eq "0" -or "$($rewrite.Value)" -eq "False")) {
        Set-ScanStatus $r "Deactivated" "Notepad settings.dat $($rewrite.Name)=0"
        $hints += "settings.dat $($rewrite.Name)=$($rewrite.Value)"
    } elseif ($rewrite -and ("$($rewrite.Value)" -eq "1" -or "$($rewrite.Value)" -eq "True")) {
        Set-ScanStatus $r "Activated" "Notepad settings.dat $($rewrite.Name)=1"
        $hints += "settings.dat $($rewrite.Name)=$($rewrite.Value)"
    } elseif ($null -ne $user -and [int]$user -eq 1) {
        Set-ScanStatus $r "Activated" "user EnableCopilot=1"
        $hints += "HKCU\SOFTWARE\Microsoft\Notepad\EnableCopilot=1"
    } else {
        Set-ScanStatus $r "Installed" "No toggle recorded; Notepad default is AI available"
        $hints += "No DisableAIFeatures policy and no saved user toggle"
    }
    $r.Details = $hints -join " | "
    return $r
}

function Scan-PaintAI {
    $r = New-Result "Paint (AI / Copilot features)"
    $pkgs = Get-AppxByName "Microsoft.Paint*"
    if (-not $pkgs) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Paint app package not found"
        return $r
    }
    $pkg = $pkgs | Select-Object -First 1
    $r.Installed = $true
    $r.Version = $pkg.Version
    $hints = @("Package: $($pkg.Name)")
    $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
    $names = @("DisableCocreator", "DisableGenerativeFill", "DisableImageCreator", "DisableGenerativeErase", "DisableRemoveBackground")
    $disabled = @()
    $enabledMissing = @()
    foreach ($n in $names) {
        $v = Get-RegValueSafe -Path $policyPath -Name $n
        if ($null -ne $v -and [int]$v -eq 1) { $disabled += $n }
        else { $enabledMissing += $n }
    }
    if ($disabled.Count -eq $names.Count) {
        Set-ScanStatus $r "Deactivated" "Paint AI policies all set to disable"
        $hints += "Disabled: $($disabled -join ', ')"
    } elseif ($disabled.Count -gt 0) {
        Set-ScanStatus $r "Installed, optional AI off" "Some Paint AI policies on"
        $hints += "Disabled: $($disabled -join ', ')"
        $hints += "Not disabled: $($enabledMissing -join ', ')"
    } else {
        Set-ScanStatus $r "Installed" "No Paint AI disable policies; features allowed if hardware supports them"
        $hints += "No DisableCocreator / DisableImageCreator / related policies"
    }
    $r.Details = $hints -join " | "
    return $r
}

function Scan-GeminiChrome {
    $r = New-Result "Google Gemini (in Chrome)"
    $r.DisableHint = "Chrome Settings > System > turn off On-device AI."

    $chromeExe = Test-PathAny @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    if (-not $chromeExe) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Google Chrome not found"
        $r.DisableHint = ""
        return $r
    }
    $r.Installed = $true
    $r.Details = "Chrome: $chromeExe"
    $r.Version = Get-FileVersionSafe $chromeExe

    $signals = @()
    $weightsPresent = $false
    $folderPresent = $false
    $userDisabled = $false
    $policyDisabled = $false
    $settingsEnabled = $null  # $true / $false / $null unknown

    # --- Policy disable (strongest) ---
    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Google\Chrome",
        "HKCU:\SOFTWARE\Policies\Google\Chrome",
        "HKLM:\SOFTWARE\Policies\Google\Chrome\Recommended",
        "HKCU:\SOFTWARE\Policies\Google\Chrome\Recommended"
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

    # --- Local State: user On-device AI toggle (kOnDeviceAiUserSettingsEnabled) ---
    $localState = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
    if (Test-Path $localState) {
        try {
            $content = Get-Content $localState -Raw -ErrorAction Stop

            # Explicit user setting for On-device AI toggle
            if ($content -match '"on_device_ai_user_settings_enabled"\s*:\s*false') {
                $userDisabled = $true
                $settingsEnabled = $false
                $signals += "On-device AI setting OFF (Local State)"
            } elseif ($content -match '"on_device_ai_user_settings_enabled"\s*:\s*true') {
                $settingsEnabled = $true
                $signals += "On-device AI setting ON (Local State)"
            }

            # Alternate key shapes Chrome has used
            if ($content -match '"OnDeviceAiUserSettingsEnabled"\s*:\s*false') {
                $userDisabled = $true
                $settingsEnabled = $false
                $signals += "OnDeviceAiUserSettingsEnabled=false"
            } elseif ($content -match '"OnDeviceAiUserSettingsEnabled"\s*:\s*true') {
                $settingsEnabled = $true
            }

            # optimization_guide model execution prefs often nest under local state
            if ($content -match '"model_execution"[^}]{0,200}"enabled"\s*:\s*false') {
                $userDisabled = $true
                $signals += "model_execution enabled=false"
            }

            # Eligibility alone is NOT activation
            if ($content -match '"is_glic_eligible"\s*:\s*true') {
                $signals += "is_glic_eligible=true (eligibility only)"
            }
        } catch {}
    }

    # --- Model files on disk ---
    $modelBases = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\OptGuideOnDeviceModel",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\OptGuideOnDeviceModel"
    )
    foreach ($modelBase in $modelBases) {
        if (-not (Test-Path $modelBase)) { continue }
        $folderPresent = $true
        $weights = Get-ChildItem -Path $modelBase -Recurse -Filter "weights.bin" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($weights -and $weights.Length -gt 50MB) {
            $weightsPresent = $true
            $sizeGB = [math]::Round($weights.Length / 1GB, 2)
            $signals += "weights.bin ~${sizeGB}GB still on disk"
            break
        } else {
            $signals += "OptGuideOnDeviceModel folder (no large weights.bin)"
        }
    }

    # --- Decision (setting/policy win over residual files) ---
    if ($policyDisabled) {
        Set-ScanStatus $r "Deactivated" "Blocked by policy"
        if ($weightsPresent) {
            $r.Details += " | Residual model files may remain until Chrome cleans up"
        }
    } elseif ($userDisabled -or $settingsEnabled -eq $false) {
        Set-ScanStatus $r "Deactivated" "On-device AI off in Settings"
        if ($weightsPresent) {
            Set-ScanStatus $r "Deactivated" "Setting OFF; residual weights still on disk"
            $r.Details += " | Close Chrome fully; if weights remain, delete OptGuideOnDeviceModel"
        } elseif ($folderPresent) {
            $r.Details += " | Empty or partial model folder leftover"
        }
    } elseif ($weightsPresent -and $settingsEnabled -ne $false) {
        # Real activation: large model present and setting not off
        Set-ScanStatus $r "Activated" "On-device model on disk"
    } elseif ($settingsEnabled -eq $true -and -not $weightsPresent) {
        Set-ScanStatus $r "Activated" "Enabled in Settings; model not downloaded yet"
    } elseif ($folderPresent) {
        Set-ScanStatus $r "Installed, optional AI off" "Model folder only; not treated as active"
    } else {
        $r.Installed = $false
        Set-ScanStatus $r "None Found on Disk" "Chrome present; no on-device Gemini model"
    }

    if ($signals.Count -gt 0) {
        $r.Details += " | " + ($signals -join "; ")
    } else {
        $r.Details += " | No Gemini Nano weights or disable flags found"
    }
    return $r
}

function Scan-ChatGPT {
    $r = New-Result "ChatGPT (OpenAI Desktop)"
    $pkgs = Get-AppxByName "OpenAI.ChatGPT*"
    if (-not $pkgs) { $pkgs = Get-AppxByName "OpenAI.Codex*" }
    if (-not $pkgs) { $pkgs = Get-AppxByName "*ChatGPT*" }
    if (-not $pkgs) { $pkgs = Get-AppxByName "OpenAI.*" }

    if ($pkgs) {
        $pkg = $pkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "Package: $($pkg.Name) | Status: $($pkg.Status)"
        Set-ScanStatus $r "Installed" "Package status: $($pkg.Status)"
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

    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($pkgFolder) {
        $r.Installed = $true
        $r.Details = "Package folder: $pkgFolder"
        Set-ScanStatus $r "Installed" "Package present"
    } elseif (Test-Path "$env:USERPROFILE\.codex") {
        $r.Installed = $true
        $r.Details = "Codex data folder: $env:USERPROFILE\.codex"
        Set-ScanStatus $r "Installed" "Codex CLI/data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No OpenAI ChatGPT or Codex Appx package found"
    }
    return $r
}

function Scan-Claude {
    $r = New-Result "Claude (Anthropic Desktop)"
    $pkgs = Get-AppxByName "Claude*"
    if ($pkgs) {
        $pkg = $pkgs | Select-Object -First 1
        $r.Installed = $true
        $r.Version = $pkg.Version
        $r.Details = "Package: $($pkg.Name) | Status: $($pkg.Status)"
        Set-ScanStatus $r "Installed" "Package status: $($pkg.Status)"
        return $r
    }

    $found = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Claude",
        "$env:LOCALAPPDATA\AnthropicClaude",
        "$env:APPDATA\Claude"
    )
    if ($found) {
        $r.Installed = $true
        $r.Details = "Found at: $found"
        Set-ScanStatus $r "Installed" "Folder present"
    }

    $pkgDir = "$env:LOCALAPPDATA\Packages"
    if (Test-Path $pkgDir) {
        $claudePkg = Get-ChildItem $pkgDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Claude_*" } | Select-Object -First 1
        if ($claudePkg) {
            $r.Installed = $true
            $r.Details = "MSIX package folder: $($claudePkg.Name)"
            Set-ScanStatus $r "Installed" "Package present"
        }
    }
    if (-not $r.Installed) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Claude Appx package or install folder found"
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
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        Set-ScanStatus $r "Installed"
        $r.Version = Get-FileVersionSafe $exe
    } elseif (Test-Path "$env:APPDATA\Perplexity") {
        $r.Installed = $true
        $r.Details = "Data folder: $env:APPDATA\Perplexity"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Perplexity executable or data folder found"
    }
    return $r
}

function Scan-EdgeCopilot {
    $r = New-Result "Microsoft Edge + Copilot / AI"
    $r.DisableHint = "Edge Settings > Sidebar > turn off Copilot / AI features."
    $edge = Test-PathAny @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
    )
    if (-not $edge) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Microsoft Edge not found"
        return $r
    }

    $r.Installed = $true
    $r.Details = "Edge: $edge"
    $r.Version = Get-FileVersionSafe $edge
    Set-ScanStatus $r "Installed, optional AI off" "Copilot Sidebar may need user enable"

    # Policy / feature registry signals for Edge Copilot / sidebar AI
    $activatedHints = @()
    $disabled = $false

    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
        "HKCU:\SOFTWARE\Policies\Microsoft\Edge",
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended"
    )) {
        try {
            $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            if ($null -ne $props.HubsSidebarEnabled -and $props.HubsSidebarEnabled -eq 0) {
                $disabled = $true
                $activatedHints += "Policy HubsSidebarEnabled=0"
            }
            if ($null -ne $props.CopilotPage -and $props.CopilotPage -eq 0) {
                $disabled = $true
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

    # Edge Preferences: require explicit Copilot/chat keys, not generic "sidebar"
    $prefs = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
    if (Test-Path $prefs) {
        try {
            $pr = Get-Content $prefs -Raw -ErrorAction Stop
            if ($pr -match '"copilot_page"\s*:\s*true' -or $pr -match '"show_copilot"\s*:\s*true') {
                $activatedHints += "Preferences Copilot enabled"
            }
            if ($pr -match '"copilot_page"\s*:\s*false' -or $pr -match '"show_copilot"\s*:\s*false') {
                $disabled = $true
                $activatedHints += "Preferences Copilot disabled"
            }
        } catch {}
    }

    if ($disabled) {
        Set-ScanStatus $r "Installed, optional AI off" "AI Sidebar disabled by policy or setting"
        if ($activatedHints.Count -gt 0) { $r.Details += " | " + ($activatedHints -join "; ") }
    } elseif ($activatedHints -match 'enabled|=1') {
        Set-ScanStatus $r "Activated" "Edge Copilot policy/setting ON"
        $r.Details += " | " + ($activatedHints -join "; ")
    } else {
        Set-ScanStatus $r "Installed, optional AI off" "Copilot Sidebar may need user enable"
    }
    return $r
}

function Scan-Ollama {
    $r = New-Result "Ollama (Local LLM Runtime)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe",
        "${env:ProgramFiles}\Ollama\ollama.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Ollama\ollama.exe"
    )
    $models = Test-Path "$env:USERPROFILE\.ollama"
    $logs = Test-Path "$env:LOCALAPPDATA\Ollama"

    if ($exe) {
        $r.Installed = $true
        $r.Details = "Binary: $exe"
        $r.Version = Get-FileVersionSafe $exe
        if ($models) { $r.Details += " | Models folder present" }
        $proc = Get-Process -Name "ollama*" -ErrorAction SilentlyContinue
        if ($proc) {
            Set-ScanStatus $r "Installed" "Process running - see Running column for loaded models"
        } else {
            Set-ScanStatus $r "Installed" "Process not running"
        }
    } elseif ($models -or $logs) {
        $r.Installed = $true
        $r.Details = "Data and logs found. Binary may be in a custom path"
        Set-ScanStatus $r "Installed" "Data only, no binary in default path"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Ollama binary or .ollama data folder found"
    }
    return $r
}

function Scan-LMStudio {
    $r = New-Result "LM Studio (Local LLM GUI)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe",
        "$env:LOCALAPPDATA\Programs\LM-Studio\LM Studio.exe",
        "${env:ProgramFiles}\LM Studio\LM Studio.exe"
    )
    $data = Test-PathAny @(
        "$env:USERPROFILE\.lmstudio",
        "$env:USERPROFILE\.cache\lm-studio",
        "$env:LOCALAPPDATA\lm-studio"
    )

    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        if ($data) { $r.Details += " | Data folder present" }
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder found: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No LM Studio executable or data folder found"
    }
    return $r
}

function Scan-Jan {
    $r = New-Result "Jan (Local LLM)"
    $data = Test-PathAny @(
        "$env:APPDATA\Jan",
        "$env:LOCALAPPDATA\Programs\Jan",
        "$env:LOCALAPPDATA\Jan"
    )
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Jan\Jan.exe",
        "$env:LOCALAPPDATA\Programs\jan\Jan.exe"
    )

    if ($exe -or $data) {
        $r.Installed = $true
        if ($exe) {
            $r.Details = "Executable: $exe"
            $r.Version = Get-FileVersionSafe $exe
        } else {
            $r.Details = "Data folder: $data"
        }
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Jan executable or data folder found"
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
        foreach ($uninst in @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )) {
            try {
                $hit = Get-ItemProperty $uninst -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*GPT4All*" } |
                    Select-Object -First 1
                if ($hit) {
                    if ($hit.DisplayIcon -and (Test-Path $hit.DisplayIcon)) { $exe = $hit.DisplayIcon }
                    elseif ($hit.InstallLocation) {
                        $cand = Test-PathAny @(
                            (Join-Path $hit.InstallLocation "bin\chat.exe"),
                            (Join-Path $hit.InstallLocation "chat.exe"),
                            (Join-Path $hit.InstallLocation "gpt4all.exe")
                        )
                        if ($cand) { $exe = $cand }
                    }
                    if (-not $r.Version -and $hit.DisplayVersion) { $r.Version = [string]$hit.DisplayVersion }
                    break
                }
            } catch {}
        }
    }

    $data = Test-PathAny @(
        "$env:APPDATA\nomic.ai",
        "$env:LOCALAPPDATA\nomic.ai\GPT4All"
    )

    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        if (-not $r.Version) { $r.Version = Get-FileVersionSafe $exe }
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No GPT4All folder or executable found"
    }
    return $r
}

function Scan-Cursor {
    $r = New-Result "Cursor (AI Code Editor)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:LOCALAPPDATA\Programs\Cursor\Cursor.exe",
        "${env:ProgramFiles}\cursor\Cursor.exe",
        "${env:ProgramFiles}\Cursor\Cursor.exe"
    )

    # Registry uninstall entries
    $regFound = $false
    $uninstallKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $uninstallKeys) {
        try {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName -like "*Cursor*" -and $item.DisplayName -notlike "*Mouse*" -and $item.DisplayName -notlike "*Cursor Hero*") {
                    $regFound = $true
                    if (-not $exe -and $item.InstallLocation) {
                        $cand = Join-Path $item.InstallLocation "Cursor.exe"
                        if (Test-Path $cand) { $exe = $cand }
                    }
                    break
                }
            }
        } catch {}
        if ($regFound) { break }
    }

    if ($exe -or $regFound) {
        $r.Installed = $true
        if ($exe) {
            $r.Details = "Executable: $exe"
            $r.Version = Get-FileVersionSafe $exe
        } else {
            $r.Details = "Detected via uninstall registry"
        }
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Cursor executable or registry entry found"
    }
    return $r
}

function Scan-WindowsAIComponents {
    $r = New-Result "Windows On-Device AI Components (Phi Silica / Foundry / etc.)"
    # These are system components on Copilot+ and recent Windows 11
    $indicators = @()

    # Common Appx / system packages related to Windows AI
    if ($null -eq $script:AllAppx) {
        $script:AllAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    }
    $aiPkgs = @($script:AllAppx | Where-Object {
        $_.Name -match "Windows\.AI|Microsoft\.Windows\.AI|PhiSilica|WindowsAI|AI\.Model"
    })

    if ($aiPkgs) {
        $r.Installed = $true
        $names = ($aiPkgs | Select-Object -First 3 -ExpandProperty Name) -join ", "
        $r.Details = "Related packages found: $names"
        Set-ScanStatus $r "Installed" "System components present"
    }

    # Check for known model / component folders (approximate)
    $possible = @(
        "$env:ProgramData\Microsoft\Windows\AI",
        "$env:LOCALAPPDATA\Microsoft\Windows\AI"
    )
    foreach ($p in $possible) {
        if (Test-Path $p) {
            $r.Installed = $true
            $r.Details += " | Path indicator: $p"
            break
        }
    }

    if (-not $r.Installed) {
        Set-ScanStatus $r "Not Installed" "Not detected"
        $r.Details = "No Windows AI packages or known AI component folders found"
    } elseif (-not $r.Activated -or $r.Activated -eq "Not Installed") {
        Set-ScanStatus $r "Installed" "System components present"
    }
    $consent = Get-SystemAiConsent
    if ($consent.Signals.Count -gt 0) {
        if ($r.Details) { $r.Details += " | " }
        $r.Details += ($consent.Signals -join "; ")
        if ($r.Installed -and $consent.Denied) {
            Set-ScanStatus $r "Deactivated" "Text and image generation = Deny"
        } elseif ($r.Installed -and $consent.Allowed) {
            # Consent Allow is not enough to mark Activated
            if ($r.Details) { $r.Details += " | Text and image generation = Allow" }
        }
    }
    return $r
}

function Scan-GitHubCopilot {
    $r = New-Result "GitHub Copilot (VS Code / Visual Studio)"
    # Extension folders
    $extPaths = @(
        "$env:USERPROFILE\.vscode\extensions",
        "$env:USERPROFILE\.vscode-insiders\extensions",
        "$env:APPDATA\Code\User\extensions",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\resources\app\extensions"
    )
    $found = $false
    foreach ($base in $extPaths) {
        if (Test-Path $base) {
            $copilotExt = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "github.copilot*" }
            if ($copilotExt) {
                $found = $true
                $r.Details = "Extension folder: $($copilotExt[0].FullName)"
                break
            }
        }
    }
    # Also check for GitHub Copilot app / CLI remnants
    if (Test-Path "$env:LOCALAPPDATA\GitHubCopilot") { $found = $true; $r.Details += " | GitHubCopilot data" }

    if ($found) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Extension detected"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No GitHub Copilot extension folders found"
    }
    return $r
}

function Scan-ComfyUI {
    $r = New-Result "ComfyUI / Stable Diffusion WebUI (common)"
    $markers = @(
        "$env:USERPROFILE\ComfyUI",
        "$env:USERPROFILE\stable-diffusion-webui",
        "$env:USERPROFILE\Documents\ComfyUI",
        "C:\ComfyUI",
        "D:\ComfyUI",
        "$env:LOCALAPPDATA\Programs\ComfyUI"
    )
    $found = Test-PathAny $markers
    if ($found) {
        $r.Installed = $true
        $r.Details = "Folder: $found"
        Set-ScanStatus $r "Installed" "Install folder present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No ComfyUI or stable-diffusion-webui folder in common locations"
    }
    return $r
}

function Scan-OperaAI {
    $r = New-Result "Opera Browser (Aria / Opera AI)"
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
            $r.Details = "Detected via App Paths registry"
            Set-ScanStatus $r "Installed, optional AI off" "AI activation not confirmed"
            return $r
        }
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Opera not found"
        return $r
    }

    $r.Installed = $true
    $r.Details = "Executable: $exe"
    $r.Version = Get-FileVersionSafe $exe
    Set-ScanStatus $r "Installed, optional AI off" "Aria activation not confirmed"

    # Opera prefs often under Local AppData Opera Stable
    $prefCandidates = @(
        "$env:APPDATA\Opera Software\Opera Stable\Preferences",
        "$env:APPDATA\Opera Software\Opera GX Stable\Preferences",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\Preferences"
    )
    foreach ($pref in $prefCandidates) {
        if (-not (Test-Path $pref)) { continue }
        try {
            $content = Get-Content $pref -Raw -ErrorAction Stop
            if ($content -match '(?i)aria|opera.?ai|sidebar.*ai|ai.?assistant') {
                Set-ScanStatus $r "Activated" "Aria and Opera AI prefs found"
                $r.Details += " | Prefs: $pref"
                break
            }
        } catch {}
    }
    return $r
}

function Scan-BraveLeo {
    $r = New-Result "Brave Browser (Leo AI)"
    $r.DisableHint = "Brave Settings > Leo > turn off Leo AI."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    if (-not $exe) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Brave Browser not found"
        return $r
    }

    $r.Installed = $true
    $r.Details = "Executable: $exe"
    $r.Version = Get-FileVersionSafe $exe
    Set-ScanStatus $r "Installed, optional AI off" "Leo activation not confirmed"

    # Policy can disable Leo
    foreach ($p in @(
        "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave",
        "HKCU:\SOFTWARE\Policies\BraveSoftware\Brave"
    )) {
        try {
            $val = Get-ItemProperty -Path $p -Name "BraveAIChatEnabled" -ErrorAction SilentlyContinue
            if ($null -ne $val -and $val.BraveAIChatEnabled -eq 0) {
                Set-ScanStatus $r "Installed, optional AI off" "Leo disabled by policy"
                $r.Details += " | BraveAIChatEnabled=0"
                return $r
            }
            if ($null -ne $val -and $val.BraveAIChatEnabled -eq 1) {
                Set-ScanStatus $r "Activated" "Leo enabled by policy"
                $r.Details += " | BraveAIChatEnabled=1"
            }
        } catch {}
    }

    $prefs = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Preferences"
    $localState = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Local State"
    foreach ($f in @($prefs, $localState)) {
        if (-not (Test-Path $f)) { continue }
        try {
            $content = Get-Content $f -Raw -ErrorAction Stop
            if ($content -match '(?i)brave\.ai_chat|leo|ai_chat\.|sidebar.*leo') {
                if ($r.Activated -notlike "Activated*") {
                    Set-ScanStatus $r "Activated" "Leo AI config found"
                }
                $r.Details += " | Config signal in $(Split-Path $f -Leaf)"
                break
            }
        } catch {}
    }
    return $r
}

function Scan-Comet {
    $r = New-Result "Perplexity Comet Browser"
    $r.DisableHint = "Comet Settings > turn off AI features (or uninstall Comet from Windows Settings > Apps)."
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Perplexity\Comet\Application\comet.exe",
        "$env:LOCALAPPDATA\Programs\Comet\comet.exe",
        "${env:ProgramFiles}\Comet\comet.exe"
    )
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed" "AI-native browser"
    } elseif (Test-Path "$env:LOCALAPPDATA\Perplexity\Comet") {
        $r.Installed = $true
        $r.Details = "Comet folder present"
        Set-ScanStatus $r "Installed" "AI-native browser"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Perplexity Comet not found"
        return $r
    }

    $prefs = "$env:LOCALAPPDATA\Perplexity\Comet\User Data\Default\Preferences"
    if (Test-Path $prefs) {
        try {
            $pr = Get-Content $prefs -Raw -ErrorAction Stop
            if ($pr -match '"ai_enabled"\s*:\s*false' -or $pr -match '"comet_ai"\s*:\s*false' -or $pr -match '"assistant_enabled"\s*:\s*false') {
                Set-ScanStatus $r "Installed, optional AI off" "AI setting off in Comet preferences"
            } elseif ($pr -match '"ai_enabled"\s*:\s*true' -or $pr -match '"comet_ai"\s*:\s*true') {
                Set-ScanStatus $r "Activated" "AI setting on in Comet preferences"
            }
        } catch {}
    }
    return $r
}

function Scan-Firefox {
    $r = New-Result "Mozilla Firefox (optional AI features)"
    $r.DisableHint = "Firefox Settings > AI Controls > turn on Block AI enhancements."
    $exe = Test-PathAny @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe"
    )
    if (-not $exe) {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "Firefox not found"
        $r.DisableHint = ""
        return $r
    }

    $r.Installed = $true
    $r.Details = "Executable: $exe"
    $r.Version = Get-FileVersionSafe $exe

    $enabledFlags = @()
    $disabledFlags = @()
    $blockedControls = @()
    $profileChecked = $false

    $profilesRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $profilesRoot) {
        try {
            # Prefer user.js overrides, then prefs.js (default + first few profiles)
            $files = @()
            $files += Get-ChildItem $profilesRoot -Recurse -Filter "user.js" -ErrorAction SilentlyContinue | Select-Object -First 3
            $files += Get-ChildItem $profilesRoot -Recurse -Filter "prefs.js" -ErrorAction SilentlyContinue | Select-Object -First 5

            foreach ($pf in $files) {
                $profileChecked = $true
                $c = Get-Content $pf.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $c) { continue }

                # Master / feature booleans that are ON
                $onPrefs = @(
                    'browser\.ml\.enable',
                    'browser\.ml\.chat\.enabled',
                    'browser\.ml\.chat\.sidebar',
                    'browser\.ml\.chat\.menu',
                    'browser\.ml\.chat\.page',
                    'browser\.ml\.linkPreview\.enabled',
                    'browser\.ml\.pageAssist\.enabled',
                    'browser\.ml\.smartAssist\.enabled',
                    'extensions\.ml\.enabled',
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

                # AI Controls string prefs: "blocked" | "available" | "enabled"
                $controlPrefs = @(
                    'browser\.ai\.control\.default',
                    'browser\.ai\.control\.sidebarChatbot',
                    'browser\.ai\.control\.linkPreviewKeyPoints',
                    'browser\.ai\.control\.smartTabGroups',
                    'browser\.ai\.control\.translations',
                    'browser\.ai\.control\.pdfjsAltText'
                )
                foreach ($p in $controlPrefs) {
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*`"blocked`"\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($blockedControls -notcontains $short) { $blockedControls += $short }
                    }
                    if ($c -match ("user_pref\(\s*`"$p`"\s*,\s*`"enabled`"\s*\)")) {
                        $short = ($p -replace '\\', '')
                        if ($enabledFlags -notcontains $short) { $enabledFlags += $short }
                    }
                }
            }
        } catch {
            Write-ErrorLog "Firefox prefs scan failed" -ErrorRecord $_
        }
    }

    # Decision: blocked/disabled wins if master controls say so
    $masterBlocked = ($blockedControls -contains 'browser.ai.control.default') -or
                     ($disabledFlags -contains 'browser.ml.enable')

    if ($masterBlocked -and $enabledFlags.Count -eq 0) {
        Set-ScanStatus $r "Deactivated" "AI blocked in Firefox Settings"
        $parts = @()
        if ($blockedControls.Count -gt 0) { $parts += "blocked: $($blockedControls.Count) controls" }
        if ($disabledFlags.Count -gt 0) { $parts += "off: $($disabledFlags.Count) ml prefs" }
        $r.Details += " | " + ($parts -join "; ")
    } elseif ($enabledFlags.Count -gt 0) {
        Set-ScanStatus $r "Activated" "AI features enabled in prefs"
        $sample = ($enabledFlags | Select-Object -First 4) -join ", "
        $r.Details += " | Enabled: $sample"
        if ($blockedControls.Count -gt 0) {
            $r.Details += " | Some controls blocked: $($blockedControls.Count)"
        }
    } elseif ($disabledFlags.Count -gt 0 -or $blockedControls.Count -gt 0) {
        Set-ScanStatus $r "Deactivated" "AI prefs set off/blocked"
        $r.Details += " | disabled=$($disabledFlags.Count); blocked=$($blockedControls.Count)"
    } elseif ($profileChecked) {
        # No AI prefs written = Firefox default: AI available but not forced on
        Set-ScanStatus $r "Installed, optional AI off" "AI optional; not enabled in prefs"
        $r.Details += " | No browser.ml or AI Controls overrides found. Defaults apply"
    } else {
        Set-ScanStatus $r "Installed, optional AI off" "Could not read Firefox profile prefs"
        $r.Details += " | Profiles folder missing or empty"
    }
    return $r
}

function Scan-GrokNote {
    $r = New-Result "Grok (xAI)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Grok\Grok.exe",
        "$env:LOCALAPPDATA\Grok\Grok.exe",
        "${env:ProgramFiles}\Grok\Grok.exe"
    )
    $data = Test-PathAny @(
        "$env:APPDATA\Grok",
        "$env:LOCALAPPDATA\Packages\Grok*"
    )
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data package: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        $r.Installed = $false
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No official desktop app. Use the web app, PWA, or mobile app"
    }
    return $r
}

function Scan-Windsurf {
    $r = New-Result "Windsurf (AI Code Editor)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Programs\Windsurf\Windsurf.exe",
        "${env:ProgramFiles}\Windsurf\Windsurf.exe",
        "${env:ProgramFiles(x86)}\Windsurf\Windsurf.exe"
    )
    $data = Test-PathAny @(
        "$env:APPDATA\Windsurf",
        "$env:USERPROFILE\.codeium\windsurf"
    )
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Windsurf executable or data folder found"
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

function Initialize-ModelNameIndex {
    if ($script:ModelNameIndex) { return }

    $names = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $add = {
        param([string]$n)
        if (-not $n) { return }
        if ($seen.ContainsKey($n)) { return }
        $seen[$n] = $true
        [void]$names.Add($n)
    }

    foreach ($root in @(Get-ModelStorageRoots | Select-Object -Unique)) {
        if (-not (Test-Path $root)) { continue }
        try {
            Get-ChildItem -Path $root -Recurse -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^(blobs|sha256|\.git)$' } |
                ForEach-Object { & $add $_.Name }
            Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -match '^\.(gguf|safetensors|ggml|bin|ot)$' -and
                    $_.FullName -notmatch '\\blobs\\'
                } |
                ForEach-Object { & $add $_.Name }
        } catch {
            Write-ErrorLog "Error indexing models in $root" -ErrorRecord $_
        }
    }

    try {
        $apiTags = @(Get-OllamaInstalledTags)
        foreach ($tag in $apiTags) { & $add $tag }
        if ($apiTags.Count -eq 0) {
            $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
            if (-not $ollamaCmd) {
                foreach ($c in @(
                    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
                    "${env:ProgramFiles}\Ollama\ollama.exe"
                )) {
                    if (Test-Path $c) { $ollamaCmd = $c; break }
                }
            }
            if ($ollamaCmd) {
                $exe = if ($ollamaCmd -is [string]) { $ollamaCmd } else { $ollamaCmd.Source }
                $listOut = & $exe list 2>$null
                if ($listOut) {
                    foreach ($line in $listOut) {
                        $t = "$line".Trim()
                        if ($t -eq "" -or $t -match "^NAME") { continue }
                        & $add (($t -split '\s+')[0])
                    }
                }
            }
        }
    } catch {
        Write-ErrorLog "ollama list check failed" -ErrorRecord $_
    }

    $script:ModelNameIndex = @($names)
    Write-ErrorLog "Model name index size: $($script:ModelNameIndex.Count)"
}

function Find-ModelFamilyOnDisk {
    param(
        [string[]]$Keywords,
        [switch]$Aggressive
    )
    Initialize-ModelNameIndex
    $hits = @()
    $sampleFiles = @()
    foreach ($n in $script:ModelNameIndex) {
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
    return [PSCustomObject]@{
        Found = ($hits.Count -gt 0)
        Count = $hits.Count
        Samples = $sampleFiles
        UniqueHints = @($hits | Select-Object -Unique | Select-Object -First 8)
    }
}

function New-ModelFamilyResult {
    param(
        [string]$DisplayName,
        [string[]]$Keywords,
        [string]$ProviderNote = "",
        [switch]$Aggressive
    )
    $r = New-Result $DisplayName
    Set-ScanStatus $r "None Found on Disk"
    $search = Find-ModelFamilyOnDisk -Keywords $Keywords -Aggressive:$Aggressive
    if ($search.Found) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Model weights found on disk"
        $parts = @()
        if ($ProviderNote) { $parts += $ProviderNote }
        if ($search.UniqueHints.Count -gt 0) {
            $parts += "Matches: " + ($search.UniqueHints -join ", ")
        }
        $parts += "Hit count: $($search.Count)"
        $r.Details = $parts -join " | "
    } else {
        $r.Details = "No matching model files or tags found"
    }
    return $r
}

function Scan-Qwen {
    New-ModelFamilyResult -DisplayName "Qwen 3 / 3.5-3.8 / 3.8-Max / Flash-Next / Qwen4 (Alibaba)" -ProviderNote "Alibaba open-weight family (3.8-Max / 27B / Flash-Next Aug 2026)" -Keywords @(
        '(?i)qwen4-coder',
        '(?i)qwen4',
        '(?i)qwen3\.?8-flash-next',
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
    New-ModelFamilyResult -DisplayName "Llama 3.1 / 3.2 / 3.3 / 4 Scout-Maverick (Meta)" -ProviderNote "Meta Llama family (Llama 5 not publicly released)" -Keywords @(
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
    # Aggressive: broad patterns for R1, V3, V4, coder, distill, MoE variants
    New-ModelFamilyResult -DisplayName "DeepSeek (R1 / V3.2 / V4 / V4.1 Flash-Pro / Vision)" -ProviderNote "DeepSeek - aggressive match (R2 not released)" -Aggressive -Keywords @(
        '(?i)deepseek-v4\.1-flash',
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
        '(?i)dspark',
        '(?i)r1-distill',
        '(?i)r1_distill',
        '(?i)deepseekr1',
        '(?i)ds-r1',
        '(?i)ds_r1',
        '(?i)ds-v3',
        '(?i)ds-v4',
        '(?i)v4-flash',
        '(?i)v4-pro',
        '(?i)v4pro'
    )
}

function Scan-Gemma {
    New-ModelFamilyResult -DisplayName "Gemma 3 / 4 / MedGemma / TranslateGemma (Google)" -ProviderNote "Google Gemma family (Gemma 4 12B Unified Jun 2026; no Gemma 5)" -Keywords @(
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
        '(?i)gemma'
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
        '(?i)granite-guardian',
        '(?i)granite'
    )
}

function Scan-GLM {
    New-ModelFamilyResult -DisplayName "GLM-4.7 / 5 / 5.1 / 5.2 / 5.3 (Zhipu)" -ProviderNote "Zhipu / zai-org GLM family" -Keywords @(
        '(?i)glm-?5\.3-flash',
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
    New-ModelFamilyResult -DisplayName "Mistral / Mixtral / Devstral / Small 4 / Large 3 / Voyage" -ProviderNote "Mistral AI family" -Keywords @(
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

function Scan-GptOss {
    # Model used by PromptLock (ESET) via local Ollama API
    New-ModelFamilyResult -DisplayName "gpt-oss (OpenAI open-weight)" -ProviderNote "OpenAI gpt-oss family (seen with local Ollama in malware research)" -Aggressive -Keywords @(
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
    New-ModelFamilyResult -DisplayName "Nemotron 3 / 3.5 Lightning (NVIDIA)" -ProviderNote "NVIDIA Nemotron open models (local agent use)" -Keywords @(
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
    New-ModelFamilyResult -DisplayName "Muse Glimmer / Spark (Meta)" -ProviderNote "Meta Superintelligence Labs (Glimmer open weights; Spark if downloaded)" -Keywords @(
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
    New-ModelFamilyResult -DisplayName "Kimi K2 / K2.6 / K2.7 / K3 (Moonshot)" -ProviderNote "Moonshot open-weight family (popular local pulls)" -Keywords @(
        '(?i)kimi-k3',
        '(?i)kimi-k2\.7',
        '(?i)kimi-k2\.6',
        '(?i)kimi-k2\.5',
        '(?i)kimi-k2',
        '(?i)kimi-k1',
        '(?i)moonshot-kimi',
        '(?i)moonshotai',
        '(?i)kimi'
    )
}

function Scan-MiniMax {
    New-ModelFamilyResult -DisplayName "MiniMax M2.5 / M2.7 / M3" -ProviderNote "MiniMax open-weight family (M3 widely pulled in 2026)" -Keywords @(
        '(?i)minimax-m3',
        '(?i)minimax-m2\.7',
        '(?i)minimax-m2\.5',
        '(?i)minimax-m2',
        '(?i)minimax-text',
        '(?i)minimax-vl',
        '(?i)minimax'
    )
}

function Scan-FoundryLocal {
    $r = New-Result "Foundry Local (Microsoft)"
    $exe = Test-PathAny @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Microsoft.FoundryLocal*\foundry.exe",
        "$env:LOCALAPPDATA\Programs\FoundryLocal\foundry.exe",
        "${env:ProgramFiles}\Microsoft Foundry Local\foundry.exe",
        "$env:LOCALAPPDATA\FoundryLocal\foundry.exe"
    )
    if (-not $exe) {
        $cmd = Get-Command foundry -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
    }
    $data = Test-PathAny @(
        "$env:USERPROFILE\.foundry",
        "$env:LOCALAPPDATA\Microsoft\FoundryLocal",
        "$env:LOCALAPPDATA\FoundryLocal"
    )
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Foundry Local executable or data folder found"
    }
    return $r
}

function Scan-LlamaCpp {
    $r = New-Result "llama.cpp / llama-server"
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
        foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\llama.cpp", "$env:USERPROFILE\llamacpp")) {
            if (-not (Test-Path $dir)) { continue }
            $hit = Get-ChildItem $dir -Recurse -Include "llama-server.exe","llama-cli.exe","llama-bench.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $foundExe = $hit.FullName; break }
        }
    }
    $folder = Test-PathAny @(
        "$env:USERPROFILE\llama.cpp",
        "$env:USERPROFILE\llamacpp",
        "C:\llama.cpp"
    )
    if ($foundExe) {
        $r.Installed = $true
        $r.Details = "Executable: $foundExe"
        $r.Version = Get-FileVersionSafe $foundExe
        Set-ScanStatus $r "Installed"
    } elseif ($folder) {
        $r.Installed = $true
        $r.Details = "Folder: $folder"
        Set-ScanStatus $r "Installed" "Install folder present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No llama-server or llama-cli in common paths"
    }
    return $r
}

function Scan-Vllm {
    $r = New-Result "vLLM (Local Inference Server)"
    # Windows installs are less common; look for typical project/venv markers
    $markers = @(
        "$env:USERPROFILE\vllm",
        "$env:USERPROFILE\vLLM",
        "$env:LOCALAPPDATA\Programs\Python\*\Lib\site-packages\vllm",
        "$env:USERPROFILE\AppData\Local\Programs\Python\*\Lib\site-packages\vllm"
    )
    $found = $false
    $detail = ""
    foreach ($m in $markers) {
        $resolved = Get-Item $m -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($resolved) {
            $found = $true
            $detail = $resolved.FullName
            break
        }
    }
    # pip show style: search site-packages shallowly under user Python
    if (-not $found) {
        $pyRoots = @(
            "$env:LOCALAPPDATA\Programs\Python",
            "$env:USERPROFILE\AppData\Local\Programs\Python",
            "$env:USERPROFILE\miniconda3",
            "$env:USERPROFILE\anaconda3"
        )
        foreach ($root in $pyRoots) {
            if (-not (Test-Path $root)) { continue }
            $pkg = Get-ChildItem $root -Recurse -Directory -Filter "vllm" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'site-packages\\vllm$' } |
                Select-Object -First 1
            if ($pkg) {
                $found = $true
                $detail = $pkg.FullName
                break
            }
        }
    }
    if ($found) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Python package present"
        $r.Details = "Path: $detail"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No vLLM package or project folder found"
    }
    return $r
}

function Scan-Msty {
    $r = New-Result "Msty (Local LLM App)"
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
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Msty executable or data folder found"
    }
    return $r
}

function Scan-KoboldCpp {
    $r = New-Result "KoboldCPP (Local LLM)"
    $exe = Test-PathAny @(
        "$env:USERPROFILE\koboldcpp\koboldcpp.exe",
        "$env:USERPROFILE\KoboldCPP\koboldcpp.exe",
        "$env:LOCALAPPDATA\Programs\KoboldCPP\koboldcpp.exe",
        "${env:ProgramFiles}\KoboldCPP\koboldcpp.exe"
    )
    # Also search common download folders for koboldcpp*.exe (shallow)
    if (-not $exe) {
        foreach ($dir in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "C:\koboldcpp", "D:\koboldcpp")) {
            if (-not (Test-Path $dir)) { continue }
            $hit = Get-ChildItem $dir -Filter "koboldcpp*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $exe = $hit.FullName; break }
        }
    }
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No koboldcpp executable in common locations"
    }
    return $r
}

function Scan-OpenWebUI {
    $r = New-Result "Open WebUI (Local LLM Frontend)"
    $paths = @(
        "$env:USERPROFILE\open-webui",
        "$env:USERPROFILE\OpenWebUI",
        "$env:LOCALAPPDATA\open-webui",
        "$env:APPDATA\open-webui"
    )
    $found = Test-PathAny $paths
    # Docker/desktop often leaves data under %USERPROFILE%\.open-webui
    $dot = Test-Path "$env:USERPROFILE\.open-webui"
    if ($found -or $dot) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "Data folder present"
        $r.Details = if ($found) { "Path: $found" } else { "Path: $env:USERPROFILE\.open-webui" }
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No Open WebUI folder found"
    }
    return $r
}

function Scan-AnythingLLM {
    $r = New-Result "AnythingLLM (Local RAG / LLM)"
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
    if ($exe) {
        $r.Installed = $true
        $r.Details = "Executable: $exe"
        $r.Version = Get-FileVersionSafe $exe
        Set-ScanStatus $r "Installed"
    } elseif ($data) {
        $r.Installed = $true
        $r.Details = "Data folder: $data"
        Set-ScanStatus $r "Installed" "Data present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No AnythingLLM executable or data folder found"
    }
    return $r
}

function Scan-TextGenWebUI {
    $r = New-Result "text-generation-webui (oobabooga)"
    $markers = @(
        "$env:USERPROFILE\text-generation-webui",
        "$env:USERPROFILE\oobabooga",
        "$env:USERPROFILE\Documents\text-generation-webui",
        "C:\text-generation-webui",
        "D:\text-generation-webui"
    )
    $found = Test-PathAny $markers
    if ($found) {
        $r.Installed = $true
        $r.Details = "Folder: $found"
        Set-ScanStatus $r "Installed" "Install folder present"
    } else {
        Set-ScanStatus $r "Not Installed"
        $r.Details = "No text-generation-webui or oobabooga folder in common locations"
    }
    return $r
}

function Scan-LocalModels {
    $r = New-Result "Local AI Models (other / summary)"
    Set-ScanStatus $r "None Found on Disk"
    $roots = Get-ModelStorageRoots
    $foundPaths = @()
    $ggufCount = 0

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $foundPaths += $root
        try {
            $ggufs = Get-ChildItem -Path $root -Recurse -Filter "*.gguf" -ErrorAction SilentlyContinue -File
            if ($ggufs) { $ggufCount += @($ggufs).Count }
        } catch {}
    }

    if ($ggufCount -gt 0) {
        $r.Installed = $true
        Set-ScanStatus $r "Installed" "GGUF files found"
        $r.Details = "GGUF files: $ggufCount | Roots: " + (($foundPaths | Select-Object -First 4) -join "; ")
    } elseif ($foundPaths.Count -gt 0) {
        $r.Installed = $false
        Set-ScanStatus $r "None Found on Disk" "Storage folders present; no GGUF files"
        $r.Details = "GGUF files: 0 | Roots: " + (($foundPaths | Select-Object -First 4) -join "; ")
    } else {
        $r.Details = "No model folders or GGUF files found in standard locations"
    }
    return $r
}

# ========== GUI ==========
Write-Log "LOAD: building window"

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName v$script:AppVersion"
$form.Size = New-Object System.Drawing.Size(900, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "$script:AppName"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblOS = New-Object System.Windows.Forms.Label
$lblOS.Text = "Windows: " + (Get-WindowsVersionInfo)
$lblOS.Location = New-Object System.Drawing.Point(20, 48)
$lblOS.Size = New-Object System.Drawing.Size(760, 22)
$lblOS.ForeColor = [System.Drawing.Color]::DarkBlue
$form.Controls.Add($lblOS)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Scan for Installed AI"
$btnScan.Location = New-Object System.Drawing.Point(20, 78)
$btnScan.Size = New-Object System.Drawing.Size(180, 34)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = "Flat"
$btnScan.Anchor = "Top, Left"
$form.Controls.Add($btnScan)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(220, 78)
$lblStatus.Size = New-Object System.Drawing.Size(640, 18)
$lblStatus.Anchor = "Top, Left, Right"
$form.Controls.Add($lblStatus)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(220, 98)
$progress.Size = New-Object System.Drawing.Size(640, 16)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Style = "Continuous"
$progress.Anchor = "Top, Left, Right"
$form.Controls.Add($progress)

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 125)
$lv.Size = New-Object System.Drawing.Size(840, 420)
$lv.View = "Details"
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.Anchor = "Top, Bottom, Left, Right"
$lv.Columns.Add("AI Name", 170) | Out-Null
$lv.Columns.Add("Installed", 58) | Out-Null
$lv.Columns.Add("Running", 58) | Out-Null
$lv.Columns.Add("Status", 160) | Out-Null
$lv.Columns.Add("Version", 120) | Out-Null
$lv.Columns.Add("Details", 120) | Out-Null
$lv.Columns.Add("How to disable", 220) | Out-Null
$form.Controls.Add($lv)

function Resize-NameAndDisableColumns {
    param($ListView)
    if (-not $ListView) { return }
    $styleContent = [System.Windows.Forms.ColumnHeaderAutoResizeStyle]::ColumnContent
    $styleHeader = [System.Windows.Forms.ColumnHeaderAutoResizeStyle]::HeaderSize
    foreach ($idx in @(0, 6)) {
        if ($idx -ge $ListView.Columns.Count) { continue }
        $ListView.AutoResizeColumn($idx, $styleHeader)
        $headerW = $ListView.Columns[$idx].Width
        if ($ListView.Items.Count -gt 0) {
            $ListView.AutoResizeColumn($idx, $styleContent)
            $contentW = $ListView.Columns[$idx].Width
            if ($headerW -gt $contentW) {
                $ListView.Columns[$idx].Width = $headerW
            }
        }
    }
}

function Add-SectionHeaderToListView {
    param($ListView, [string]$Title)
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
    [void]$ListView.Items.Add($item)
    $item.EnsureVisible()
}

function Add-ResultToListView {
    param($ListView, $r)
    if (-not $ListView -or -not $r) { return }
    $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
    $item.SubItems.Add( $(if ($r.Installed) { "Yes" } else { "No" }) ) | Out-Null
    $item.SubItems.Add( $r.Running ) | Out-Null
    $item.SubItems.Add( $r.Activated ) | Out-Null
    $item.SubItems.Add( $r.Version ) | Out-Null
    $item.SubItems.Add( $r.Details ) | Out-Null
    $disableText = ""
    if ($r.Installed) {
        $disableText = Get-HowToDisable -Name $r.Name
    }
    $item.SubItems.Add( $disableText ) | Out-Null

    $isRunning = ($r.Running -like "Yes*")
    $st = [string]$r.Activated
    if ($isRunning) {
        $item.ForeColor = [System.Drawing.Color]::Firebrick
    } elseif ($st -eq "Activated") {
        $item.ForeColor = [System.Drawing.Color]::DarkBlue
    } elseif ($st -eq "Installed" -or $st -eq "Installed, optional AI off" -or $st -eq "Deactivated") {
        $item.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $item.ForeColor = [System.Drawing.Color]::Gray
    }
    [void]$ListView.Items.Add($item)
    $item.EnsureVisible()
}

$form.Add_Shown({ Resize-NameAndDisableColumns -ListView $lv })

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Text = "v$script:AppVersion | Colors: Green = Installed | Blue = Activated | Red = Running in memory | Gray = Not installed"
$lblFooter.Location = New-Object System.Drawing.Point(20, 555)
$lblFooter.Size = New-Object System.Drawing.Size(840, 20)
$lblFooter.ForeColor = [System.Drawing.Color]::Gray
$lblFooter.Anchor = "Bottom, Left, Right"
$form.Controls.Add($lblFooter)

$lv.Add_SelectedIndexChanged({
    if ($lv.SelectedItems.Count -gt 0 -and $lv.SelectedItems[0].Tag -eq "section") {
        $lv.SelectedItems.Clear()
    }
})

$btnScan.Add_Click({
    $btnScan.Enabled = $false
    $lblStatus.Text = "Starting scan..."
    $progress.Value = 0
    $lv.Items.Clear()
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    Write-Log "SCAN: started by user"
    $script:AllAppx = $null
    $script:ModelNameIndex = $null

    # --- On-device model check only (not browsers / host apps) ---
    $lblStatus.Text = "Checking for on-device models loaded in memory..."
    $progress.Value = 2
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    $ollamaLoaded = @(Get-OllamaLoadedModels)
    Write-ErrorLog "Ollama loaded models: $(if ($ollamaLoaded.Count -gt 0) { $ollamaLoaded -join ', ' } else { '(none)' })"

    $lmStudioLoaded = @(Get-LmStudioLoadedModels)
    Write-ErrorLog "LM Studio loaded models: $(if ($lmStudioLoaded.Count -gt 0) { $lmStudioLoaded -join ', ' } else { '(none)' })"

    $compatLoaded = @(Get-OpenAiCompatLoadedModels)
    Write-ErrorLog "OpenAI-compat (llama.cpp/etc) models: $(if ($compatLoaded.Count -gt 0) { $compatLoaded -join ', ' } else { '(none)' })"

    $lblStatus.Text = "Indexing local model files and tags..."
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Initialize-ModelNameIndex

    $results = @()
    $scanGroups = @(
        @{
            Header = ""
            Fns = @(
                { Scan-ChatGPT },
                { Scan-Claude },
                { Scan-GrokNote },
                { Scan-Copilot },
                { Scan-Ollama },
                { Scan-Perplexity }
            )
        },
        @{
            Header = ""
            Fns = @(
                { Scan-DeepSeek },
                { Scan-Gemma },
                { Scan-Granite },
                { Scan-GLM },
                { Scan-GptOss },
                { Scan-Kimi },
                { Scan-Llama },
                { Scan-MiniMax },
                { Scan-MistralFamily },
                { Scan-MuseGlimmer },
                { Scan-Nemotron },
                { Scan-Phi },
                { Scan-Qwen },
                { Scan-LocalModels }
            )
        },
        @{
            Header = "Browser-based"
            Fns = @(
                { Scan-BraveLeo },
                { Scan-GeminiChrome },
                { Scan-EdgeCopilot },
                { Scan-Firefox },
                { Scan-OperaAI },
                { Scan-Comet }
            )
        },
        @{
            Header = "Microsoft Apps"
            Fns = @(
                { Scan-FoundryLocal },
                { Scan-GitHubCopilot },
                { Scan-M365Copilot },
                { Scan-NotepadAI },
                { Scan-PaintAI },
                { Scan-WindowsAIComponents }
            )
        },
        @{
            Header = "Other Apps"
            Fns = @(
                { Scan-AnythingLLM },
                { Scan-ComfyUI },
                { Scan-Cursor },
                { Scan-GPT4All },
                { Scan-Jan },
                { Scan-KoboldCpp },
                { Scan-LlamaCpp },
                { Scan-LMStudio },
                { Scan-Msty },
                { Scan-OpenWebUI },
                { Scan-TextGenWebUI },
                { Scan-Vllm },
                { Scan-Windsurf }
            )
        }
    )

    $totalSteps = 0
    foreach ($g in $scanGroups) { $totalSteps += @($g.Fns).Count }
    $step = 0
    $lblStatus.Text = "Scanning installed components..."
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    foreach ($group in $scanGroups) {
        if ($group.Header) {
            Add-SectionHeaderToListView -ListView $lv -Title $group.Header
            [System.Windows.Forms.Application]::DoEvents()
        }
        foreach ($fn in @($group.Fns)) {
        $step++
        $hint = (($fn.ToString() -replace '(?s).*Scan-', 'Scan-') -replace '\s.*', '')
        $pct = [int][Math]::Min(99, [Math]::Round((($step - 1) / [Math]::Max(1, $totalSteps)) * 100))
        $progress.Value = $pct
        $lblStatus.Text = "Scanning $step of $totalSteps : $hint"
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $r = & $fn
            if ($r) {
                $r.Running = Test-IsRunning -AiName $r.Name -OllamaLoadedModels $ollamaLoaded -LmStudioLoadedModels $lmStudioLoaded -CompatLoadedModels $compatLoaded
                $results += $r
                Add-ResultToListView -ListView $lv -r $r
                [System.Windows.Forms.Application]::DoEvents()
                if ($r.Installed -or ($r.Running -like "Yes*")) {
                    $tag = "FOUND"
                    if ($r.Activated -eq "Installed, optional AI off" -or $r.Activated -eq "Deactivated") {
                        $tag = "FOUND (AI off)"
                    }
                    Write-ErrorLog ("{0}: {1} | Installed={2} | Running={3} | Status={4} | Version={5} | Details={6}" -f $tag, $r.Name, $(if ($r.Installed) {"Yes"} else {"No"}), $r.Running, $r.Activated, $r.Version, $r.Details)
                }
            }
        } catch {
            Write-ErrorLog "Error running scanner: $($fn.ToString())" -ErrorRecord $_
            $errResult = New-Result "Scanner Error" $false "Error" $_.Exception.Message
            $errResult.Running = "No"
            $results += $errResult
            Add-ResultToListView -ListView $lv -r $errResult
            [System.Windows.Forms.Application]::DoEvents()
        }
        }
    }

    try {
        $runningCount = ($results | Where-Object { $_.Running -like "Yes*" }).Count
        $activatedCount = ($results | Where-Object { $_.Activated -eq "Activated" -and $_.Running -notlike "Yes*" }).Count
        $installedCount = ($results | Where-Object {
            $_.Running -notlike "Yes*" -and $_.Activated -ne "Activated" -and (
                $_.Activated -eq "Installed" -or
                $_.Activated -eq "Installed, optional AI off" -or
                $_.Activated -eq "Deactivated"
            )
        }).Count
        Resize-NameAndDisableColumns -ListView $lv
        $progress.Value = 100
        $lblStatus.Text = "Scan complete. Installed (Green): $installedCount | Activated (Blue): $activatedCount | Running in memory (Red): $runningCount"
        Write-ErrorLog "Scan finished. Green: $installedCount | Blue: $activatedCount | Red: $runningCount"
    } catch {
        Write-ErrorLog "Error updating UI after scan" -ErrorRecord $_
        $lblStatus.Text = "Scan finished with errors. See Log.txt"
        $progress.Value = 100
    }

    $btnScan.Enabled = $true
})

try {
    Write-Log "LOAD: window ready, opening"
    [void]$form.ShowDialog()
    Write-Log "LOAD: window closed normally"
} catch {
    Write-Log "LOAD ERROR: window failed to open" -ErrorRecord $_
    [System.Windows.Forms.MessageBox]::Show("A critical error occurred. Details were written to Log.txt", "$script:AppName v$script:AppVersion Error", "OK", "Error")
}
