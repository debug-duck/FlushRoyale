@echo off
REM FLUSH ROYALE  -  run the game on PC (mouse = touch). Keys: F/Space flush, R restart, F1 collision debug.
REM Uses Godot 4.4.1 (the pinned version). Set GODOT_EXE to use your own copy; otherwise it is
REM downloaded once into build\godot (git-ignored).
setlocal EnableExtensions
cd /d "%~dp0"

REM ---- first use: this .bat on its own (no project next to it) -> clone the repo into C:\temp\FlushRoyale, run from there ----
if exist "%~dp0project.godot" goto :have_project
set "REPO=https://github.com/debug-duck/FlushRoyale.git"
set "BRANCH=main"
set "TARGET=C:\temp\FlushRoyale"
where git >nul 2>&1 || (echo Git is needed: https://git-scm.com/download/win & goto :fail)
if not exist "%TARGET%\project.godot" (
  echo Cloning Flush Royale into %TARGET% ...
  if not exist "C:\temp" mkdir "C:\temp"
  git clone -b %BRANCH% %REPO% "%TARGET%" || goto :fail
)
call "%TARGET%\%~nx0" %*
exit /b %errorlevel%
:have_project

REM ---- update from GitHub first (fast-forward only; never overwrites local work) ----
where git >nul 2>&1 && (
  echo Updating from GitHub ...
  git pull --ff-only || echo WARNING: could not update ^(local changes, no network, or diverged branch^) - continuing with the current files.
)

set "GVER=4.4.1-stable"
set "GDIR=%~dp0build\godot"
set "GEXE=%GDIR%\Godot_v%GVER%_win64.exe"
set "GCON=%GDIR%\Godot_v%GVER%_win64_console.exe"

if defined GODOT_EXE (
  set "GEXE=%GODOT_EXE%"
  set "GCON=%GODOT_EXE%"
)

if not exist "%GEXE%" (
  echo Godot %GVER% not found - downloading to build\godot ...
  if not exist "%GDIR%" mkdir "%GDIR%"
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; $z='%GDIR%\g.zip'; Invoke-WebRequest 'https://github.com/godotengine/godot-builds/releases/download/%GVER%/Godot_v%GVER%_win64.exe.zip' -OutFile $z; Expand-Archive $z '%GDIR%' -Force; Remove-Item $z" || goto :fail
)

REM Always re-import: after a pull, new scripts (class_name) and assets are only known to Godot once imported.
if not exist ".godot" (
  echo First run: importing assets ^(can take a minute^) ...
  "%GCON%" --headless --path . --import
)
echo Refreshing project cache ...
"%GCON%" --headless --path . --import

echo Starting game ...
"%GEXE%" --path .
exit /b %errorlevel%

:fail
echo.
echo Could not download Godot. Download Godot %GVER% manually and set GODOT_EXE to its path.
pause
exit /b 1
