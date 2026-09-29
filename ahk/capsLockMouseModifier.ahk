#Requires AutoHotkey v2.0
#SingleInstance Force

; CapsLock is only a modifier now, so it never toggles on
SetCapsLockState "AlwaysOff"

; While CapsLock is held: Space = left click, LAlt = right click
#HotIf GetKeyState("CapsLock", "P")
*Space::    Press("LButton")
*Space Up:: Release("LButton")
*LAlt::    Press("RButton")
*LAlt Up:: Release("RButton")
#HotIf

; If CapsLock is released first, don't leave a mouse button stuck down
*CapsLock Up:: {
    Release("LButton")
    Release("RButton")
}

Press(btn) {
    if !GetKeyState(btn)  ; ignore key auto-repeat while held
        Send "{Blind}{" btn " down}"
}

Release(btn) {
    if GetKeyState(btn)
        Send "{Blind}{" btn " up}"
}
