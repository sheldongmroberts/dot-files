#Requires AutoHotkey v2.0
#SingleInstance Force

; Keep CapsLock from ever toggling on
SetCapsLockState "AlwaysOff"

; CapsLock acts as the left mouse button (press/hold/release)
CapsLock::LButton

; Optional: Shift+CapsLock still toggles real Caps Lock
capsOn := false
+CapsLock:: {
    global capsOn
    capsOn := !capsOn
    SetCapsLockState capsOn ? "AlwaysOn" : "AlwaysOff"
}
