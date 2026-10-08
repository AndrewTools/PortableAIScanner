Portable AI Scanner
===================

Lists AI apps, browser AI, and local models on this PC.
It does not install anything or turn anything off.

License: All rights reserved. You may run this app on your own PC.
You may not modify or republish it.

You run it at your own risk. Windows may warn that the app is
unsigned.

Current version: 1.7.5 Build 0179


What to put in the folder
-------------------------
Keep these in the same folder:

  - PortableAIScanner.exe      Double-click this to start
  - AI_Scanner.ps1             Windows 10 and 11
  - AI_Scanner_Legacy.ps1      Windows 7

Version.txt and README.txt are optional.

Windows 7, 10, and 11 only. Windows Server and Windows 8 / 8.1
are not supported.

If you do not have the exe:

  - Windows 10/11: right-click AI_Scanner.ps1 > Run with PowerShell
  - Windows 7:     right-click AI_Scanner_Legacy.ps1 > Run with PowerShell


How to scan
-----------
  1. Double-click PortableAIScanner.exe.
     If a window is already open, that start brings it forward.
  2. Click Scan.
  3. After the scan, Detected hides gray rows. Export list saves
     the visible list as a CSV file.
  4. Click Rescan to scan again. Click Cancel to stop a scan.

How to disable is blank when that AI is already off, unread,
or not there to turn off.

On Windows 10/11, Check for update looks up the latest version.
It does not download files.


Colors
------
  - Red     The app is open and AI is on, or a local model is loaded
  - Blue    AI is on or a model is loaded, and the app is closed
  - Green   AI is off or unread
  - Gray    Not installed, or this browser version has no AI


Log
---
Each run writes Log.txt in the same folder. You can delete it.
Do not upload it.


What it will not do
-------------------
  - It is not an antivirus and it does not find every AI.
  - It does not change settings or send files off this PC.
  - It does not need Administrator.

See Version.txt for what changed in each release.
