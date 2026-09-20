Portable AI Scanner
===================

A portable Windows app that lists AI apps, browser AI features, and
local models on this PC. It does not install anything.

License: All rights reserved. You may run this app on your own PC.
You may not modify or republish it. See LICENSE.txt.

Current version: 1.5.8


Files needed to run
-------------------
Keep these in the same folder:

  PortableAIScanner.exe     Double-click this to start the app
  AI_Scanner.ps1            Windows 10 and Windows 11 scanner
  AI_Scanner_Legacy.ps1     Windows 7 scanner

Version.txt, README.txt, and LICENSE.txt are documentation only.

The exe will not start on Windows 10/11 without AI_Scanner.ps1.
It will not start on Windows 7 without AI_Scanner_Legacy.ps1.
Keep both scripts next to the exe.


Requirements
------------
Windows 7, Windows 10, or Windows 11 only.
No installer.
Windows PowerShell is already part of Windows.


Which file runs
---------------
Double-click PortableAIScanner.exe. It picks the script:

  Windows 10 or 11     AI_Scanner.ps1
  Windows 7            AI_Scanner_Legacy.ps1
  Any other Windows    Not compatible. Neither script starts.

Windows 8 and 8.1 are not supported.

Windows 7 uses a smaller checker list.
Windows 7 only looks for local runtimes and model files
(Ollama, LM Studio, GPT4All, Jan, llama.cpp, and similar).
It does not look for Copilot or browser on-device AI.
Windows 7 uses a smaller checker list.


How to run
----------
1. Put the exe and both .ps1 files in one folder.
2. Double-click PortableAIScanner.exe.
3. Click Scan.
4. After the scan, Detected and Export list appear at the top.
5. Click Detected to hide gray rows.
6. Click Export list to save visible rows as a CSV file.
7. Click Rescan to scan again. Click Cancel during a scan to stop it.

A second launch tells you to close the open window first.

Windows may warn that the exe is unsigned. That is SmartScreen.
Choose More info, then Run anyway if you trust this copy.

Do not move the exe and leave the .ps1 files behind.

If you do not have the exe:

  Windows 10/11: right-click AI_Scanner.ps1 > Run with PowerShell
  Windows 7:     right-click AI_Scanner_Legacy.ps1 > Run with PowerShell

If you start the .ps1 from an already-open command prompt, that
prompt stays open after the window closes.


What you will see
-----------------
The window shows the Windows version and the app version.

Status words:

  Installed                    On disk, exe closed
  Unknown                      Browser has AI, on/off setting cannot be read
  App running                  Desktop exe open with no model, or
                               browser AI on and that browser is open
  Model loaded                 A local model is in memory
  Activated                    Browser AI setting on, browser closed
  Deactivated                  Browser or optional app AI is present and off
  Not Installed                Product not found
  None Found on Disk           Browser is there but that version has no AI

Desktop and other apps (ChatGPT, Claude, Gemini Desktop, Copilot,
Ollama, LM Studio, Cherry Studio, Claude Code, Cursor, and similar):

  Gray   Not Installed
  Green  Installed - on disk, exe not open. Running = No
  Blue   App running - exe open, no local model. Running = Yes
  Red    Model loaded - local model in memory. Running = Yes

Browsers (Chrome Gemini, Edge, Firefox, Brave, Opera):

  Gray   No AI in that version, or browser not installed
  Green  Installed, Deactivated, or Unknown. Running = No
  Blue   Activated - AI setting on, browser closed. Running = No
  Red    App running - AI on and that browser is open. Running = Yes

If Firefox prefs cannot be read, or Brave/Opera AI cannot be proven
on or off, Status is Unknown (Green). Detected still shows the row.

Opening Chrome with Gemini off stays Green or Gray.
Every browser uses Deactivated when AI is known off. Edge with the
AI setting on but no weights.bin is Activated (Blue if Edge is closed).

Official Gemini Desktop is the Google app (Update GUID and
%LOCALAPPDATA%\Google\Gemini). Third-party Gemini Desktop
wrappers are ignored. Google has not published the live exe folder.

Local model files (Qwen, Llama, DeepSeek, Gemma, and similar):

  Gray   No files on disk
  Green  Files on disk, nothing loaded. Running = No
  Red    That family is loaded in Ollama, LM Studio, or similar.
         Running = Yes
  Blue   Not used for model-file rows

Detected hides gray rows. Export list saves the visible rows as CSV.
Name and How to Disable widths are kept after the first scan.
During a scan the bar shows Indexed N model names when that walk finishes.
After the first scan, Name and How to Disable column widths stay put
on Rescan. While model folders are scanned, the bar shows how many
names and GGUF files were indexed.
Name and How to Disable column widths stay the same after the first scan.
While it indexes local models the status bar shows how many names and
GGUF files it found.


How to disable
--------------
How to disable appears when Installed is Yes.

  Windows 10/11: Settings and the mouse. No file editing.
  Windows 7:     Control Panel > Programs and Features > Uninstall.


Log file
--------
Each run creates or overwrites Log.txt in the same folder.
It records startup and what was found. You can delete it.
Do not upload Log.txt. It can include your PC name and scan results.


What this is not
----------------
It is not an antivirus.
It does not find every possible AI.
It does not turn AI off for you. It only reports what it can see
and how you can turn that item off yourself.

See Version.txt for what changed in each release.
