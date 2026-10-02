#Requires AutoHotkey v2.0
; Startup test: runs App.Main() as a first run (config file doesn't exist yet, keyboard hook on)
; and checks the config was created, the tray is set up, and the UHK auto-pause matches
; UhkDetect. Exits after a couple of seconds.
; Run:  AutoHotkey64.exe /ErrorStdOut tests\Startup.ahk

global KeyAgentEmbedded := true
#Include ..\KeyAgent.ahk

global OutDir := A_ScriptDir "\out"
DirCreate(OutDir)
cfgPath := OutDir "\startup-config.json"
try FileDelete(cfgPath)
A_Args.Push("--config", cfgPath)
App.Main()
Sleep 2000

results := []
Check(cond, name) => results.Push((cond ? "ok    " : "FAIL  ") name)
Check(FileExist(cfgPath), "first run created the config file")
Check(App.firstRun, "first run detected")
Check(Config.Load(cfgPath)["keymaps"][1]["layers"]["base"].Has("RAlt"), "config came from default-config.json")
Check(Engine._hk.Count = 2 * Keys.List.Length, "hotkeys registered for every key (" Engine._hk.Count ")")
uhk := UhkDetect.Connected()
Check(A_IsSuspended = uhk, "paused exactly when a UHK is connected (UHK connected: " uhk ", paused: " A_IsSuspended ")")
Check(InStr(A_IconTip, "KeyAgent - QWERTY for PC"), "tray tip: " StrReplace(A_IconTip, "`n", " | "))
Check(A_TrayMenu.Default = "Open editor", "tray default item")
App.SetPaused("user", true)
Check(A_IsSuspended = 1, "user pause suspends")
App.SetPaused("user", false)
Check(A_IsSuspended = uhk, "user unpause restores the UHK state")

; where config.json goes when no --config is given
Check(App._Writable(A_Temp), "temp folder counts as writable")
Check(!App._Writable(A_ProgramFiles), "Program Files counts as not writable (not running as admin)")
savedDir := App.Dir
App.Dir := OutDir
Check(App._DefaultConfigPath() = OutDir "\config.json", "config goes next to KeyAgent when that folder is writable")
roamingDir := A_AppData "\KeyAgent", hadRoaming := DirExist(roamingDir)
App.Dir := A_ProgramFiles "\AutoHotkey"
Check(App._DefaultConfigPath() = roamingDir "\config.json", "config goes to %APPDATA%\KeyAgent when it isn't")
if !hadRoaming
    try DirDelete(roamingDir)                   ; leave the profile as it was
App.Dir := savedDir

out := ""
for r in results
    out .= r "`n"
try FileAppend(out, "*", "UTF-8")
FileAppend(out, OutDir "\Startup.log", "UTF-8")
ExitApp
