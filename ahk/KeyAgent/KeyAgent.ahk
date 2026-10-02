#Requires AutoHotkey v2.0
#SingleInstance Force
; KeyAgent - UHK Agent-style key remapping for normal keyboards: layers (Mod, Fn, Mouse, ...),
; tap/hold keys, keymaps, mouse keys and macros, edited in a GUI and stored in config.json.
;
; Command line: KeyAgent.ahk [--config <file>] [--editor] [--test] [--nohook]
;   (or KeyAgent.exe with the same options, when compiled with tools\BuildExe.ahk)
;   --editor   open the editor on start
;   --test     no UHK auto-pause / key watchdog (used by the end-to-end tests)
;   --nohook   don't hook the keyboard (look at the editor without remapping anything)

;@Ahk2Exe-SetMainIcon KeyAgent.ico
;@Ahk2Exe-SetName KeyAgent
;@Ahk2Exe-SetDescription KeyAgent - UHK Agent-style keyboard remapping
;@Ahk2Exe-SetVersion 1.0.0

Persistent
InstallKeybdHook
SetKeyDelay -1, -1
SetMouseDelay -1
A_MaxHotkeysPerInterval := 1000
A_HotkeyInterval := 1000

#Include %A_LineFile%\..\lib\Json.ahk
#Include %A_LineFile%\..\lib\Keys.ahk
#Include %A_LineFile%\..\lib\Actions.ahk
#Include %A_LineFile%\..\lib\Config.ahk
#Include %A_LineFile%\..\lib\Engine.ahk
#Include %A_LineFile%\..\lib\MouseKeys.ahk
#Include %A_LineFile%\..\lib\Macros.ahk
#Include %A_LineFile%\..\lib\Osd.ahk
#Include %A_LineFile%\..\lib\UhkDetect.ahk
#Include %A_LineFile%\..\lib\UhkImport.ahk
#Include %A_LineFile%\..\lib\Editor.ahk
#Include %A_LineFile%\..\lib\Dialogs.ahk

if !IsSet(KeyAgentEmbedded)        ; tests include this file and drive App themselves
    App.Main()

class App {
    static Name := "KeyAgent"
    static cfg := ""
    ; folder of KeyAgent.ahk, or of KeyAgent.exe when compiled
    static Dir := A_IsCompiled ? A_ScriptDir : RegExReplace(A_LineFile, "\\[^\\]*$")
    static configPath := ""
    static paused := Map()          ; reason ("user", "uhk", "capture") -> true
    static testMode := false
    static noHook := false
    static firstRun := false
    static keymapMenu := ""
    static _uhkCheckFn := ""

    static Main() {
        openEditor := false
        i := 0
        while ++i <= A_Args.Length {
            switch A_Args[i] {
                case "--config": this.configPath := A_Args[++i]
                case "--editor": openEditor := true
                case "--test": this.testMode := true
                case "--nohook": this.noHook := true
            }
        }
        if this.configPath = ""
            this.configPath := this._DefaultConfigPath()
        ProcessSetPriority("High")
        Keys.Init()
        this.cfg := this._LoadConfig()
        Engine.watchdog := !this.testMode
        Engine.OnChange := ObjBindMethod(this, "_OnEngineChange")
        if !this.noHook
            Engine.Install()
        this.Apply(this.cfg)
        this._BuildTray()
        OnExit(ObjBindMethod(this, "_OnExit"))
        this._uhkCheckFn := ObjBindMethod(this, "CheckUhk")
        if !this.testMode {
            OnMessage(0x0219, ObjBindMethod(this, "_OnDeviceChange"))     ; WM_DEVICECHANGE
            SetTimer(this._uhkCheckFn, 15000)
            this.CheckUhk(true)
        }
        if openEditor
            Editor.Open()
        else if this.firstRun
            TrayTip("KeyAgent is running. Double-click the tray icon to open the editor.", "KeyAgent")
    }

    ; config.json lives next to KeyAgent, so the folder (or the exe) can be carried around. If
    ; that folder isn't writable (e.g. KeyAgent.exe in Program Files) it goes to %APPDATA%\KeyAgent.
    static _DefaultConfigPath() {
        beside := this.Dir "\config.json", roaming := A_AppData "\KeyAgent\config.json"
        if FileExist(beside)
            return beside
        if FileExist(roaming)
            return roaming
        if this._Writable(this.Dir)
            return beside
        DirCreate(A_AppData "\KeyAgent")
        return roaming
    }

    static _Writable(dir) {
        probe := dir "\.keyagent-write-test"
        try {
            FileAppend("", probe)
            FileDelete(probe)
            return true
        }
        return false
    }

    ; The first-run configuration: default-config.json next to KeyAgent if there is one,
    ; otherwise the copy built into KeyAgent.exe.
    static _DefaultConfig() {
        path := this.Dir "\default-config.json"
        if FileExist(path)
            return Config.Load(path)
        if A_IsCompiled {
            tmp := A_Temp "\KeyAgent-default-config.json"
            try {
                FileInstall("default-config.json", tmp, 1)
                cfg := Config.Load(tmp)
                FileDelete(tmp)
                return cfg
            }
        }
        return Config.Minimal()
    }

    static _LoadConfig() {
        if !FileExist(this.configPath) {
            this.firstRun := true
            cfg := this._DefaultConfig()
            try Config.Save(cfg, this.configPath)
            return cfg
        }
        try
            return Config.Load(this.configPath)
        catch as e {
            try FileCopy(this.configPath, this.configPath ".broken", true)
            MsgBox("KeyAgent couldn't read " this.configPath ":`n`n" e.Message
                "`n`nIt starts with a basic layout for now. A copy of your file was saved as config.json.broken.",
                "KeyAgent", "Icon!")
            return Config.Minimal()
        }
    }

    ; Makes cfg the active configuration.
    static Apply(cfg) {
        this.cfg := cfg
        MouseKeys.Configure(cfg["settings"])
        Macros.Configure(cfg["macros"])
        Engine.Load(cfg)
        ; Caps Lock is a layer key: if it was left on, there'd be no way to turn it off
        if Engine.keymap["layers"]["base"].Has("CapsLock") && GetKeyState("CapsLock", "T")
            SetCapsLockState("Off")
        if this.keymapMenu
            this._UpdateTray()
    }

    static SaveAndApply(cfg) {
        Config.Save(cfg, this.configPath)
        this.Apply(Config.Clone(cfg))
        this.CheckUhk()
    }

    static ReloadConfig(*) {
        try
            cfg := Config.Load(this.configPath)
        catch as e {
            MsgBox("Couldn't reload " this.configPath ":`n`n" e.Message, "KeyAgent", "Icon!")
            return
        }
        this.Apply(cfg)
        Editor.OnConfigReloaded()
        TrayTip("Configuration reloaded.", "KeyAgent")
    }

    ; Remapping is paused while any reason holds: the user paused it, a UHK is connected,
    ; or the editor is capturing a key press.
    static SetPaused(reason, on) {
        if on
            this.paused[reason] := true
        else if this.paused.Has(reason)
            this.paused.Delete(reason)
        want := this.paused.Count > 0
        if want != A_IsSuspended {
            Engine.ReleaseAll()
            Suspend(want)
            Osd.Hide()
        }
        if this.keymapMenu
            this._UpdateTray()
    }

    static TogglePause(*) => this.SetPaused("user", !this.paused.Has("user"))

    static CheckUhk(quiet := false) {
        if this.testMode
            return
        s := this.cfg["settings"]
        connected := s["pauseWhenUhkConnected"] && UhkDetect.Connected(s["uhkDongleCounts"])
        if connected = this.paused.Has("uhk")
            return
        this.SetPaused("uhk", connected)
        if !quiet || connected
            TrayTip(connected ? "UHK connected: KeyAgent is paused while it's plugged in."
                : "UHK disconnected: KeyAgent is remapping again.", "KeyAgent")
    }

    static _OnDeviceChange(wParam, *) {
        if wParam = 7                                   ; DBT_DEVNODES_CHANGED
            SetTimer(this._uhkCheckFn, -1500)           ; let the device settle first
    }

    ; ---- tray ----

    static _BuildTray() {
        tm := A_TrayMenu
        tm.Delete()
        tm.Add("Open editor", (*) => Editor.Open())
        tm.Default := "Open editor"
        tm.Add()
        this.keymapMenu := Menu()
        tm.Add("Keymap", this.keymapMenu)
        tm.Add("Pause remapping", ObjBindMethod(this, "TogglePause"))
        tm.Add()
        tm.Add("Reload config.json", ObjBindMethod(this, "ReloadConfig"))
        tm.Add("Open config folder", (*) => Run(RegExReplace(this.configPath, "\\[^\\]*$")))
        tm.Add("Start with Windows", ObjBindMethod(this, "ToggleStartup"))
        tm.Add()
        tm.Add("Exit", (*) => ExitApp())
        this._UpdateTray()
    }

    static _UpdateTray() {
        m := this.keymapMenu
        m.Delete()
        for km in this.cfg["keymaps"] {
            label := km["name"] " (" km["abbreviation"] ")"
            m.Add(label, ObjBindMethod(this, "_PickKeymap", km["abbreviation"]))
            if Engine.keymap && km["abbreviation"] = Engine.keymap["abbreviation"]
                m.Check(label)
        }
        tm := A_TrayMenu
        this.paused.Has("user") ? tm.Check("Pause remapping") : tm.Uncheck("Pause remapping")
        FileExist(this.StartupLink) ? tm.Check("Start with Windows") : tm.Uncheck("Start with Windows")
        this._SetTrayIcon()
        this._UpdateTip()
    }

    ; KeyAgent's keyboard icon (so it stands out from other AutoHotkey scripts), or AutoHotkey's
    ; pause icon while paused.
    static _SetTrayIcon() {
        try {
            if this.paused.Count
                TraySetIcon(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, 4, true)
            else if A_IsCompiled
                TraySetIcon(A_ScriptFullPath, 1, true)
            else if FileExist(this.Dir "\KeyAgent.ico")
                TraySetIcon(this.Dir "\KeyAgent.ico", 1, true)
            else
                TraySetIcon("DDORes.dll", 31, true)      ; a keyboard icon that comes with Windows
        }
    }

    static _UpdateTip() {
        tip := "KeyAgent - " (Engine.keymap ? Engine.keymap["name"] : "")
        layer := Engine.Layer()
        if layer != "base"
            tip .= " - " Actions.LayerNames[layer] (Engine.toggled = layer ? " (locked)" : "")
        if this.paused.Count
            tip .= "`nPaused" (this.paused.Has("uhk") ? " (UHK connected)" : "")
        A_IconTip := tip
    }

    static _PickKeymap(abbr, *) {
        Engine.SwitchKeymap(abbr)
        this._UpdateTray()
    }

    static _OnEngineChange(kind) {
        s := this.cfg["settings"]
        layer := Engine.Layer()
        if kind = "keymap" {
            if s["osdLocked"]
                Osd.Show("Keymap: " Engine.keymap["name"], 1500)
            this._UpdateTray()
            return
        }
        if layer != "base" && Engine.toggled = layer && s["osdLocked"]
            Osd.Show(Actions.LayerNames[layer] " layer locked")
        else if layer != "base" && s["osdHeld"]
            Osd.Show(Actions.LayerNames[layer] " layer")
        else
            Osd.Hide()
        this._UpdateTip()
    }

    ; ---- start with Windows ----

    static StartupLink => A_Startup "\KeyAgent.lnk"

    ; The script version starts with AutoHotkey's UI Access build when it's installed, so
    ; remapping also works in windows running as administrator.
    static ToggleStartup(*) {
        this.SetStartup(!FileExist(this.StartupLink))
    }

    static SetStartup(on) {
        if !on {
            try FileDelete(this.StartupLink)
        } else if A_IsCompiled {
            FileCreateShortcut(A_ScriptFullPath, this.StartupLink, this.Dir, , "KeyAgent keyboard remapping")
        } else {
            exe := A_AhkPath
            uia := RegExReplace(A_AhkPath, "i)\.exe$", "_UIA.exe")
            if FileExist(uia)
                exe := uia
            FileCreateShortcut(exe, this.StartupLink, this.Dir, '"' this.Dir "\KeyAgent.ahk" '"',
                "KeyAgent keyboard remapping")
        }
        if this.keymapMenu
            this._UpdateTray()
    }

    static _OnExit(*) {
        Engine.ReleaseAll()
    }
}
