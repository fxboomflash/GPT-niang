@echo off
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "%~dp0scripts\Settings.ps1"
