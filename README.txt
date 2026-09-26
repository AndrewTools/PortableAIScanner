Portable AI Scanner
===================

A portable Windows app that lists AI apps, browser AI features, and
local models on this PC. It does not install anything.

License: All rights reserved. You may run this app on your own PC.
You may not modify or republish it.

You run PortableAIScanner.exe (and the scripts) at your own risk.
This project does not promise that the files are safe, complete,
or right for your PC. Windows may warn that the app is unsigned.

Current version: 1.6.6


What it is
----------
It scans this computer and shows what it found: installed or not,
AI on or off, and whether that app is open. It also tells you how
to turn an item off yourself. It does not turn anything off for you.


What to put in the folder
-------------------------
Keep these in the same folder:

  - PortableAIScanner.exe      Double-click this to start the app
  - AI_Scanner.ps1             Windows 10 and Windows 11
  - AI_Scanner_Legacy.ps1      Windows 7

Version.txt and README.txt are optional.

  - Double-click the exe. Do not move it away from the two scripts.
  - Windows 10 and 11 use AI_Scanner.ps1.
  - Windows 7 uses AI_Scanner_Legacy.ps1 and a shorter list
    (local apps and model files only).
  - Windows 8 and 8.1 are not supported.

Windows may warn that the app is unsigned. That is normal for a
portable exe with no certificate.

If you do not have the exe:

  - Windows 10/11: right-click AI_Scanner.ps1 > Run with PowerShell
  - Windows 7:     right-click AI_Scanner_Legacy.ps1 > Run with PowerShell


How to scan
-----------
  1. Put the exe and both .ps1 files in one folder.
  2. Double-click PortableAIScanner.exe.
  3. Click Scan.
  4. After the scan, Detected and Export list appear.
  5. Click Detected to hide gray rows.
  6. Click Export list to save the visible rows as a CSV file.
     That is the list on screen, including section headers.
     Detected-on exports only the non-gray rows.
  7. Click Rescan to scan again. Click Cancel to stop a scan.

Rescan turns Detected off and shows every row again. Click
Detected after the new scan if you want to hide gray rows.

A second launch asks you to close the window that is already open.

Check for update only looks up this project's latest release.
Nothing is installed. If it says Download, click again to open
that page in your browser.

GPU use is shown next to Check for update. It does not change
any scan row.


What the columns and colors mean
--------------------------------
The window shows the Windows version and the app version.

Installed is Yes if that product is on this PC.

Status words:

  - Installed           On disk; no separate AI switch
  - Activated           AI switch on
  - Copilot / Microsoft 365 Copilot: Activated means the app is
    installed and not turned off by policy. It is not a live chat.
  - Notepad / Paint: Activated also if Windows text and image
    generation is Allow and the app has no off switch stored.
  - Deactivated         AI switch off
  - No AI Features      Browser is installed; this version has no AI
  - Unknown             AI exists; on or off could not be read
  - Model loaded        A local model is in memory
  - Not Installed       Product not found
  - None Found on Disk  Model files only; no app

Running is Yes if that app or browser is open.

Color:

  - Red     Running is Yes and Status is Activated or Model loaded
  - Blue    Status is Activated or Model loaded, process closed
  - Green   Installed, Deactivated, or Unknown
  - Gray    Not Installed, None Found on Disk, or No AI Features

Browser rows:

  - Google Chrome + Gemini
  - Microsoft Edge + Copilot
  - Mozilla Firefox + AI
  - Opera + Aria
  - Brave + Leo
  - Perplexity Comet + AI

List groups, top to bottom:

  - Major Apps
  - Browser-based
  - Microsoft Apps
  - Other Apps
  - Local Models


How to disable and the log
--------------------------
How to disable appears when Installed is Yes and Status is
Activated, Model loaded, Installed, or Unknown.

It is blank when Status is Deactivated, No AI Features,
Not Installed, or None Found on Disk.

  - Windows 10/11: use Settings and the mouse. No file editing.
  - Windows 7:     Control Panel > Programs and Features > Uninstall.

Each run creates or overwrites Log.txt in the same folder.
You can delete it. Do not upload Log.txt.


What it will not do
-------------------
  - It is not an antivirus.
  - It does not find every possible AI.
  - It does not turn AI off for you.
  - It does not download or install anything.
  - It does not need Administrator and does not add startup tasks.
  - It does not send your files off this PC.
  - If a local AI app is running, the scan may ask that app which
    models are loaded. The answer stays on this PC.
  - It only reads settings. It does not change them.


Privacy and safety
------------------
You run PortableAIScanner.exe (and the scripts) at your own risk.
This project does not promise that the files are safe, complete,
or right for your PC.

Windows may warn that the app is unsigned. That only means there
is no publisher certificate. It is not a clean bill of health.

Check for update only asks GitHub for the latest version number.
It does not download the new files.

A scan reads installed apps, open programs, and AI settings. It
does not change those settings.

If a local AI app is already running, the scan may ask it which
models are loaded. That stays on this PC.

If Notepad's AI switch cannot be read the usual way, Windows may
show an antivirus notice for a short extra check. That check
only reads a copy of the Notepad setting.

Log.txt can list folder paths. You can delete it. Do not upload it.

The app does not need Administrator and does not add startup tasks.

See Version.txt for what changed in each release.
