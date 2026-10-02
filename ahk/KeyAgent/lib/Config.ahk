; Config.ahk - loading, saving and shaping KeyAgent's configuration (config.json).
;
; {
;   "version": 1,
;   "defaultKeymap": "QWR",
;   "settings": {...},                                  see DefaultSettings()
;   "keymaps": [{"name", "abbreviation", "layers": {"base": {keyId: action}, "mod": {...}}}],
;   "macros": [{"name", "steps": [step, ...]}]           see Macros.ahk for step shapes
; }

class Config {
    ; Settings written to JSON as true/false.
    static BoolKeys := Map("secondaryRoleDoubletapToPrimary", 1, "secondaryRoleTriggerByMouse", 1,
        "diagonalSpeedCompensation", 1, "smoothScroll", 1, "osdLocked", 1, "osdHeld", 1,
        "pauseWhenUhkConnected", 1, "uhkDongleCounts", 1)

    static DefaultSettings() {
        return Map(
            "doubleTapLayerTimeout", 250,           ; ms between taps to lock a layer
            "secondaryRoleStrategy", "Simple",      ; Simple | Advanced
            "secondaryRoleTimeout", 350,            ; Advanced: ms before a held key decides alone
            "secondaryRoleTimeoutAction", "Secondary",
            "secondaryRoleTrigger", "Press",        ; Advanced: Press | Release of another key
            "secondaryRoleDoubletapToPrimary", false,
            "secondaryRoleDoubletapTimeout", 200,
            "secondaryRoleTriggerByMouse", true,
            "mouseMove", Map("initialSpeed", 4, "baseSpeed", 32, "acceleratedSpeed", 64,
                "deceleratedSpeed", 12, "acceleration", 68),
            "mouseScroll", Map("initialSpeed", 20, "baseSpeed", 20, "acceleratedSpeed", 50,
                "deceleratedSpeed", 10, "acceleration", 20),
            "diagonalSpeedCompensation", true,
            "smoothScroll", false,
            "osdLocked", true,                      ; show indicator for locked layers / keymap switches
            "osdHeld", false,                       ; ...and while a layer key is held
            "pauseWhenUhkConnected", true,
            "uhkDongleCounts", false)
    }

    ; A config with one keymap and the default layer keys only.
    static Minimal() {
        km := this.NewKeymap("QWERTY", "QWR")
        km["layers"]["base"]["CapsLock"] := Map("type", "layer", "layer", "mouse", "mode", "holdAndDoubleTapToggle")
        km["layers"]["base"]["RAlt"] := Map("type", "layer", "layer", "mod", "mode", "holdAndDoubleTapToggle")
        return this.Normalize(Map("keymaps", [km], "macros", []))
    }

    static Load(path) => this.Normalize(Json.Parse(FileRead(path, "UTF-8")))

    static Save(cfg, path) {
        tmp := path ".tmp"
        f := FileOpen(tmp, "w", "UTF-8-RAW")
        f.Write(Json.Dump(cfg, this.BoolKeys) "`n")
        f.Close()
        FileMove(tmp, path, true)
    }

    ; Fills in anything missing and drops entries that aren't usable, so the rest of the
    ; program can rely on the shape documented above.
    static Normalize(cfg) {
        if !(cfg is Map)
            throw ValueError("The configuration must be a JSON object.")
        s := cfg.Get("settings", "")
        s := s is Map ? s : Map()
        for k, v in this.DefaultSettings() {
            if !s.Has(k) || (v is Map) != (s[k] is Map)
                s[k] := v
            else if v is Map
                for k2, v2 in v
                    if !s[k].Has(k2)
                        s[k][k2] := v2
        }
        cfg["settings"] := s

        kms := cfg.Get("keymaps", "")
        valid := []
        if kms is Array
            for km in kms {
                if !(km is Map) || !km.Has("abbreviation")
                    continue
                km["abbreviation"] := String(km["abbreviation"])
                if !km.Has("name")
                    km["name"] := km["abbreviation"]
                layers := km.Get("layers", "")
                layers := layers is Map ? layers : Map()
                for name in Actions.Layers {
                    if !layers.Has(name) || !(layers[name] is Map)
                        layers[name] := Map()
                    bad := []
                    for id, a in layers[name]
                        if !(a is Map) || !a.Has("type")
                            bad.Push(id)
                    for id in bad
                        layers[name].Delete(id)
                }
                km["layers"] := layers
                valid.Push(km)
            }
        if !valid.Length
            valid.Push(this.NewKeymap("QWERTY", "QWR"))
        cfg["keymaps"] := valid

        macros := cfg.Get("macros", "")
        list := []
        if macros is Array
            for m in macros
                if m is Map && m.Has("name") {
                    if !(m.Get("steps", "") is Array)
                        m["steps"] := []
                    list.Push(m)
                }
        cfg["macros"] := list

        if !this.Keymap(cfg, cfg.Get("defaultKeymap", ""))
            cfg["defaultKeymap"] := valid[1]["abbreviation"]
        cfg["version"] := 1
        return cfg
    }

    static NewKeymap(name, abbr) {
        layers := Map()
        for l in Actions.Layers
            layers[l] := Map()
        return Map("name", name, "abbreviation", abbr, "layers", layers)
    }

    static Keymap(cfg, abbr) {
        for km in cfg["keymaps"]
            if km["abbreviation"] = abbr
                return km
        return ""
    }

    static KeymapIndex(cfg, abbr) {
        for km in cfg["keymaps"]
            if km["abbreviation"] = abbr
                return A_Index
        return 0
    }

    static Macro(cfg, name) {
        for m in cfg["macros"]
            if m["name"] == name
                return m
        return ""
    }

    ; An abbreviation (up to 3 letters, like the UHK's) not used by any keymap yet.
    static UniqueAbbr(cfg, name) {
        base := StrUpper(SubStr(RegExReplace(name, "[^A-Za-z0-9]"), 1, 3))
        if base = ""
            base := "KM"
        abbr := base, n := 1
        while this.Keymap(cfg, abbr)
            abbr := SubStr(base, 1, 2) (++n)
        return abbr
    }

    static Clone(v) {
        if v is Map {
            c := Map()
            for k, x in v
                c[k] := this.Clone(x)
            return c
        }
        if v is Array {
            c := []
            for x in v
                c.Push(this.Clone(x))
            return c
        }
        return v
    }
}
