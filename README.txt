Portable AI Scanner
===================

A portable Windows app that lists AI apps, browser AI features, and
local models on this PC. It does not install anything.

License: All rights reserved. You may run this app on your own PC.
You may not modify or republish it. See LICENSE.

This release is three files. Keep them in the same folder.

  PortableAIScanner.exe   Double-click this to start the app
  AI_Scanner.ps1          The scanner. The exe will not run without
                          this file next to it
  Version.txt             Version history

Current version: 1.4.0

Requirements
------------
Windows 10 or Windows 11.
No installer.
No extra downloads if these files are together.

How to run
----------
1. Put PortableAIScanner.exe, AI_Scanner.ps1, and Version.txt
   in one folder.
2. Double-click PortableAIScanner.exe.
3. Click Scan for Installed AI.

Windows may warn that the exe is unsigned. That is SmartScreen.
You can choose More info, then Run anyway if you trust this copy.

Do not move the exe to another folder and leave AI_Scanner.ps1
behind. They must stay together.

What you will see
-----------------
The window title shows the Windows version and the app version.

After a scan:

  Green  Installed (including AI that ships with a browser or app
         but is turned off)
  Blue   Activated
  Red    An on-device model is loaded in memory
  Gray   Not installed, or no on-device model found

Running = Yes only when a local model is actually in memory.
A browser being open does not count as running.

How to disable appears only when Installed is Yes. Those steps
use Settings and the mouse. They do not ask you to edit files.

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

License
-------
All rights reserved. You may run this app on your own PC.
You may not modify or republish it. See LICENSE.
