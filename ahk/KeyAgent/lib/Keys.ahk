; Keys.ahk - the physical keyboard KeyAgent remaps (full-size ANSI layout) and the catalog
; of keys an action can send.
;
; Physical keys are identified by AHK-style names ("a", "CapsLock", "Numpad7", ...). Hotkeys
; are registered by scan code wherever a key name would depend on the Windows keyboard layout
; or on NumLock, so a key always means the same physical position - the way the UHK works.

class Keys {
    static List := []           ; physical keys, in drawing order
    static ById := Map()
    static BySc := Map()
    static Out := []            ; keys an action can send: [{id, name}], in display order
    static OutById := Map()
    static Modifiers := ["LCtrl", "LShift", "LAlt", "LWin", "RCtrl", "RShift", "RAlt", "RWin"]
    static Width := 22.5        ; keyboard size in key units, for the editor drawing
    static Height := 6.25

    static Init() {
        if this.List.Length
            return
        k := ObjBindMethod(this, "_Add")
        ; k(id, legend, name, scanCode, x, y [, w, h, flags])
        ;   flags: c = character key (hotkey and output by scan code: follows the layout)
        ;          n = register the hotkey by name    m = modifier key
        k("Esc", "Esc", "Escape", 0x001, 0, 0)
        k("F1", "F1", "F1", 0x03B, 2, 0), k("F2", "F2", "F2", 0x03C, 3, 0)
        k("F3", "F3", "F3", 0x03D, 4, 0), k("F4", "F4", "F4", 0x03E, 5, 0)
        k("F5", "F5", "F5", 0x03F, 6.5, 0), k("F6", "F6", "F6", 0x040, 7.5, 0)
        k("F7", "F7", "F7", 0x041, 8.5, 0), k("F8", "F8", "F8", 0x042, 9.5, 0)
        k("F9", "F9", "F9", 0x043, 11, 0), k("F10", "F10", "F10", 0x044, 12, 0)
        k("F11", "F11", "F11", 0x057, 13, 0), k("F12", "F12", "F12", 0x058, 14, 0)
        k("PrintScreen", "PrtSc", "Print Screen", 0x137, 15.25, 0)
        k("ScrollLock", "ScrLk", "Scroll Lock", 0x046, 16.25, 0)
        k("Pause", "Pause", "Pause / Break", 0x045, 17.25, 0, 1, 1, "n")

        y := 1.25
        k("``", "``", "`` (backtick)", 0x029, 0, y, 1, 1, "c")
        for i, d in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            k(d, d, d, 0x001 + i, i, y, 1, 1, "c")
        k("-", "-", "- (minus)", 0x00C, 11, y, 1, 1, "c")
        k("=", "=", "= (equals)", 0x00D, 12, y, 1, 1, "c")
        k("Backspace", "Bksp", "Backspace", 0x00E, 13, y, 2)
        k("Insert", "Ins", "Insert", 0x152, 15.25, y)
        k("Home", "Home", "Home", 0x147, 16.25, y)
        k("PgUp", "PgUp", "Page Up", 0x149, 17.25, y)
        k("NumLock", "Num", "Num Lock", 0x145, 18.5, y, 1, 1, "n")
        k("NumpadDiv", "/", "Numpad /", 0x135, 19.5, y)
        k("NumpadMult", "*", "Numpad *", 0x037, 20.5, y)
        k("NumpadSub", "-", "Numpad -", 0x04A, 21.5, y)

        y := 2.25
        k("Tab", "Tab", "Tab", 0x00F, 0, y, 1.5)
        for i, c in StrSplit("qwertyuiop")
            k(c, StrUpper(c), StrUpper(c), 0x00F + i, 0.5 + i, y, 1, 1, "c")
        k("[", "[", "[ (left bracket)", 0x01A, 11.5, y, 1, 1, "c")
        k("]", "]", "] (right bracket)", 0x01B, 12.5, y, 1, 1, "c")
        k("\", "\", "\ (backslash)", 0x02B, 13.5, y, 1.5, 1, "c")
        k("Delete", "Del", "Delete", 0x153, 15.25, y)
        k("End", "End", "End", 0x14F, 16.25, y)
        k("PgDn", "PgDn", "Page Down", 0x151, 17.25, y)
        k("Numpad7", "7", "Numpad 7", 0x047, 18.5, y)
        k("Numpad8", "8", "Numpad 8", 0x048, 19.5, y)
        k("Numpad9", "9", "Numpad 9", 0x049, 20.5, y)
        k("NumpadAdd", "+", "Numpad +", 0x04E, 21.5, y, 1, 2)

        y := 3.25
        k("CapsLock", "Caps", "Caps Lock", 0x03A, 0, y, 1.75)
        for i, c in StrSplit("asdfghjkl")
            k(c, StrUpper(c), StrUpper(c), 0x01D + i, 0.75 + i, y, 1, 1, "c")
        k(";", ";", "; (semicolon)", 0x027, 10.75, y, 1, 1, "c")
        k("'", "'", "' (quote)", 0x028, 11.75, y, 1, 1, "c")
        k("Enter", "Enter", "Enter", 0x01C, 12.75, y, 2.25)
        k("Numpad4", "4", "Numpad 4", 0x04B, 18.5, y)
        k("Numpad5", "5", "Numpad 5", 0x04C, 19.5, y)
        k("Numpad6", "6", "Numpad 6", 0x04D, 20.5, y)

        y := 4.25
        k("LShift", "Shift", "Left Shift", 0x02A, 0, y, 2.25, 1, "m")
        for i, c in StrSplit("zxcvbnm")
            k(c, StrUpper(c), StrUpper(c), 0x02B + i, 1.25 + i, y, 1, 1, "c")
        k(",", ",", ", (comma)", 0x033, 9.25, y, 1, 1, "c")
        k(".", ".", ". (period)", 0x034, 10.25, y, 1, 1, "c")
        k("/", "/", "/ (slash)", 0x035, 11.25, y, 1, 1, "c")
        k("RShift", "Shift", "Right Shift", 0x136, 12.25, y, 2.75, 1, "m")
        k("Up", "↑", "Up Arrow", 0x148, 16.25, y)
        k("Numpad1", "1", "Numpad 1", 0x04F, 18.5, y)
        k("Numpad2", "2", "Numpad 2", 0x050, 19.5, y)
        k("Numpad3", "3", "Numpad 3", 0x051, 20.5, y)
        k("NumpadEnter", "Enter", "Numpad Enter", 0x11C, 21.5, y, 1, 2)

        y := 5.25
        k("LCtrl", "Ctrl", "Left Ctrl", 0x01D, 0, y, 1.25, 1, "m")
        k("LWin", "Win", "Left Win", 0x15B, 1.25, y, 1.25, 1, "m")
        k("LAlt", "Alt", "Left Alt", 0x038, 2.5, y, 1.25, 1, "m")
        k("Space", "Space", "Space", 0x039, 3.75, y, 6.25)
        k("RAlt", "Alt", "Right Alt", 0x138, 10, y, 1.25, 1, "m")
        k("RWin", "Win", "Right Win", 0x15C, 11.25, y, 1.25, 1, "m")
        k("AppsKey", "Menu", "Menu (Apps key)", 0x15D, 12.5, y, 1.25, 1, "n")
        k("RCtrl", "Ctrl", "Right Ctrl", 0x11D, 13.75, y, 1.25, 1, "m")
        k("Left", "←", "Left Arrow", 0x14B, 15.25, y)
        k("Down", "↓", "Down Arrow", 0x150, 16.25, y)
        k("Right", "→", "Right Arrow", 0x14D, 17.25, y)
        k("Numpad0", "0", "Numpad 0", 0x052, 18.5, y, 2)
        k("NumpadDot", ".", "Numpad .", 0x053, 20.5, y)

        this._BuildOutputCatalog()
    }

    static _Add(id, legend, name, sc, x, y, w := 1, h := 1, flags := "") {
        key := {id: id, legend: legend, name: name, sc: sc, x: x, y: y, w: w, h: h,
            char: InStr(flags, "c") > 0, isMod: InStr(flags, "m") > 0}
        scName := Format("SC{:03X}", sc)
        key.hk := (InStr(flags, "n") || key.isMod) ? id : scName      ; hotkey key name
        key.send := key.char ? scName : id                             ; Send key name
        this.List.Push(key)
        this.ById[id] := key
        this.BySc[sc] := key
    }

    static _BuildOutputCatalog() {
        self := this
        add(id, name, short := "") {
            item := {id: id, name: name, short: short != "" ? short : id}
            self.Out.Push(item)
            self.OutById[id] := item
        }
        order := []
        for c in StrSplit("abcdefghijklmnopqrstuvwxyz")
            order.Push(c)
        for d in StrSplit("1234567890")
            order.Push(d)
        for id in ["Enter", "Esc", "Backspace", "Tab", "Space", "``", "-", "=", "[", "]", "\", ";", "'", ",", ".", "/",
            "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn", "Insert", "Delete",
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
            order.Push(id)
        for id in order
            add(id, this.ById[id].name, this.ById[id].legend)
        loop 12
            add("F" (12 + A_Index), "F" (12 + A_Index))
        for id in ["PrintScreen", "ScrollLock", "Pause", "CapsLock", "NumLock", "AppsKey",
            "LCtrl", "LShift", "LAlt", "LWin", "RCtrl", "RShift", "RAlt", "RWin"]
            add(id, this.ById[id].name, this.ById[id].legend)
        for extra in [
            ["Media_Play_Pause", "Media: Play / Pause", "Play"], ["Media_Next", "Media: Next track", "Next"],
            ["Media_Prev", "Media: Previous track", "Prev"], ["Media_Stop", "Media: Stop", "Stop"],
            ["Volume_Up", "Volume up", "Vol+"], ["Volume_Down", "Volume down", "Vol-"],
            ["Volume_Mute", "Volume mute", "Mute"],
            ["Browser_Back", "Browser: Back", "Back"], ["Browser_Forward", "Browser: Forward", "Fwd"],
            ["Browser_Refresh", "Browser: Refresh", "Rfrsh"], ["Browser_Stop", "Browser: Stop", "BStop"],
            ["Browser_Search", "Browser: Search", "Search"], ["Browser_Favorites", "Browser: Favorites", "Favs"],
            ["Browser_Home", "Browser: Home", "BHome"],
            ["Launch_Mail", "Launch: Mail", "Mail"], ["Launch_Media", "Launch: Media player", "Media"],
            ["Launch_App1", "Launch: This PC", "PC"], ["Launch_App2", "Launch: Calculator", "Calc"],
            ["Sleep", "System: Sleep", "Sleep"]]
            add(extra[1], extra[2], extra[3])
        for key in this.List                      ; numpad keys last
            if !this.OutById.Has(key.id)
                add(key.id, key.name, key.legend)
    }

    static IsModifier(id) {
        for m in this.Modifiers
            if m = id
                return true
        return false
    }

    ; Name to use with Send for an output key id.
    static SendName(id) => this.ById.Has(id) ? this.ById[id].send : id

    ; Descriptive name ("Left Arrow"), for lists and descriptions.
    static Name(id) => this.OutById.Has(id) ? this.OutById[id].name : this.ById.Has(id) ? this.ById[id].name : id

    ; Short label ("←", "PgUp", "Vol+"), for key tiles.
    static Short(id) => this.OutById.Has(id) ? this.OutById[id].short : this.ById.Has(id) ? this.ById[id].legend : id

    ; Physical key id for a scan code as reported by AHK (0x100 = extended), or "".
    static FromSc(sc) => this.BySc.Has(sc) ? this.BySc[sc].id : ""
}
