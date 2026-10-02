#Requires AutoHotkey v2.0
; Builds default-config.json (what KeyAgent starts with on first run) from a UHK Agent config:
; the UHK's default keymap, its macros and its mouse/timing settings, with Mod on Right Alt and
; Mouse on Caps Lock.
;   AutoHotkey64.exe tools\MakeDefaultConfig.ahk [path to UHK Agent config .json]

#Include ..\lib\Json.ahk
#Include ..\lib\Keys.ahk
#Include ..\lib\Actions.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Macros.ahk
#Include ..\lib\UhkImport.ahk

Keys.Init()
found := UhkImport.FindConfigs()
src := A_Args.Length ? A_Args[1] : found.Length ? found[1] : ""
if !src {
    MsgBox("No UHK Agent configuration found in " A_AppData "\uhk-agent.", "KeyAgent", "Icon!")
    ExitApp(1)
}
uhk := UhkImport.Load(src)
default := ""
for km in UhkImport.ListKeymaps(uhk)
    if km.isDefault || default = ""
        default := km.abbreviation
res := UhkImport.Convert(uhk, {keymaps: [default], triggers: UhkImport.DefaultTriggers(), macros: true, settings: true})
cfg := Config.Normalize(Map("keymaps", res.keymaps, "macros", res.macros, "settings", res.settings, "defaultKeymap", default))
; Left Alt also right-clicks on the Mouse layer (Caps Lock + Left Alt), like the
; capsLockMouseModifier.ahk script this replaces. Right Alt does too, from the UHK's thumb Mod key.
cfg["keymaps"][1]["layers"]["mouse"]["LAlt"] := Map("type", "mouse", "action", "rightClick")
out := A_ScriptDir "\..\default-config.json"
Config.Save(cfg, out)
notes := ""
for line in res.log
    notes .= "`n  " line
try FileAppend("Wrote " out " from " src notes "`n", "*", "UTF-8")
ExitApp(0)
