; UhkImport.ahk - converts a UHK Agent user configuration (the JSON file UHK Agent keeps in
; %APPDATA%\uhk-agent) into KeyAgent keymaps, macros and settings.
;
; The UHK is split and has thumb keys a normal keyboard doesn't, so key positions are mapped by
; meaning, using the UHK's default keymap's base layer to tell what each position is:
;   * a position that types a key there becomes that key here - the UHK's "I" position is
;     this keyboard's I key, so Mod+I stays Up;
;   * a position holding a modifier becomes that modifier key;
;   * a position that switches layers (the UHK's Mod / Fn / Mouse keys) becomes whichever key
;     is chosen as that layer's key on this keyboard (options.triggers).
; Base layers only carry over letter/number/punctuation remaps (Colemak, Dvorak, ...) and
; tap/hold keys; everything else on a normal keyboard's base layer stays as it is.

class UhkImport {
    static DefaultTriggers() => Map("mod", "RAlt", "mouse", "CapsLock", "fn", "", "fn2", "", "fn3", "", "fn4", "", "fn5", "")

    ; Finds UHK Agent's config file(s) in %APPDATA%\uhk-agent.
    static FindConfigs() {
        found := []
        loop files A_AppData "\uhk-agent\*.json"
            if RegExMatch(A_LoopFileName, "^\d+\.json$")
                found.Push(A_LoopFileFullPath)
        return found
    }

    static Load(path) {
        uhk := Json.Parse(FileRead(path, "UTF-8"))
        if !(uhk is Map) || !(uhk.Get("keymaps", "") is Array)
            throw ValueError("This doesn't look like a UHK Agent configuration (no keymaps).")
        return uhk
    }

    ; [{abbreviation, name, isDefault}] for the import dialog.
    static ListKeymaps(uhk) {
        list := []
        for km in uhk["keymaps"]
            list.Push({abbreviation: km["abbreviation"], name: km["name"], isDefault: km.Get("isDefault", 0)})
        return list
    }

    ; options: {keymaps: [abbreviations], triggers: Map(layer -> key id or ""), macros: bool,
    ;           settings: bool}
    ; Returns {keymaps: [], macros: [], settings: Map, log: [lines]}.
    static Convert(uhk, options) {
        this._log := Map()
        triggers := options.triggers
        posKey := this._PositionMap(uhk, triggers)
        macroNames := []
        for m in uhk.Get("macros", [])
            macroNames.Push(m["name"])

        keymaps := []
        for km in uhk["keymaps"] {
            if !this._In(options.keymaps, km["abbreviation"])
                continue
            out := Config.NewKeymap(km["name"], km["abbreviation"])
            for layer in km["layers"] {
                lid := layer["id"]
                if !Actions.IsLayer(lid) {
                    this._Note("Skipped the `"" lid "`" layer (KeyAgent has base, mod, fn, mouse, fn2-fn5)")
                    continue
                }
                for module in layer["modules"]
                    for i, a in module["keyActions"] {
                        pos := module["id"] "/" (i - 1)
                        if !(a is Map) || !posKey.Has(pos)
                            continue
                        if lid = "base"
                            this._ImportBase(a, posKey[pos], out["layers"]["base"], macroNames, options)
                        else
                            this._ImportLayer(a, posKey[pos], out["layers"][lid], macroNames, options)
                    }
            }
            ; layer keys for this keyboard, with the mode the UHK's own layer key uses
            for layerName, keyId in triggers
                if keyId != ""
                    out["layers"]["base"][keyId] := Map("type", "layer", "layer", layerName,
                        "mode", this._LayerMode(km, layerName))
            ; a layer entry that does what the base layer already does is redundant
            for lid, layerMap in out["layers"] {
                if lid = "base"
                    continue
                same := []
                for id, a in layerMap
                    if out["layers"]["base"].Has(id) && Actions.Equal(a, out["layers"]["base"][id])
                        same.Push(id)
                for id in same
                    layerMap.Delete(id)
            }
            keymaps.Push(out)
        }

        macros := []
        if options.macros
            for m in uhk.Get("macros", [])
                macros.Push(this._Macro(m))

        settings := options.settings ? this._Settings(uhk) : Map()
        log := []
        for msg, n in this._log
            log.Push(msg (n > 1 ? " (" n "x)" : ""))
        return {keymaps: keymaps, macros: macros, settings: settings, log: log}
    }

    ; UHK position ("module/index") -> key id on this keyboard, from the default keymap.
    static _PositionMap(uhk, triggers) {
        ref := ""
        for km in uhk["keymaps"]
            if km.Get("isDefault", 0) {
                ref := km
                break
            }
        if !ref
            ref := uhk["keymaps"][1]
        posKey := Map()
        for layer in ref["layers"]
            if layer["id"] = "base"
                for module in layer["modules"]
                    for i, a in module["keyActions"] {
                        if !(a is Map)
                            continue
                        id := ""
                        t := a["keyActionType"]
                        if t = "keystroke" && a.Get("type", "basic") = "basic" {
                            sc := a.Get("scancode", 0), mask := a.Get("modifierMask", 0)
                            if sc && !mask
                                id := this.HidKey(sc)
                            else if !sc && mask {
                                mods := this._Mods(mask)
                                id := mods.Length = 1 ? mods[1] : ""
                            }
                        } else if t = "switchLayer"
                            id := triggers.Get(a["layer"], "")
                        if id != "" && Keys.ById.Has(id)
                            posKey[module["id"] "/" (i - 1)] := id
                    }
        return posKey
    }

    static _ImportBase(a, id, base, macroNames, options) {
        if a["keyActionType"] != "keystroke"
            return
        key := Keys.ById[id]
        if key.isMod || !(key.char || a.Has("secondaryRoleAction"))
            return
        conv := this._Action(a, macroNames, options)
        if conv && !this._IsIdentity(conv, id)
            base[id] := conv
    }

    static _ImportLayer(a, id, layerMap, macroNames, options) {
        conv := this._Action(a, macroNames, options)
        if !conv || this._IsIdentity(conv, id)
            return
        if layerMap.Has(id) {
            if !Actions.Equal(layerMap[id], conv)
                this._Note("Two UHK keys land on the same key here; kept the first")
            return
        }
        layerMap[id] := conv
    }

    ; One UHK key action -> KeyAgent action Map, or "" if it has no equivalent.
    static _Action(a, macroNames, options) {
        switch a["keyActionType"] {
            case "none":
                return ""
            case "keystroke":
                key := ""
                if sc := a.Get("scancode", 0) {
                    key := this._ScancodeKey(a.Get("type", "basic"), sc)
                    if key = "" {
                        this._Note("Skipped keys with no Windows equivalent (" a.Get("type", "basic") " code " sc ")")
                        return ""
                    }
                }
                mods := this._Mods(a.Get("modifierMask", 0))
                if key = "" && mods.Length = 1
                    key := mods.RemoveAt(1)
                if key = "" && !mods.Length
                    return ""
                act := Map("type", "key", "key", key)
                if mods.Length
                    act["mods"] := mods
                if (sec := a.Get("secondaryRoleAction", "")) != "" {
                    if this.SecondaryRoles.Has(sec)
                        act["secondary"] := this.SecondaryRoles[sec]
                    else
                        this._Note("Dropped an unknown secondary role `"" sec "`"")
                }
                return act
            case "switchLayer":
                layer := a["layer"]
                if !Actions.IsLayer(layer) || layer = "base" {
                    this._Note("Skipped switches to the `"" layer "`" layer")
                    return ""
                }
                mode := a.Get("switchLayerMode", a.Get("toggle", 0) ? "toggle" : "hold")
                return Map("type", "layer", "layer", layer, "mode", mode)
            case "switchKeymap":
                abbr := a["keymapAbbreviation"]
                if !this._In(options.keymaps, abbr) {
                    this._Note("Skipped switches to keymaps that weren't imported (" abbr ")")
                    return ""
                }
                return Map("type", "keymap", "keymap", abbr)
            case "mouse":
                return Map("type", "mouse", "action", a["mouseAction"])
            case "playMacro":
                i := a["macroIndex"] + 1
                if options.macros && i >= 1 && i <= macroNames.Length
                    return Map("type", "macro", "macro", macroNames[i])
                this._Note("Skipped macro keys whose macro wasn't imported")
                return ""
            case "connections":
                this._Note("Skipped Bluetooth / host connection keys (keyboard hardware only)")
                return ""
        }
        this._Note("Skipped `"" a["keyActionType"] "`" keys (keyboard hardware only)")
        return ""
    }

    static _IsIdentity(conv, id) => conv["type"] = "key" && conv["key"] == id
        && !conv.Has("mods") && !conv.Has("secondary")

    ; Mode of the keymap's own key for a layer (so double-tap locking carries over).
    static _LayerMode(km, layerName) {
        for layer in km["layers"]
            if layer["id"] = "base"
                for module in layer["modules"]
                    for a in module["keyActions"]
                        if a is Map && a["keyActionType"] = "switchLayer" && a["layer"] = layerName
                            return a.Get("switchLayerMode", a.Get("toggle", 0) ? "toggle" : "hold")
        return "holdAndDoubleTapToggle"
    }

    static _Macro(m) {
        steps := []
        for x in m.Get("macroActions", []) {
            action := x.Get("action", "tap")        ; tap | press | hold | release
            mode := action = "tap" ? "tap" : action = "release" ? "release" : "press"
            switch x["macroActionType"] {
                case "key":
                    step := Map("type", "key", "mode", mode)
                    key := x.Get("scancode", 0) ? this._ScancodeKey(x.Get("type", "basic"), x["scancode"]) : ""
                    mods := this._Mods(x.Get("modifierMask", 0))
                    if key = "" && !mods.Length {
                        this._Note("Skipped macro keys with no Windows equivalent")
                        continue
                    }
                    step["key"] := key
                    if mods.Length
                        step["mods"] := mods
                    steps.Push(step)
                case "text":
                    steps.Push(Map("type", "text", "text", x["text"]))
                case "delay":
                    steps.Push(Map("type", "delay", "ms", x.Get("delay", 0)))
                case "mouseButton":
                    mask := x.Get("mouseButtonsMask", 0)
                    for i, btn in Macros.Buttons
                        if mask & (1 << (i - 1))
                            steps.Push(Map("type", "mouse", "mode", mode, "button", btn))
                case "moveMouse":
                    steps.Push(Map("type", "move", "x", x.Get("x", 0), "y", x.Get("y", 0)))
                case "scrollMouse":
                    steps.Push(Map("type", "scroll", "x", x.Get("x", 0), "y", x.Get("y", 0)))
                default:
                    this._Note("Skipped smart-macro commands (UHK firmware only)")
            }
        }
        return Map("name", m["name"], "steps", steps)
    }

    static _Settings(uhk) {
        s := Map()
        copy(from, to) {
            if uhk.Has(from)
                s[to] := uhk[from]
        }
        copy("doubleTapSwitchLayerTimeout", "doubleTapLayerTimeout")
        copy("secondaryRoleStrategy", "secondaryRoleStrategy")
        copy("secondaryRoleAdvancedStrategyTimeout", "secondaryRoleTimeout")
        copy("secondaryRoleAdvancedStrategyTimeoutAction", "secondaryRoleTimeoutAction")
        copy("secondaryRoleAdvancedStrategyTrigger", "secondaryRoleTrigger")
        copy("secondaryRoleAdvancedStrategyDoubletapToPrimary", "secondaryRoleDoubletapToPrimary")
        copy("secondaryRoleAdvancedStrategyDoubletapTimeout", "secondaryRoleDoubletapTimeout")
        copy("secondaryRoleAdvancedStrategyTriggerByMouse", "secondaryRoleTriggerByMouse")
        copy("diagonalSpeedCompensation", "diagonalSpeedCompensation")
        for kind in ["Move", "Scroll"] {
            p := Map()
            for field in ["InitialSpeed", "BaseSpeed", "AcceleratedSpeed", "DeceleratedSpeed", "Acceleration"]
                if uhk.Has("mouse" kind field)
                    p[StrLower(SubStr(field, 1, 1)) SubStr(field, 2)] := uhk["mouse" kind field]
            if p.Count
                s["mouse" kind] := p
        }
        return s
    }

    static _ScancodeKey(type, sc) {
        switch type {
            case "basic":
                return this.HidKey(sc)
            case "media", "shortMedia", "longMedia":
                return this.ConsumerKeys.Get(sc, "")
            case "system":
                return sc = 0x82 ? "Sleep" : ""
        }
        return ""
    }

    ; HID keyboard usage -> key id.
    static HidKey(usage) {
        static table := ""
        if !table {
            table := Map()
            for i, c in StrSplit("abcdefghijklmnopqrstuvwxyz")
                table[3 + i] := c
            for i, d in StrSplit("1234567890")
                table[29 + i] := d
            for usage_, id in Map(40, "Enter", 41, "Esc", 42, "Backspace", 43, "Tab", 44, "Space",
                45, "-", 46, "=", 47, "[", 48, "]", 49, "\", 50, "\", 51, ";", 52, "'", 53, "``",
                54, ",", 55, ".", 56, "/", 57, "CapsLock", 70, "PrintScreen", 71, "ScrollLock",
                72, "Pause", 73, "Insert", 74, "Home", 75, "PgUp", 76, "Delete", 77, "End",
                78, "PgDn", 79, "Right", 80, "Left", 81, "Down", 82, "Up", 83, "NumLock",
                84, "NumpadDiv", 85, "NumpadMult", 86, "NumpadSub", 87, "NumpadAdd",
                88, "NumpadEnter", 98, "Numpad0", 99, "NumpadDot", 101, "AppsKey",
                127, "Volume_Mute", 128, "Volume_Up", 129, "Volume_Down",
                224, "LCtrl", 225, "LShift", 226, "LAlt", 227, "LWin",
                228, "RCtrl", 229, "RShift", 230, "RAlt", 231, "RWin")
                table[usage_] := id
            loop 12
                table[57 + A_Index] := "F" A_Index           ; F1-F12
            loop 9
                table[88 + A_Index] := "Numpad" A_Index      ; Numpad1-9
            loop 12
                table[103 + A_Index] := "F" (12 + A_Index)   ; F13-F24
        }
        return table.Get(usage, "")
    }

    static ConsumerKeys := Map(0xB5, "Media_Next", 0xB6, "Media_Prev", 0xB7, "Media_Stop",
        0xCD, "Media_Play_Pause", 0xE2, "Volume_Mute", 0xE9, "Volume_Up", 0xEA, "Volume_Down",
        0x183, "Launch_Media", 0x18A, "Launch_Mail", 0x192, "Launch_App2", 0x194, "Launch_App1",
        0x221, "Browser_Search", 0x223, "Browser_Home", 0x224, "Browser_Back",
        0x225, "Browser_Forward", 0x226, "Browser_Stop", 0x227, "Browser_Refresh",
        0x22A, "Browser_Favorites")

    static SecondaryRoles := Map("leftCtrl", "LCtrl", "leftShift", "LShift", "leftAlt", "LAlt",
        "leftSuper", "LWin", "rightCtrl", "RCtrl", "rightShift", "RShift", "rightAlt", "RAlt",
        "rightSuper", "RWin", "mod", "mod", "fn", "fn", "mouse", "mouse",
        "fn2", "fn2", "fn3", "fn3", "fn4", "fn4", "fn5", "fn5")

    static _Mods(mask) {
        mods := []
        for i, m in ["LCtrl", "LShift", "LAlt", "LWin", "RCtrl", "RShift", "RAlt", "RWin"]
            if mask & (1 << (i - 1))
                mods.Push(m)
        return mods
    }

    static _In(list, value) {
        for x in list
            if x = value
                return true
        return false
    }

    static _log := Map()
    static _Note(msg) => this._log[msg] := this._log.Get(msg, 0) + 1
}
