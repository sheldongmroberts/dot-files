#Requires AutoHotkey v2.0
#SingleInstance Off
; End-to-end test through the real keyboard hook. Starts KeyAgent on a test config, then types
; into its own Edit control with SendEvent at SendLevel 1 (which KeyAgent's hotkeys react to like
; real key presses) and checks the text that arrives. Takes about 5 seconds; don't type meanwhile.
; Run:  AutoHotkey64.exe /ErrorStdOut tests\E2E.ahk [--exe dist\KeyAgent.exe]

#Include ..\lib\Json.ahk
#Include ..\lib\Keys.ahk
#Include ..\lib\Actions.ahk
#Include ..\lib\Config.ahk

global OutDir := A_ScriptDir "\out", Passed := 0, Failed := [], KeyAgentPid := 0
DirCreate(OutDir)
global LogFile := OutDir "\E2E.log"
try FileDelete(LogFile)
Say(text) {
    try FileAppend(text, "*", "UTF-8")
    FileAppend(text, LogFile, "UTF-8")
}
OnError((e, *) => (Say("ERROR: " e.Message " " e.Extra "`n  at line " e.Line "`n"), Cleanup(), ExitApp(2)))
SetTimer(() => (Say("ERROR: timed out`n"), Cleanup(), ExitApp(3)), -40000)

; ---- test config
K(key, mods*) {
    a := Map("type", "key", "key", key)
    if mods.Length
        a["mods"] := mods
    return a
}
km := Config.NewKeymap("E2E", "E2E")
base := km["layers"]["base"], modL := km["layers"]["mod"]
base["RAlt"] := Map("type", "layer", "layer", "mod", "mode", "holdAndDoubleTapToggle")
base["f"] := Map("type", "key", "key", "f", "secondary", "LShift")
base["q"] := K("z")
modL["j"] := K("Left"), modL["l"] := K("Right"), modL["u"] := K("Home"), modL["o"] := K("End")
modL["e"] := K("x", "LShift")
modL["m"] := Map("type", "macro", "macro", "hi")
cfg := Config.Normalize(Map("keymaps", [km], "macros", [Map("name", "hi", "steps", [Map("type", "text", "text", "Hi!")])]))
cfg["settings"]["pauseWhenUhkConnected"] := false
cfgPath := OutDir "\e2e-config.json"
Config.Save(cfg, cfgPath)

; ---- start KeyAgent and the test window
; A KeyAgent that's already running would remap the test's keys too, so don't run alongside it.
DetectHiddenWindows true
if ProcessExist("KeyAgent.exe") || WinExist("\KeyAgent.ahk ahk_class AutoHotkey") {
    Say("SKIPPED: KeyAgent is running. Exit it (tray icon > Exit) and run the test again.`n")
    ExitApp(4)
}
DetectHiddenWindows false
exe := A_Args.Length >= 2 && A_Args[1] = "--exe" ? A_Args[2] : ""     ; test KeyAgent.exe instead
if exe {
    cmd := Format('"{}" --config "{}" --test', exe, cfgPath)
} else {
    ; Started through a wrapper so AutoHotkey's single-instance rule (keyed on the script file)
    ; can never close a KeyAgent.ahk you start yourself.
    wrapper := OutDir "\KeyAgentUnderTest.ahk"
    try FileDelete(wrapper)
    FileAppend("#Include " A_ScriptDir "\..\KeyAgent.ahk`n", wrapper, "UTF-8")
    cmd := Format('"{}" "{}" --config "{}" --test', A_AhkPath, wrapper, cfgPath)
}
Say("testing " (exe ? exe : "KeyAgent.ahk") "`n")
Run(cmd, , , &KeyAgentPid)
Sleep 1500
g := Gui("+AlwaysOnTop", "KeyAgent E2E test")
ed := g.Add("Edit", "w420 h60")
g.Show("x20 y20")
WinActivate(g.Hwnd)
WinWaitActive(g.Hwnd, , 3)
ed.Focus()
Sleep 300

SetKeyDelay 12, 8           ; ~ fast human typing: 12 ms between events, keys held 8 ms
SendLevel 1

Expect(cond, name) {
    global Passed
    if cond
        Passed++
    else
        Failed.Push(name)
}

Step(keys, expected, name, settle := 150) {
    global Passed
    if !WinActive(g.Hwnd) {                      ; something else took the focus: get it back
        try who := WinGetTitle("A") " / " WinGetProcessName("A") " / " WinGetClass("A")
        catch
            who := "(no active window)"
        Say("  note: focus was on [" who "] before `"" name "`"`n")
        WinActivate(g.Hwnd), WinWaitActive(g.Hwnd, , 2), ed.Focus()
        SendMessage(0xB1, -1, -1, ed)               ; EM_SETSEL: caret back to the end
    }
    ; {Blind}: the driver must not release modifiers itself (a normal Send releases any Shift it
    ; sees held - including one KeyAgent is holding - which a real keyboard never does)
    if keys != ""
        SendEvent("{Blind}" keys)
    Sleep settle
    actual := ed.Value
    lost := !WinActive(g.Hwnd) ? " (the test window lost the focus during this step: "
        . WinGetTitle("A") " / " WinGetProcessName("A") ")" : ""
    if actual == expected
        Passed++
    else
        Failed.Push(name lost "`n      expected: [" expected "]`n      actual:   [" actual "]")
}

Step("{SC01E}{SC030}{SC02E}", "abc", "plain keys pass through")
Step("{RAlt down}{SC024}{SC024}{RAlt up}{SC02D down}{SC02D up}", "axbc", "Mod+J twice = Left, Left")
Step("{RAlt down}{SC018}{RAlt up}{SC015}", "axbcy", "Mod+O = End")
Step("{SC010}", "axbcyz", "Q remapped to Z")
Step("{SC021}", "axbcyzf", "tap/hold key tapped")
Step("{SC021 down}{SC024 down}{SC024 up}{SC021 up}", "axbcyzfJ", "tap/hold key held = Shift")
Step("{RAlt down}{SC012}{RAlt up}", "axbcyzfJX", "Mod+E = Shift+X")
Step("{RAlt}{RAlt}", "axbcyzfJX", "double-tap RAlt")
DetectHiddenWindows false
Expect(WinExist("ahk_pid " KeyAgentPid " ahk_class AutoHotkeyGUI", "Mod layer locked"), "indicator shows `"Mod layer locked`"")
Expect(WinActive("A") = g.Hwnd, "indicator didn't take the focus")
Step("{SC016}{SC002}{RAlt}{SC024}", "1jaxbcyzfJX", "locked Mod: Home, then tap RAlt unlocks")
Step("{RAlt down}{SC032}{RAlt up}", "1jHi!axbcyzfJX", "Mod+M plays a macro", 500)
SetKeyDelay 1, 1            ; very fast rolls
Step("{RAlt down}{SC026}{RAlt up}{SC02D}{SC02E}", "1jHi!axcxbcyzfJX", "fast roll: Mod+L then x c keep order")
Step("{SC024 down}{SC024 down}{RAlt down}{SC024 down}{SC024 up}{RAlt up}", "1jHi!axcjjjxbcyzfJX", "key held from before the layer stays itself")
SetKeyDelay 12, 8
Step("{End}{Shift down}{RAlt down}{SC024}{SC024}{RAlt up}{Shift up}{SC02D}", "1jHi!axcjjjxbcyzfx", "physical Shift + Mod+J selects (Shift+Left)")

SendLevel 0
Cleanup()
report := Format("{} passed, {} failed`n", Passed, Failed.Length)
for f in Failed
    report .= "  FAIL " f "`n"
Say(report)
ExitApp(Failed.Length ? 1 : 0)

Cleanup() {
    SendLevel 0
    Send("{Blind}{RAlt up}{LShift up}{Shift up}")
    if KeyAgentPid {
        DetectHiddenWindows true
        if WinExist("ahk_pid " KeyAgentPid " ahk_class AutoHotkey")
            WinClose()                      ; lets KeyAgent run its OnExit (releases keys)
        if !ProcessWaitClose(KeyAgentPid, 3)
            ProcessClose(KeyAgentPid)
    }
}
