#Requires AutoHotkey v2.0
#SingleInstance Force

; The Copilot key sends LWin + LShift + F23.
; Blocking F23 with any modifiers stops the combo, and AutoHotkey
; also masks the Win key so the Start menu doesn't open.
*F23::return
*F23 Up::return
