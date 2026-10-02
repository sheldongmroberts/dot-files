#Requires AutoHotkey v2.0
; Builds dist\KeyAgent.exe: KeyAgent as one file that runs without AutoHotkey installed. The exe
; carries default-config.json inside it and creates config.json next to itself on first run.
; Double-click this file after changing KeyAgent, or run:
;   AutoHotkey64.exe tools\BuildExe.ahk [--quiet]

quiet := A_Args.Length && A_Args[1] = "--quiet"
root := RegExReplace(A_LineFile, "\\tools\\[^\\]*$")

Report(msg, ok) {
    try FileAppend(msg "`n", "*", "UTF-8")
    if !quiet
        MsgBox(msg, "Build KeyAgent.exe", ok ? "Iconi" : "Icon!")
    ExitApp(ok ? 0 : 1)
}

; Ahk2Exe lives in AutoHotkey's install folder; the 64-bit v2 interpreter is the base the exe is built on.
installDir := ""
try installDir := RegRead("HKLM\SOFTWARE\AutoHotkey", "InstallDir")
if installDir = ""
    installDir := RegExReplace(A_AhkPath, "\\[^\\]+\\[^\\]+$")
compiler := installDir "\Compiler\Ahk2Exe.exe"
base := RegExReplace(A_AhkPath, "[^\\]+$") "AutoHotkey64.exe"
if !FileExist(compiler)
    Report("Ahk2Exe (AutoHotkey's compiler) isn't installed.`n`nOpen AutoHotkey Dash, choose Compile to install it, then run this again.", false)
if !FileExist(base)
    Report("Couldn't find the 64-bit AutoHotkey v2 interpreter (" base ").", false)

DirCreate(root "\dist")
out := root "\dist\KeyAgent.exe"
if FileExist(out) {
    try FileDelete(out)
    catch
        Report("dist\KeyAgent.exe is in use. Exit it (tray icon > Exit) and try again.", false)
}

; /compress 0: compressed AutoHotkey exes are far more likely to be flagged by antivirus.
logFile := A_Temp "\KeyAgent-build.log"
cmd := Format('"{}" /in "{}" /out "{}" /base "{}" /compress 0 /silent verbose', compiler, root "\KeyAgent.ahk", out, base)
code := RunWait(A_ComSpec ' /c "' cmd ' > "' logFile '" 2>&1"', root, "Hide")
details := FileExist(logFile) ? Trim(FileRead(logFile), " `r`n") : ""
try FileDelete(logFile)
if code || !FileExist(out)
    Report("Ahk2Exe failed (exit code " code ").`n`n" details, false)
Report(Format("Built {} ({} KB).`n`nShare just this one file: it runs without AutoHotkey installed and creates config.json next to itself on first run.",
    out, Round(FileGetSize(out) / 1024)), true)
