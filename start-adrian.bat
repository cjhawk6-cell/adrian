@echo off
REM Double-click this to run Adrian over http://localhost instead of opening
REM the HTML file directly. Fixes Chrome repeatedly re-asking for microphone
REM permission. Requires no installs — just Windows' built-in PowerShell.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve-adrian.ps1"
