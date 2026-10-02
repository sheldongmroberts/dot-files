; Actions.ahk - what a key can do, and how actions are labelled in the editor.
;
; An action is a Map stored in the config:
;   {type: "key", key: "Up", mods: ["LCtrl"], secondary: "mod"}
;         sends a key, a shortcut (key + mods) or holds modifiers (key empty or a modifier).
;         "secondary" (optional) makes it a tap/hold key: tap = this action, hold = the
;         secondary role (a modifier like "LCtrl" or a layer like "mod").
;   {type: "layer", layer: "mod", mode: "hold" | "toggle" | "holdAndDoubleTapToggle"}
;   {type: "keymap", keymap: "QWR"}
;   {type: "mouse", action: "moveUp"}
;   {type: "macro", macro: "<macro name>"}
;   {type: "none"}         the key does nothing on this layer
; A key with no action on a layer falls through to the Base layer; a key with no action on
; the Base layer behaves normally.

class Actions {
    static Layers := ["base", "mod", "fn", "mouse", "fn2", "fn3", "fn4", "fn5"]
    static LayerNames := Map("base", "Base", "mod", "Mod", "fn", "Fn", "mouse", "Mouse",
        "fn2", "Fn2", "fn3", "Fn3", "fn4", "Fn4", "fn5", "Fn5")
    static Modes := [
        ["hold", "Hold (active while held)"],
        ["holdAndDoubleTapToggle", "Hold, or double-tap to lock"],
        ["toggle", "Toggle (each press locks / unlocks)"]]
    static MouseActions := [
        ["moveUp", "Move pointer up", "M↑"], ["moveDown", "Move pointer down", "M↓"],
        ["moveLeft", "Move pointer left", "M←"], ["moveRight", "Move pointer right", "M→"],
        ["scrollUp", "Scroll up", "S↑"], ["scrollDown", "Scroll down", "S↓"],
        ["scrollLeft", "Scroll left", "S←"], ["scrollRight", "Scroll right", "S→"],
        ["leftClick", "Left button", "LClk"], ["middleClick", "Middle button", "MClk"],
        ["rightClick", "Right button", "RClk"], ["button4", "Button 4 (back)", "Btn4"],
        ["button5", "Button 5 (forward)", "Btn5"],
        ["accelerate", "Accelerate (hold while moving)", "Fast"],
        ["decelerate", "Decelerate (hold while moving)", "Slow"]]
    static ModSymbols := Map("LCtrl", "^", "RCtrl", "^", "LShift", "+", "RShift", "+",
        "LAlt", "!", "RAlt", "!", "LWin", "#", "RWin", "#")

    static IsLayer(name) {
        for l in this.Layers
            if l = name
                return true
        return false
    }

    ; Choices for a key's secondary (hold) role: [value, label].
    static SecondaryChoices() {
        list := [["", "(none - plain key)"]]
        for m in Keys.Modifiers
            list.Push([m, Keys.Name(m)])
        for l in this.Layers
            if l != "base"
                list.Push([l, this.LayerNames[l] " layer"])
        return list
    }

    ; Display category, which picks the tile color: key, shortcut, modifier, layer, keymap,
    ; mouse, macro, none.
    static Category(a) {
        switch a["type"] {
            case "key":
                key := a.Get("key", ""), mods := a.Get("mods", [])
                if key = "" || Keys.IsModifier(key)
                    return "modifier"
                return mods.Length ? "shortcut" : "key"
            case "layer", "keymap", "mouse", "macro":
                return a["type"]
        }
        return "none"
    }

    ; Short label for a key tile.
    static Short(a) {
        switch a["type"] {
            case "key":
                key := a.Get("key", ""), mods := a.Get("mods", [])
                if key = "" || Keys.IsModifier(key) {
                    names := key != "" ? [Keys.Short(key)] : []
                    for m in mods
                        names.Push(Keys.Short(m))
                    label := this._Join(names, "+")
                } else
                    label := this.ModPrefix(mods) Keys.Short(key)
                if (sec := a.Get("secondary", "")) != ""
                    label .= "/" (Keys.IsModifier(sec) ? this.ModSymbols[sec] : this.LayerNames.Get(sec, sec))
                return label
            case "layer":
                return this.LayerNames.Get(a["layer"], a["layer"])
            case "keymap":
                return "→" a["keymap"]
            case "mouse":
                return this._Mouse(a["action"], 3)
            case "macro":
                return "►" SubStr(a["macro"], 1, 6)
        }
        return "×"
    }

    ; One-line description for the editor.
    static Describe(a, cfg := "") {
        switch a["type"] {
            case "key":
                key := a.Get("key", ""), mods := a.Get("mods", [])
                if key = "" || Keys.IsModifier(key) {
                    names := key != "" ? [Keys.Name(key)] : []
                    for m in mods
                        names.Push(Keys.Name(m))
                    text := "Holds " this._Join(names, " + ")
                } else
                    text := "Sends " this.ModText(mods) Keys.Name(key)
                if (sec := a.Get("secondary", "")) != ""
                    text .= "; acts as " (Keys.IsModifier(sec) ? Keys.Name(sec) : this.LayerNames.Get(sec, sec) " layer") " while held"
                return text
            case "layer":
                mode := a.Get("mode", "hold")
                for m in this.Modes
                    if m[1] = mode
                        mode := m[2]
                return "Switches to the " this.LayerNames.Get(a["layer"], a["layer"]) " layer: " StrLower(mode)
            case "keymap":
                name := ""
                if cfg && (km := Config.Keymap(cfg, a["keymap"]))
                    name := " (" km["name"] ")"
                return "Switches to keymap " a["keymap"] name
            case "mouse":
                return "Mouse: " this._Mouse(a["action"], 2)
            case "macro":
                return "Plays macro `"" a["macro"] "`""
        }
        return "Does nothing on this layer"
    }

    static ModPrefix(mods) {
        s := ""
        for m in mods
            if !InStr(s, this.ModSymbols.Get(m, ""))
                s .= this.ModSymbols.Get(m, "")
        return s
    }

    static ModText(mods) {
        s := ""
        for m in mods
            s .= Keys.Name(m) " + "
        return s
    }

    static Equal(a, b) => Json.Dump(a) == Json.Dump(b)

    static _Mouse(action, field) {
        for m in this.MouseActions
            if m[1] = action
                return m[field]
        return action
    }

    static _Join(arr, sep) {
        s := ""
        for x in arr
            s .= (A_Index > 1 ? sep : "") x
        return s
    }
}
