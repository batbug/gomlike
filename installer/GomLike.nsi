; GomLike-Setup: ставит плеер в выбранную папку, делает ярлыки и ассоциации файлов.
; Установка только для текущего пользователя, права администратора не нужны.

; 32-битный установщик: в NSIS для Windows нет 64-битных заготовок, а ставит он
; всё равно 64-битный mpv (пишет только в HKCU и LOCALAPPDATA, перенаправления нет)
Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"
!include "TextFunc.nsh"

!define APP "GomLike"
!define PROGID "GomLike.File"
!define REG "Software\GomLike"
!define UNREG "Software\Microsoft\Windows\CurrentVersion\Uninstall\GomLike"
!define VIDEO "mkv mp4 avi mov wmv flv webm m4v mpg mpeg ts m2ts mts vob 3gp ogv divx rm rmvb asf f4v"
!define AUDIO "mp3 flac m4a aac ogg opus wav wma ape"
!define PLAYLIST "m3u m3u8 pls"

Name "${APP}"
Caption "Установка ${APP}"
; -DOFFLINE: mpv лежит внутри установщика (installer\mpv, готовит tools/build.ps1),
; без него установщик скачивает mpv во время установки
!ifdef TEST
OutFile "test-setup.exe"
!else ifdef OFFLINE
OutFile "GomLike-Setup-Offline.exe"
!else
OutFile "GomLike-Setup.exe"
!endif
InstallDir "$LOCALAPPDATA\Programs\GomLike"
InstallDirRegKey HKCU "${REG}" "InstallDir"
BrandingText "${APP}"

!define MUI_ICON "gomlike.ico"
!define MUI_UNICON "gomlike.ico"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_NODESC

!define MUI_WELCOMEPAGE_TITLE "Установка ${APP}"
!ifdef OFFLINE
!define MUI_WELCOMEPAGE_TEXT "Видеоплеер на движке mpv: без рекламы, без обновлений, с классической панелью управления.$\r$\n$\r$\nВсё нужное уже внутри установщика, интернет не нужен. Плеер в интернет тоже не ходит.$\r$\n$\r$\nНажми «Далее»."
!else
!define MUI_WELCOMEPAGE_TEXT "Видеоплеер на движке mpv: без рекламы, без обновлений, с классической панелью управления.$\r$\n$\r$\nВо время установки нужен интернет: установщик скачает свежий mpv (около 35 МБ). Потом плеер в интернет не ходит.$\r$\n$\r$\nНажми «Далее»."
!endif
!define MUI_DIRECTORYPAGE_TEXT_TOP "Выбери папку для плеера. Подойдёт любая папка, куда у тебя есть права на запись (Program Files не подойдёт: плеер хранит там настройки и позиции просмотра)."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Запустить ${APP}"
!define MUI_FINISHPAGE_RUN_FUNCTION RunPlayer

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

; ---------- ассоциации ----------
!macro AssocList LIST
    Push "${LIST} "
    Call AssocExts
!macroend

Var ext
Var rest

Function AssocExts
    Exch $rest
    ${Do}
        StrCpy $ext ""
        ${Do}
            StrCpy $0 $rest 1
            StrCpy $rest $rest "" 1
            ${If} $0 == " "
            ${OrIf} $0 == ""
                ${ExitDo}
            ${EndIf}
            StrCpy $ext "$ext$0"
        ${Loop}
        ${If} $ext != ""
            WriteRegStr HKCU "Software\Classes\.$ext\OpenWithProgids" "${PROGID}" ""
            WriteRegStr HKCU "${REG}\Capabilities\FileAssociations" ".$ext" "${PROGID}"
            ; делаем GomLike плеером для этого формата: сбрасываем прежний выбор
            ; (например, GOM), тогда Windows открывает файл программой ниже
            WriteRegStr HKCU "Software\Classes\.$ext" "" "${PROGID}"
            DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.$ext\UserChoice"
            DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.$ext\UserChoiceLatest"
        ${EndIf}
    ${LoopUntil} $rest == ""
    Pop $rest
FunctionEnd

Function un.UnassocExts
    Exch $rest
    ${Do}
        StrCpy $ext ""
        ${Do}
            StrCpy $0 $rest 1
            StrCpy $rest $rest "" 1
            ${If} $0 == " "
            ${OrIf} $0 == ""
                ${ExitDo}
            ${EndIf}
            StrCpy $ext "$ext$0"
        ${Loop}
        ${If} $ext != ""
            DeleteRegValue HKCU "Software\Classes\.$ext\OpenWithProgids" "${PROGID}"
            ReadRegStr $1 HKCU "Software\Classes\.$ext" ""
            ${If} $1 == "${PROGID}"
                DeleteRegValue HKCU "Software\Classes\.$ext" ""
            ${EndIf}
        ${EndIf}
    ${LoopUntil} $rest == ""
    Pop $rest
FunctionEnd

; ---------- файлы mpv ----------
; удаляет файлы mpv по списку gomlike-files.txt, который записал установщик (чужие файлы
; в папке не трогаем); при установке поверх старой версии убирает прежние файлы,
; например mpv.exe из версий, где плеер ещё не назывался GomLike.exe
!macro RemoveMpvFilesFn UN
Function ${UN}RemoveMpvFiles
    ClearErrors
    FileOpen $1 "$INSTDIR\gomlike-files.txt" r
    ${IfNot} ${Errors}
        ${Do}
            ClearErrors
            FileRead $1 $2
            ${If} ${Errors}
                ${ExitDo}
            ${EndIf}
            ${Do}
                StrCpy $3 $2 1 -1
                ${If} $3 == "$\r"
                ${OrIf} $3 == "$\n"
                    StrCpy $2 $2 -1
                ${Else}
                    ${ExitDo}
                ${EndIf}
            ${Loop}
            ${If} $2 != ""
                RMDir /r "$INSTDIR\$2"
                Delete "$INSTDIR\$2"
            ${EndIf}
        ${Loop}
        FileClose $1
    ${EndIf}
    Delete "$INSTDIR\gomlike-files.txt"
FunctionEnd
!macroend
!insertmacro RemoveMpvFilesFn ""
!insertmacro RemoveMpvFilesFn "un."

; ---------- секции ----------
Section "${APP} (обязательно)" SecMain
    SectionIn RO
    SetOutPath "$INSTDIR"
    File "gomlike.ico"
    File /r "payload\portable_config"
    File "payload\README.txt"
    ; лицензии: GomLike (MIT) и mpv (GPLv2+); откуда взят mpv — в mpv-source.txt
    File "/oname=LICENSE.txt" "payload\LICENSE"
    File /r "licenses"
    ; прежние файлы mpv (при установке поверх старой версии)
    Call RemoveMpvFiles

!ifdef OFFLINE
    ; mpv и список его файлов (gomlike-files.txt) для удаления
    File /r "mpv\*.*"
!else
    AddSize 105000
    InitPluginsDir
    File "/oname=$PLUGINSDIR\getmpv.ps1" "getmpv.ps1"
    retry:
    DetailPrint "Скачиваю mpv с GitHub, это займёт минуту..."
!ifdef TEST
    FileOpen $1 "$INSTDIR\GomLike.exe" w
    FileClose $1
    CreateDirectory "$INSTDIR\doc"
    FileOpen $1 "$INSTDIR\doc\manual.pdf" w
    FileClose $1
    FileOpen $1 "$INSTDIR\gomlike-files.txt" w
    FileWrite $1 "GomLike.exe$\r$\ndoc$\r$\n"
    FileClose $1
    StrCpy $0 "0"
!else
    nsExec::ExecToLog 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\getmpv.ps1" -Dest "$INSTDIR" -Icon "$INSTDIR\gomlike.ico"'
    Pop $0
!endif
    ${If} $0 != "0"
        MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Не получилось скачать или распаковать mpv.$\r$\n$\r$\nПроверь интернет. Если плеер сейчас открыт, закрой его. Потом нажми «Повтор»." IDRETRY retry
        Abort "Установка прервана: mpv не скачан."
    ${EndIf}
!endif

    WriteUninstaller "$INSTDIR\uninstall.exe"
    CreateDirectory "$SMPROGRAMS\${APP}"
    CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\GomLike.exe"
    CreateShortcut "$SMPROGRAMS\${APP}\Uninstall ${APP}.lnk" "$INSTDIR\uninstall.exe"

    WriteRegStr HKCU "${REG}" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "${UNREG}" "DisplayName" "${APP}"
    WriteRegStr HKCU "${UNREG}" "DisplayIcon" "$INSTDIR\gomlike.ico"
    WriteRegStr HKCU "${UNREG}" "Publisher" "${APP}"
    WriteRegStr HKCU "${UNREG}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNREG}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKCU "${UNREG}" "NoModify" 1
    WriteRegDWORD HKCU "${UNREG}" "NoRepair" 1
    WriteRegDWORD HKCU "${UNREG}" "EstimatedSize" 110000
SectionEnd

Section "Ярлык на рабочем столе" SecDesktop
    CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\GomLike.exe"
SectionEnd

SectionGroup /e "Сделать ${APP} плеером по умолчанию" SecAssoc
    Section "для видео (mkv, mp4, avi и другие)" SecVideo
        Call RegisterProgId
        !insertmacro AssocList "${VIDEO}"
    SectionEnd
    Section /o "для музыки (mp3, flac и другие)" SecAudio
        Call RegisterProgId
        !insertmacro AssocList "${AUDIO}"
    SectionEnd
    Section "для плейлистов (m3u, m3u8, pls)" SecPlaylist
        Call RegisterProgId
        !insertmacro AssocList "${PLAYLIST}"
    SectionEnd
SectionGroupEnd

Function RegisterProgId
    WriteRegStr HKCU "Software\Classes\${PROGID}" "" "Медиафайл (${APP})"
    WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" '"$INSTDIR\gomlike.ico",0'
    WriteRegStr HKCU "Software\Classes\${PROGID}\shell" "" "open"
    WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open" "FriendlyAppName" "${APP}"
    WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\GomLike.exe" -- "%1"'
    WriteRegStr HKCU "${REG}\Capabilities" "ApplicationName" "${APP}"
    WriteRegStr HKCU "${REG}\Capabilities" "ApplicationDescription" "Видеоплеер без рекламы"
    WriteRegStr HKCU "${REG}\Capabilities" "ApplicationIcon" '"$INSTDIR\gomlike.ico",0'
    WriteRegStr HKCU "Software\RegisteredApplications" "${APP}" "${REG}\Capabilities"
FunctionEnd

Function RunPlayer
    ; установщик сейчас закроется, и Windows оставила бы окно плеера позади других;
    ; пока мы ещё на переднем плане, разрешаем плееру выйти вперёд
    System::Call 'user32::AllowSetForegroundWindow(i -1)'
    ExecShell "" "$INSTDIR\GomLike.exe" "" SW_SHOWNORMAL
    ; только что скачанный GomLike.exe может запускаться долго (антивирус проверяет его
    ; при первом запуске), и разрешение выше к тому времени пропадает. Поэтому ждём,
    ; пока появится окно плеера (класс «mpv»), и выводим его вперёд сами, пока установщик
    ; ещё на переднем плане. Ждём не дольше 15 секунд.
    StrCpy $1 0
    ${Do}
        FindWindow $0 "mpv"
        ${If} $0 <> 0
            System::Call 'user32::IsWindowVisible(p r0) i .r2'
            ${If} $2 <> 0
                System::Call 'user32::SetForegroundWindow(p r0)'
                ${ExitDo}
            ${EndIf}
        ${EndIf}
        Sleep 100
        IntOp $1 $1 + 1
    ${LoopUntil} $1 >= 150
FunctionEnd

Function .onInstSuccess
    ; обновить значки и ассоциации в Проводнике
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
FunctionEnd

; ---------- удаление ----------
Section "Uninstall"
    ; ассоциации
    Push "${VIDEO} ${AUDIO} ${PLAYLIST} "
    Call un.UnassocExts
    DeleteRegKey HKCU "Software\Classes\${PROGID}"
    DeleteRegValue HKCU "Software\RegisteredApplications" "${APP}"
    DeleteRegKey HKCU "${REG}"
    DeleteRegKey HKCU "${UNREG}"
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

    ; ярлыки
    Delete "$DESKTOP\${APP}.lnk"
    RMDir /r "$SMPROGRAMS\${APP}"

    Call un.RemoveMpvFiles
    Delete "$INSTDIR\mpv-source.txt"
    RMDir /r "$INSTDIR\portable_config"
    RMDir /r "$INSTDIR\licenses"
    Delete "$INSTDIR\gomlike.ico"
    Delete "$INSTDIR\README.txt"
    Delete "$INSTDIR\LICENSE.txt"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"
SectionEnd
