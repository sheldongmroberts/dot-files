#Requires AutoHotkey v2.0
; GUI smoke test: opens the editor on a copy of default-config.json without hooking the keyboard,
; drives it through its own methods, checks the results, and saves window images to tests\out.
; Run:  AutoHotkey64.exe /ErrorStdOut tests\GuiSmoke.ahk

global KeyAgentEmbedded := true
#Include ..\KeyAgent.ahk

global OutDir := A_ScriptDir "\out", Passed := 0, Failed := []
DirCreate(OutDir)
global LogFile := OutDir "\GuiSmoke.log"
try FileDelete(LogFile)
Say(text) {
    try FileAppend(text, "*", "UTF-8")
    FileAppend(text, LogFile, "UTF-8")
}
OnError((e, *) => (Say("ERROR: " e.Message " " e.Extra "`n  at " e.File ":" e.Line "`n" e.Stack "`n"), ExitApp(2)))
Eq(actual, expected, name) {
    global Passed
    if actual == expected
        Passed++
    else
        Failed.Push(name "`n      expected: " expected "`n      actual:   " actual)
}

; Saves an image of one window (PrintWindow, so only that window is captured).
Snap(hwnd, name) {
    static gdiplus := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")   ; keep it loaded between calls
    WinGetPos(, , &w, &h, hwnd)
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", sdc, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("PrintWindow", "Ptr", hwnd, "Ptr", mdc, "UInt", 2)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
    si := Buffer(24, 0), NumPut("UInt", 1, si)
    token := 0, bmp := 0
    DllCall("gdiplus\GdiplusStartup", "UPtr*", &token, "Ptr", si, "Ptr", 0)
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &bmp)
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "Str", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
    DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bmp, "Str", OutDir "\" name ".png", "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
    DllCall("gdiplus\GdiplusShutdown", "UPtr", token)
    DllCall("DeleteObject", "Ptr", hbm), DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
}

; Snaps a modal dialog shortly after it opens, then closes it.
SnapDialogLater(title, name) {
    check() {                            ; polls: a blocking wait would stall the dialog being built
        if !(hwnd := WinExist(title))
            return
        SetTimer(check, 0)
        Sleep 400
        Snap(hwnd, name)
        WinClose(title)
    }
    SetTimer(check, 100)
}

; ---- set up the app without hooks, on a scratch copy of the default config
Keys.Init()
App.testMode := true, App.noHook := true
App.configPath := OutDir "\config.json"
FileCopy(A_ScriptDir "\..\default-config.json", App.configPath, true)
App.cfg := Config.Load(App.configPath)
Engine.watchdog := false
App.Apply(App.cfg)
App._BuildTray()

Editor.Open()
Sleep 500
Snap(Editor.gui.Hwnd, "1-base")
t := Editor.tiles
Eq(t["CapsLock"].state, " Caps|Mouse|layer|" Editor.TileBg, "CapsLock tile on base")
Eq(t["a"].state, "|A|native|" Editor.TileBg, "plain tile on base")

; Mod layer, select J
Editor.c.layers[2].Value := 1
Editor._OnLayerPick("mod")
Editor._Select("j")
Sleep 300
Snap(Editor.gui.Hwnd, "2-mod-j")
Eq(t["j"].state, " J|←|key|" Editor.SelBg, "J tile on mod, selected")
Eq(t["w"].state, " W|^PgUp|shortcut|" Editor.TileBg, "W tile on mod")
Eq(t["Space"].state, "|Space|transparent|" Editor.TileBg, "unmapped Space on mod (no duplicate legend)")
Eq(Editor.c.desc.Value, "Sends Left Arrow.", "J description")
Eq(Editor.c.key.Text, "Left Arrow", "key dropdown shows Left Arrow")
Eq(Editor.c.key.Visible, 1, "key fields visible")
Eq(Editor.c.layerPick.Visible, 0, "layer fields hidden")

; change J to Ctrl+Shift+Left via the fields, then make it a tap/hold key
Editor.c.mods[1].Value := 1, Editor.c.mods[2].Value := 1
Editor._OnFieldChange()
Eq(Json.Dump(Config.Keymap(Editor.cfg, "QWR")["layers"]["mod"]["j"]), '{"key": "Left", "mods": ["LCtrl", "LShift"], "type": "key"}', "J edited")
Eq(Editor.dirty, true, "dirty after edit")
Eq(t["j"].state, " J|^+←|shortcut|" Editor.SelBg, "J tile updated")

; Mouse layer, select I; then change I to "Switch layer"
Editor._OnLayerPick("mouse")
Editor._Select("i")
Eq(Editor.c.mouse.Text, "Move pointer up", "mouse dropdown")
Editor.c.type.Choose(3)
Editor._OnTypeChange()
Eq(Json.Dump(Config.Keymap(Editor.cfg, "QWR")["layers"]["mouse"]["i"]), '{"layer": "mod", "mode": "holdAndDoubleTapToggle", "type": "layer"}', "I changed to a layer key")
Eq(Editor.c.mode.Text, "Hold, or double-tap to lock", "mode dropdown")
Snap(Editor.gui.Hwnd, "3-mouse-i-layer")
; back to not mapped
Editor.c.type.Choose(1)
Editor._OnTypeChange()
Eq(Config.Keymap(Editor.cfg, "QWR")["layers"]["mouse"].Has("i"), false, "I unmapped again")

; key capture (keys are sent at SendLevel 1 while the capture window waits)
CaptureWith(keys, combos) {
    SetTimer(() => (SendLevel(1), SendEvent(keys), SendLevel(0)), -700)
    return KeyCapture.Capture(Editor.gui, "Test capture", combos)
}
r := CaptureWith("{LCtrl down}{SC014}{LCtrl up}", true)
Eq(r ? r.key "+" Actions._Join(r.mods, "+") : "none", "t+LCtrl", "capture Ctrl+T")
r := CaptureWith("{LShift down}{LShift up}", true)
Eq(r ? r.key : "none", "LShift", "capture a lone Shift")
r := CaptureWith("{SC024}", false)
Eq(r ? r.key : "none", "j", "find key J")
Eq(App.paused.Has("capture"), false, "remapping resumed after capture")

; keymap management
Editor._AddKeymap(Config.NewKeymap("Test keymap", "TST"))
Eq(Editor.c.keymap.Text, "Test keymap (TST)", "new keymap selected")
Editor.abbr := "QWR", Editor._RefreshKeymaps(), Editor._RefreshTiles()

; dialogs
MacroEditor.Open(Editor.gui)
MacroEditor.c.list.Choose(1), MacroEditor._OnPick()
MacroEditor.c.steps.Modify(1, "Select Focus")
MacroEditor._OnStepPick(MacroEditor.c.steps, 1, true)
Sleep 300
Snap(MacroEditor.gui.Hwnd, "4-macros")
Eq(MacroEditor.c.key.Text, "L", "macro step key")
Eq(MacroEditor.c.mods[1].Value, 1, "macro step Ctrl")
MacroEditor.Close()

SnapDialogLater("KeyAgent - Settings", "5-settings")
SettingsDialog.Open(Editor.gui)
SnapDialogLater("KeyAgent - Import from UHK Agent", "6-import")
ImportDialog.Open(Editor.gui)

; save writes the file and applies it
Editor._Save()
saved := Config.Load(App.configPath)
Eq(Json.Dump(Config.Keymap(saved, "QWR")["layers"]["mod"]["j"]), '{"key": "Left", "mods": ["LCtrl", "LShift"], "type": "key"}', "saved to disk")
Eq(Config.Keymap(saved, "TST") != "", true, "new keymap saved")
Eq(Json.Dump(Config.Keymap(Engine.cfg, "QWR")["layers"]["mod"]["j"]), '{"key": "Left", "mods": ["LCtrl", "LShift"], "type": "key"}', "engine uses saved config")
Eq(Editor.dirty, false, "clean after save")

Editor._OnClose()
Eq(Editor.IsOpen(), false, "editor closed")

report := Format("{} passed, {} failed`n", Passed, Failed.Length)
for f in Failed
    report .= "  FAIL " f "`n"
Say(report)
ExitApp(Failed.Length ? 1 : 0)
