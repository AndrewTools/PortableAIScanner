Portable AI Scanner
===================

A portable Windows app that lists AI apps, browser AI features, and
local models on this PC. It does not install anything.

License: All rights reserved. You may run this app on your own PC.
You may not modify or republish it.

Current version: 1.6.2


Files needed to run
-------------------
Keep these in the same folder:

  - PortableAIScanner.exe      Double-click this to start the app
  - AI_Scanner.ps1             Windows 10 and Windows 11 scanner
  - AI_Scanner_Legacy.ps1      Windows 7 scanner

Version.txt and README.txt are documentation only.

  - The exe will not start on Windows 10/11 without AI_Scanner.ps1.
  - The exe will not start on Windows 7 without AI_Scanner_Legacy.ps1.
  - Keep both scripts next to the exe.


Requirements
------------
  - Windows 7, Windows 10, or Windows 11 only
  - No installer
  - Windows PowerShell (already part of Windows)


Which file runs
---------------
Double-click PortableAIScanner.exe. It picks the script:

  - Windows 10 or 11     AI_Scanner.ps1
  - Windows 7            AI_Scanner_Legacy.ps1
  - Any other Windows    Not compatible. Neither script starts.

Windows 8 and 8.1 are not supported.

Windows 7 uses a smaller scan list:

  - It looks for local runtimes and model files (Ollama, LM Studio,
    GPT4All, Jan, llama.cpp, and similar).
  - It does not look for Copilot or browser on-device AI.


How to run
----------
  1. Put the exe and both .ps1 files in one folder.
  2. Double-click PortableAIScanner.exe.
  3. Click Scan.
  4. After the scan, Detected and Export list appear at the top.
  5. Click Detected to hide gray rows.
  6. Click Export list to save visible rows as a CSV file.
  7. Click Rescan to scan again. Click Cancel during a scan to stop it.

While the scan is walking model folders, the bar shows how many
names and GGUF files were indexed.

Check for update sits on the title row (blue, same color as Scan).

  - It reads GitHub AndrewTools/PortableAIScanner releases/latest.
  - Nothing is downloaded.
  - The button shows Checking..., then Found: vX.Y.Z (Latest),
    Found: vX.Y.Z (Old), or Found: vX.Y.Z (New).
  - If it says (New), click the button again to open that release page.

A second launch tells you to close the open window first.

Windows may warn that the exe is unsigned. That is SmartScreen.
Choose More info, then Run anyway if you trust this copy.

Do not move the exe and leave the .ps1 files behind.

If you do not have the exe:

  - Windows 10/11: right-click AI_Scanner.ps1 > Run with PowerShell
  - Windows 7:     right-click AI_Scanner_Legacy.ps1 > Run with PowerShell

If you start the .ps1 from an already-open command prompt, that
prompt stays open after the window closes.


What you will see
-----------------
The window shows the Windows version and the app version.

Installed is Yes if that product is on disk. For browsers, Installed
is Yes whenever Chrome, Edge, Firefox, Opera, Brave, or Comet is
installed, even if that build has no AI.

Status words:

  - Installed           On disk; no separate AI switch
  - Activated           AI switch on
  - Deactivated         AI switch off (or Block / policy off)
  - No AI Features      Browser is installed; this version has no AI
  - Unknown             AI exists; on/off could not be read
  - Model loaded        A local model is in memory
  - Not Installed       Product not found
  - None Found on Disk  Model files / non-browser rows only

Running is Yes if that browser or app process is open. AI on or off
does not change the Running column.

Color:

  - Red     Running is Yes and Status is Activated or Model loaded
  - Blue    Status is Activated or Model loaded, process closed
  - Green   Installed, Deactivated, or Unknown
  - Gray    Not Installed, None Found on Disk, or No AI Features

Browser row names:

  - Google Chrome + Gemini
  - Microsoft Edge + Copilot
  - Mozilla Firefox + AI
  - Opera + Aria
  - Brave + Leo
  - Perplexity Comet + AI

Firefox Details still split Labs chatbot, tab AI, and link previews
by version. Old Firefox is Installed Yes with Status No AI Features.

Official Gemini Desktop is the Google app (Update GUID and
%LOCALAPPDATA%\Google\Gemini). Third-party wrappers are ignored.
Google has not published the live exe folder.

Other apps also include NVIDIA ChatRTX and NVIDIA G-Assist.
NVIDIA App alone is not G-Assist.

After a scan:

  - Detected hides gray rows.
  - Export list saves the visible rows as CSV.
  - Name and How to Disable column widths stay put on Rescan.


How to disable
--------------
How to disable appears when Installed is Yes and Status is
Activated or Model loaded.

It is blank when Status is Deactivated or No AI Features.

  - Windows 10/11: Settings and the mouse. No file editing.
  - Windows 7:     Control Panel > Programs and Features > Uninstall.


Log file
--------
Each run creates or overwrites Log.txt in the same folder.

  - It records startup and what was found.
  - You can delete it.
  - Do not upload Log.txt. It can include scan paths and results.



What it does not do
-------------------
It does not download or install anything. Check for update only reads
this project's GitHub releases list and can open that GitHub page in
your browser. It does not need Administrator. It does not add startup
tasks. Local service checks only contact 127.0.0.1 on this PC.

A scan reads browser settings files and Notepad settings to see if AI
is on. It does not change those files. Do not upload Log.txt.

What this is not
----------------
  - It is not an antivirus.
  - It does not find every possible AI.
  - It does not turn AI off for you. It only reports what it can see
    and how you can turn that item off yourself.

This app does not download or run other programs. Check for update
only reads the GitHub release tag for this project and can open that
project's GitHub release page in your browser. It does not need
Administrator and does not add startup tasks. Local model checks stay
on this PC (127.0.0.1). It writes Log.txt and, if you export, a CSV
you choose.

It reads (does not change) some app settings so it can see if AI is
on: browser files such as Preferences, Local State, and Firefox
prefs.js, plus Notepad settings.dat. Windows may warn that the exe
is unsigned.

See Version.txt for what changed in each release.
