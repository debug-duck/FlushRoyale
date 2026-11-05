@echo off
REM FLUSH ROYALE  -  build the Android debug APK and push it to a connected phone.
REM Usage:  build_android.bat            build + install + launch on the connected phone
REM         build_android.bat --no-push  build only (build\flush-royale-debug.apk)
REM Needs: Android SDK (build-tools 34.0.0, platform android-34), JDK 17+, USB debugging on the phone.
REM Overrides: ANDROID_SDK_ROOT, JAVA_HOME, GODOT_EXE (console build of 4.4.1), DEBUG_KEYSTORE.
setlocal EnableExtensions
cd /d "%~dp0"

REM ---- first use: this .bat on its own (no project next to it) -> clone the repo into C:\temp\FlushRoyale, run from there ----
if exist "%~dp0project.godot" goto :have_project
set "REPO=https://github.com/debug-duck/FlushRoyale.git"
set "BRANCH=claude/flush-royale-godot-poc-nnxf41"
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
set "GTPL=4.4.1.stable"
set "GDIR=%~dp0build\godot"
set "GCON=%GDIR%\Godot_v%GVER%_win64_console.exe"
set "APK=build\flush-royale-debug.apk"
set "PKG=com.wrongbutton.flushroyale"
if defined GODOT_EXE set "GCON=%GODOT_EXE%"

REM ---- Android SDK ----
if not defined ANDROID_SDK_ROOT if defined ANDROID_HOME set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
if not defined ANDROID_SDK_ROOT set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
if not exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" (echo Android SDK not found at %ANDROID_SDK_ROOT% & goto :fail)

REM ---- JDK 17+ (Godot 4.4 will not work with Java 8) ----
if not defined JAVA_HOME (
  for /d %%D in ("%ProgramFiles%\Amazon Corretto\jdk*" "%ProgramFiles%\Java\jdk*" "%ProgramFiles%\Eclipse Adoptium\jdk*" "%ProgramFiles%\Android\Android Studio\jbr") do if exist "%%~D\bin\keytool.exe" set "JAVA_HOME=%%~D"
)
if not defined JAVA_HOME (echo JDK 17+ not found. Set JAVA_HOME. & goto :fail)

REM ---- debug keystore (generated once, never committed) ----
if not defined DEBUG_KEYSTORE set "DEBUG_KEYSTORE=%USERPROFILE%\.android\debug.keystore"
if not exist "%DEBUG_KEYSTORE%" (
  if not exist "%USERPROFILE%\.android" mkdir "%USERPROFILE%\.android"
  "%JAVA_HOME%\bin\keytool" -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "%DEBUG_KEYSTORE%" -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12 || goto :fail
)
set "GODOT_ANDROID_KEYSTORE_DEBUG_PATH=%DEBUG_KEYSTORE%"
set "GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey"
set "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android"

REM ---- Godot 4.4.1 editor + export templates ----
if not exist "%GCON%" (
  echo Godot %GVER% not found - downloading to build\godot ...
  if not exist "%GDIR%" mkdir "%GDIR%"
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; $z='%GDIR%\g.zip'; Invoke-WebRequest 'https://github.com/godotengine/godot-builds/releases/download/%GVER%/Godot_v%GVER%_win64.exe.zip' -OutFile $z; Expand-Archive $z '%GDIR%' -Force; Remove-Item $z" || goto :fail
)
set "TDIR=%APPDATA%\Godot\export_templates\%GTPL%"
if not exist "%TDIR%\android_debug.apk" (
  echo Downloading export templates ^(~1 GB, once^) ...
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; $t='%GDIR%\t.zip'; Invoke-WebRequest 'https://github.com/godotengine/godot-builds/releases/download/%GVER%/Godot_v%GVER%_export_templates.tpz' -OutFile $t; $x='%GDIR%\tpl'; Expand-Archive $t $x -Force; New-Item -ItemType Directory -Force '%TDIR%' | Out-Null; Copy-Item ($x+'\templates\*') '%TDIR%' -Recurse -Force; Remove-Item $t,$x -Recurse -Force" || goto :fail
)

REM ---- editor settings for 4.4 (only written if missing; your other Godot versions are untouched) ----
set "ES=%APPDATA%\Godot\editor_settings-4.4.tres"
if not exist "%ES%" (
  if not exist "%APPDATA%\Godot" mkdir "%APPDATA%\Godot"
  powershell -NoProfile -Command "$q=[char]34; $s=$env:ANDROID_SDK_ROOT.Replace([char]92,[char]47); $j=$env:JAVA_HOME.Replace([char]92,[char]47); $k=$env:DEBUG_KEYSTORE.Replace([char]92,[char]47); $l=@(('[gd_resource type='+$q+'EditorSettings'+$q+' format=3]'),'','[resource]',('export/android/android_sdk_path = '+$q+$s+$q),('export/android/java_sdk_path = '+$q+$j+$q),('export/android/debug_keystore = '+$q+$k+$q),('export/android/debug_keystore_user = '+$q+'androiddebugkey'+$q),('export/android/debug_keystore_pass = '+$q+'android'+$q)); Set-Content -Encoding ascii '%ES%' $l"
)

REM ---- build ----
if not exist build mkdir build
echo Importing assets ...
"%GCON%" --headless --path . --import
"%GCON%" --headless --path . --import || goto :fail
if exist "%APK%" del "%APK%"
echo Exporting APK ...
"%GCON%" --headless --path . --export-debug "Android" "%APK%"
if not exist "%APK%" (echo APK export failed. & goto :fail)
echo Built %APK%

if /i "%~1"=="--no-push" goto :done

REM ---- push to phone ----
set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
"%ADB%" start-server >nul 2>&1
"%ADB%" devices | findstr /r /c:"	device$" >nul
if errorlevel 1 (
  echo.
  echo No phone detected. Enable Developer options + USB debugging, plug in, accept the prompt on the phone,
  echo then run:  "%ADB%" install -r "%APK%"
  goto :fail
)
echo Installing on phone ...
"%ADB%" install -r "%APK%" || goto :fail
"%ADB%" shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1 >nul 2>&1
echo Installed and launched.

:done
exit /b 0

:fail
echo.
echo Build/push did not complete.
pause
exit /b 1
