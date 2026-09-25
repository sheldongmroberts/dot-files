#Requires AutoHotkey v2.0
#SingleInstance Force
InstallKeybdHook

*LWin:: {
    Send "{Blind}{LWin down}"
    Send "{Blind}{vkE8}"
    KeyWait "LWin"
    Send "{Blind}{LWin up}"
}