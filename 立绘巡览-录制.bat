@echo off
setlocal

rem ASCII-only on purpose: a .bat with Chinese comments breaks when the console
rem code page does not match the file encoding.
rem Optional first argument overrides SECONDS, e.g. "record.bat 3" for a short test.

set "SECONDS=60"
set "FPS=60"
rem FULL=1 records the outer sweep + all 12 expression laps (ends on the memorial lap).
rem FULL=0 records only the first SECONDS seconds, starting from AT.
set "FULL=1"
set "AT=8"

rem Gallery pacing and camera. Keep these in sync with the preview bat.
set "LAP=10"
set "OUTER_LAP=3.2727"
set "OUTER_HEIGHT=10"
set "OUTER_RADIUS=15"
set "OUTER_END_RADIUS=7"
set "RADIUS=2.10"
set "HEIGHT=2.40"
set "TARGET=2.20"
set "FOV=40"

rem Render resolution. 1920x1080 records at 1080p by writing override.cfg for
rem this run only; the normal game window stays at 1600x900.
set "RENDER_W=1920"
set "RENDER_H=1080"

rem 1 = fast Movie Maker AVI (MJPEG, real-time speed).
rem 0 = lossless PNG sequence (much slower, large).
set "USE_AVI=1"

rem x264 quality: lower = better and bigger. 16 is a high quality master.
set "CRF=16"
set "PRESET=slow"
rem Keyframe distance in frames. 120 = 2 s at 60 fps.
set "GOP=120"

rem 1 = keep the intermediate frames after a successful encode.
set "KEEP_FRAMES=0"

rem 1 = loop audio\bgm.ogg to the video length, 0 = write a silent track.
set "ADD_BGM=1"
set "BGM_BITRATE=192k"

if "%FULL%"=="1" (
  set "AT=0"
  rem set /a is integer-only: 12 laps plus a rounded-up 3.27 s outer sweep.
  set /a SECONDS=%LAP%*12+4
)
if not "%~1"=="" set "SECONDS=%~1"
if "%FPS%"=="" set "FPS=60"
if "%FPS%"=="0" (
  echo FPS must be greater than 0, otherwise Movie Maker divides by zero.
  goto end
)
set /a FRAMES=%SECONDS%*%FPS%

rem ROOT keeps the trailing backslash for cmd file operations.
set "ROOT=%~dp0"
set "ROOT_FWD=%ROOT:\=/%"
set "CAPTURES=%ROOT%captures"
set "FRAMESDIR=%CAPTURES%\frames"
set "AVI=%CAPTURES%\gallery.avi"
set "MP4=%CAPTURES%\gallery.mp4"
set "FRAMES_FWD=%ROOT_FWD%captures/frames/frame.png"
set "AVI_FWD=%ROOT_FWD%captures/gallery.avi"
set "GODOT=%ROOT_FWD%tools/godot/Godot_v4.7.2-stable_win64.exe"
set "OVERRIDE=%ROOT%game\override.cfg"
set "BGM=%ROOT%audio\bgm.ogg"

if not exist "%CAPTURES%" mkdir "%CAPTURES%"

if not "%RENDER_W%"=="" if not "%RENDER_H%"=="" (
  > "%OVERRIDE%" echo [display]
  >>"%OVERRIDE%" echo.
  >>"%OVERRIDE%" echo window/size/viewport_width=%RENDER_W%
  >>"%OVERRIDE%" echo window/size/viewport_height=%RENDER_H%
  >>"%OVERRIDE%" echo window/size/window_width_override=%RENDER_W%
  >>"%OVERRIDE%" echo window/size/window_height_override=%RENDER_H%
)

echo Recording %SECONDS% seconds at %FPS% FPS (%FRAMES% frames)...
echo.
rem Movie Maker occasionally dies at startup; retry up to three times from frame 0.
set "ATTEMPT=0"
:godot_attempt
set /a ATTEMPT+=1
if exist "%AVI%" del /q "%AVI%"
if exist "%FRAMESDIR%" rmdir /s /q "%FRAMESDIR%"
if "%USE_AVI%"=="1" (
  set "MOVIEOUT=%AVI_FWD%"
  set "CHECK=%AVI%"
) else (
  mkdir "%FRAMESDIR%"
  set "TARGET=%FRAMES_FWD%"
  set "CHECK=%FRAMESDIR%\frame00000000.png"
)
"%GODOT%" --path "%ROOT_FWD%game" --script res://checks/portrait_gallery.gd --write-movie "%MOVIEOUT%" --fixed-fps %FPS% --quit-after %FRAMES% -- --fps=%FPS% --at=%AT% --lap=%LAP% --outer-lap=%OUTER_LAP% --outer-height=%OUTER_HEIGHT% --outer-radius=%OUTER_RADIUS% --outer-end-radius=%OUTER_END_RADIUS% --radius=%RADIUS% --height=%HEIGHT% --target=%TARGET% --fov=%FOV%
if not errorlevel 1 if exist "%CHECK%" goto godot_done
if %ATTEMPT% lss 3 (
  echo Attempt %ATTEMPT% failed, retrying...
  goto godot_attempt
)
if exist "%OVERRIDE%" del /q "%OVERRIDE%"
goto godot_failed
:godot_done
if exist "%OVERRIDE%" del /q "%OVERRIDE%"

set "FFMPEG=C:\ffmpeg\bin\ffmpeg.exe"
if exist "%FFMPEG%" goto have_ffmpeg
set "FFMPEG=ffmpeg"
:have_ffmpeg

echo Converting to MP4 (H.264 High, CRF %CRF%, preset %PRESET%)...
set "ENC=-c:v libx264 -preset %PRESET% -crf %CRF% -profile:v high -level:v 4.2 -pix_fmt yuv420p -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 -x264-params keyint=%GOP%:min-keyint=%GOP%:scenecut=0"
set "AUD=-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000"
set "AUDOPTS=-map 0:v:0 -map 1:a:0 -c:a aac -b:a 320k -shortest"
if "%ADD_BGM%"=="1" if exist "%BGM%" (
  echo Background music: %BGM%
  set "AUD=-stream_loop -1 -i "%BGM%""
  set "AUDOPTS=-map 0:v:0 -map 1:a:0 -c:a aac -b:a %BGM_BITRATE% -shortest"
)

if "%USE_AVI%"=="1" (
  "%FFMPEG%" -y -i "%AVI%" %AUD% -vf "scale=in_range=full:out_range=tv,format=yuv420p" %ENC% %AUDOPTS% -movflags +faststart "%MP4%"
) else (
  "%FFMPEG%" -y -framerate %FPS% -i "%FRAMESDIR%\frame%%08d.png" %AUD% -vf "format=yuv420p" %ENC% %AUDOPTS% -movflags +faststart "%MP4%"
)
if errorlevel 1 goto ffmpeg_failed
if not exist "%MP4%" goto ffmpeg_failed

if "%KEEP_FRAMES%"=="0" (
  if exist "%AVI%" del /q "%AVI%"
  if exist "%FRAMESDIR%" rmdir /s /q "%FRAMESDIR%"
)

echo.
echo Done: %MP4%
start "" "%CAPTURES%"
goto end

:godot_failed
echo.
echo Recording failed. Check free space in %CAPTURES% and that Godot can open a window.
if exist "%FRAMESDIR%" echo Partial PNG frames kept at: %FRAMESDIR%
if exist "%AVI%" echo Partial AVI kept at: %AVI%
goto end

:ffmpeg_failed
echo.
echo ffmpeg failed. Intermediate files kept in %CAPTURES%.
goto end

:end
if exist "%OVERRIDE%" del /q "%OVERRIDE%"
endlocal
