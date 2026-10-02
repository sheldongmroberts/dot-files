; Editor.ahk - the configuration window, modelled on UHK Agent: pick a keymap and a layer, click a
; key, choose what it does. Edits go to a working copy and take effect on "Save & Apply".

class Editor {
    static gui := ""
    static cfg := ""                ; working copy being edited
    static dirty := false
    static abbr := ""               ; keymap shown
    static layer := "base"          ; layer shown
    static sel := ""                ; selected key id
    static tiles := Map()           ; key id -> {key, top, body, state}
    static c := ""                  ; named controls
    static groups := Map()          ; action type -> controls shown for it
    static U := 42                  ; pixels per key unit
    static OX := 14, OY := 86       ; keyboard origin
    static W := 973, H := 640
    static TileBg := "2B2D31", SelBg := "1F5FBF", LegendFg := "8A9099"
    ; tile text colors per action category (after the UHK's functional backlighting colors)
    static Colors := Map("native", "D0D4DA", "key", "FFFFFF", "shortcut", "8AB4FF",
        "modifier", "5EE0F0", "layer", "F5D547", "keymap", "FF7B7B", "mouse", "7BE086",
        "macro", "E08BFF", "none", "8A8F98", "transparent", "666C75")
    static TypeValues := ["", "key", "layer", "keymap", "mouse", "macro", "none"]

    static IsOpen() => this.gui != ""

    static Open(*) {
        if this.gui {
            this.gui.Show()
            return
        }
        this.cfg := Config.Clone(App.cfg)
        this.dirty := false
        this.abbr := Engine.keymap && Config.Keymap(this.cfg, Engine.keymap["abbreviation"])
            ? Engine.keymap["abbreviation"] : this.cfg["defaultKeymap"]
        this.layer := "base", this.sel := ""
        this._Build()
        this._RefreshKeymaps()
        this._RefreshMacroList()
        this._RefreshTiles()
        this._ShowAction()
        this._UpdateStatus()
        this.gui.Show("w" this.W " h" this.H)
    }

    ; config.json was reloaded from disk: pick it up unless there are unsaved edits.
    static OnConfigReloaded() {
        if !this.gui || this.dirty
            return
        this._Reset(Config.Clone(App.cfg))
    }

    ; ---------------------------------------------------------------- layout

    static _Build() {
        g := Gui("-MaximizeBox", "KeyAgent")
        g.BackColor := "F3F4F6"
        g.SetFont("s9", "Segoe UI")
        g.OnEvent("Close", ObjBindMethod(this, "_OnClose"))
        g.OnEvent("Escape", ObjBindMethod(this, "_OnClose"))
        this.gui := g
        c := this.c := {}

        ; keymap bar
        g.Add("Text", "x14 y16", "Keymap")
        c.keymap := this._On(g.Add("DropDownList", "x66 y12 w220"), "Change", "_OnKeymapPick")
        this._On(g.Add("Button", "x+6 yp-1 w52 h25", "New…"), "Click", "_NewKeymap")
        this._On(g.Add("Button", "x+6 yp w74 h25", "Duplicate…"), "Click", "_DuplicateKeymap")
        this._On(g.Add("Button", "x+6 yp w66 h25", "Rename…"), "Click", "_RenameKeymap")
        this._On(g.Add("Button", "x+6 yp w54 h25", "Delete"), "Click", "_DeleteKeymap")
        c.makeDefault := this._On(g.Add("Button", "x+6 yp w88 h25", "Make default"), "Click", "_MakeDefault")
        this._On(g.Add("Button", "x671 y11 w76 h25", "Macros…"), "Click", "_OpenMacros")
        this._On(g.Add("Button", "x753 y11 w80 h25", "Settings…"), "Click", "_OpenSettings")
        this._On(g.Add("Button", "x839 y11 w120 h25", "Import from UHK…"), "Click", "_OpenImport")

        ; layer tabs
        c.layers := []
        for i, l in Actions.Layers {
            r := g.Add("Radio", (i = 1 ? "x14 y48 Group" : "x+4 yp") " w62 h26 +0x1000", Actions.LayerNames[l])
            this._On(r, "Click", "_OnLayerPick", l)
            c.layers.Push(r)
        }
        c.layers[1].Value := 1
        g.Add("Text", "x560 y54 w305 Right c666C75", "Click a key to see or change what it does")
        this._On(g.Add("Button", "x875 y48 w84 h26", "Find key…"), "Click", "_FindKey")

        ; keyboard
        U := this.U
        for k in Keys.List {
            x := this.OX + Round(k.x * U), y := this.OY + Round(k.y * U)
            w := Round(k.w * U) - 3, h := Round(k.h * U) - 3
            top := g.Add("Text", Format("x{} y{} w{} h13 +0x100 Background{} c{}", x, y, w, this.TileBg, this.LegendFg))
            top.SetFont("s7")
            body := g.Add("Text", Format("x{} y{} w{} h{} Center +0x200 +0x100 Background{} cFFFFFF",
                x, y + 13, w, h - 13, this.TileBg))
            body.SetFont("s8")
            this._On(top, "Click", "_Select", k.id)
            this._On(body, "Click", "_Select", k.id)
            this.tiles[k.id] := {key: k, top: top, body: body, state: ""}
        }

        ; color legend
        y := this.OY + Round(Keys.Height * U) + 6, x := this.OX
        for item in [["key", "Key"], ["shortcut", "Shortcut"], ["modifier", "Modifier"], ["layer", "Layer"],
            ["keymap", "Keymap"], ["mouse", "Mouse"], ["macro", "Macro"], ["none", "Disabled"],
            ["transparent", "From Base"]] {
            t := g.Add("Text", Format("x{} y{} w68 h18 Center +0x200 Background{} c{}", x, y, this.TileBg, this.Colors[item[1]]), item[2])
            t.SetFont("s8")
            x += 72
        }
        g.Add("Text", Format("x{} y{} w{} Right c666C75", x + 10, y + 2, this.W - this.OX - x - 10), "^ Ctrl    + Shift    ! Alt    # Win")

        ; action panel
        gy := y + 28
        g.Add("GroupBox", Format("x14 y{} w945 h196", gy))
        c.title := g.Add("Text", Format("x28 y{} w700", gy + 16))
        c.title.SetFont("s10 bold")
        c.desc := g.Add("Text", Format("x28 y{} w900 +0x80 c4A4F57", gy + 40))
        ry := gy + 66
        g.Add("Text", Format("x28 y{} w62", ry + 4), "Action")
        c.type := this._On(g.Add("DropDownList", Format("x92 y{} w300", ry)), "Change", "_OnTypeChange")
        ya := ry + 34, yb := ry + 66, yc := ry + 98
        grp := Map()

        names := []
        for item in Keys.Out
            names.Push(item.name)
        k1 := g.Add("Text", Format("x28 y{} w62", ya + 4), "Key")
        c.key := this._On(g.Add("DropDownList", Format("x92 y{} w230 R24", ya), names), "Change", "_OnFieldChange")
        c.capture := this._On(g.Add("Button", "x+6 yp-1 w90 h25", "Capture…"), "Click", "_CaptureOutput")
        k2 := g.Add("Text", Format("x28 y{} w62", yb + 2), "Modifiers")
        c.mods := []
        for i, m in Keys.Modifiers {
            label := StrReplace(StrReplace(Keys.Name(m), "Left ", "L "), "Right ", "R ")
            cb := this._On(g.Add("Checkbox", Format("x{} y{} w62", 92 + (i - 1) * 64, yb + 2), label), "Click", "_OnFieldChange")
            c.mods.Push(cb)
        }
        secLabels := []
        for s in Actions.SecondaryChoices()
            secLabels.Push(s[2])
        k3 := g.Add("Text", Format("x28 y{} w62", yc + 4), "When held")
        c.secondary := this._On(g.Add("DropDownList", Format("x92 y{} w230 R16", yc), secLabels), "Change", "_OnFieldChange")
        k4 := g.Add("Text", Format("x330 y{} w600 c666C75", yc + 4), "Tap/hold key: a tap sends the key above, holding it acts as this.")
        grp["key"] := [k1, c.key, c.capture, k2, k3, c.secondary, k4]
        for cb in c.mods
            grp["key"].Push(cb)

        layerNames := []
        for l in Actions.Layers
            if l != "base"
                layerNames.Push(Actions.LayerNames[l])
        l1 := g.Add("Text", Format("x28 y{} w62", ya + 4), "Layer")
        c.layerPick := this._On(g.Add("DropDownList", Format("x92 y{} w230", ya), layerNames), "Change", "_OnFieldChange")
        modeNames := []
        for m in Actions.Modes
            modeNames.Push(m[2])
        l2 := g.Add("Text", Format("x28 y{} w62", yb + 4), "Mode")
        c.mode := this._On(g.Add("DropDownList", Format("x92 y{} w300", yb), modeNames), "Change", "_OnFieldChange")
        grp["layer"] := [l1, c.layerPick, l2, c.mode]

        m1 := g.Add("Text", Format("x28 y{} w62", ya + 4), "Keymap")
        c.keymapPick := this._On(g.Add("DropDownList", Format("x92 y{} w230", ya)), "Change", "_OnFieldChange")
        grp["keymap"] := [m1, c.keymapPick]

        mouseNames := []
        for m in Actions.MouseActions
            mouseNames.Push(m[2])
        o1 := g.Add("Text", Format("x28 y{} w62", ya + 4), "Mouse")
        c.mouse := this._On(g.Add("DropDownList", Format("x92 y{} w230 R16", ya), mouseNames), "Change", "_OnFieldChange")
        o2 := g.Add("Text", Format("x330 y{} w600 c666C75", ya + 4), "Speeds and acceleration are in Settings.")
        grp["mouse"] := [o1, c.mouse, o2]

        p1 := g.Add("Text", Format("x28 y{} w62", ya + 4), "Macro")
        c.macro := this._On(g.Add("DropDownList", Format("x92 y{} w230", ya)), "Change", "_OnFieldChange")
        p2 := this._On(g.Add("Button", "x+6 yp-1 w100 h25", "Edit macros…"), "Click", "_OpenMacros")
        grp["macro"] := [p1, c.macro, p2]
        this.groups := grp

        ; bottom bar
        by := gy + 196 + 12
        g.Add("Text", Format("x14 y{}", by + 4), "Try it here")
        g.Add("Edit", Format("x84 y{} w300 h24", by))
        c.status := g.Add("Text", Format("x400 y{} w350 +0x80 c4A4F57", by + 4))
        this._On(g.Add("Button", Format("x763 y{} w80 h26", by - 1), "Revert"), "Click", "_Revert")
        c.save := this._On(g.Add("Button", Format("x849 y{} w110 h26", by - 1), "Save && Apply"), "Click", "_Save")
        this.H := by + 38
    }

    static _On(ctrl, event, method, args*) {
        ctrl.OnEvent(event, ObjBindMethod(this, method, args*))
        return ctrl
    }

    ; ---------------------------------------------------------------- display

    static _Layers() => Config.Keymap(this.cfg, this.abbr)["layers"]
    static _Get(layer, id) => this._Layers()[layer].Get(id, "")

    static _RefreshKeymaps() {
        c := this.c, names := [], picks := []
        for km in this.cfg["keymaps"] {
            label := km["name"] " (" km["abbreviation"] ")"
            names.Push(label (km["abbreviation"] = this.cfg["defaultKeymap"] ? "  - default" : ""))
            picks.Push(label)
        }
        c.keymap.Delete(), c.keymap.Add(names)
        c.keymap.Choose(Config.KeymapIndex(this.cfg, this.abbr))
        c.makeDefault.Enabled := this.abbr != this.cfg["defaultKeymap"]
        c.keymapPick.Delete(), c.keymapPick.Add(picks)
    }

    static _RefreshMacroList() {
        names := []
        for m in this.cfg["macros"]
            names.Push(m["name"])
        this.c.macro.Delete(), this.c.macro.Add(names)
    }

    static _RefreshTiles() {
        for id in this.tiles
            this._RefreshTile(id)
    }

    static _RefreshTile(id) {
        t := this.tiles[id], k := t.key
        a := this._Get(this.layer, id)
        if a != "" {
            top := " " k.legend, body := Actions.Short(a), cat := Actions.Category(a)
        } else if this.layer != "base" && (b := this._Get("base", id)) != "" {
            top := " " k.legend, body := Actions.Short(b), cat := "transparent"
        } else {
            top := "", body := k.legend, cat := this.layer = "base" ? "native" : "transparent"
        }
        bg := id = this.sel ? this.SelBg : this.TileBg
        state := top "|" body "|" cat "|" bg
        if state == t.state
            return
        t.state := state
        t.top.Opt("Background" bg)
        t.top.Value := top
        t.body.Opt("Background" bg)
        t.body.SetFont("c" this.Colors[cat] (StrLen(body) > 5 && k.w < 1.5 ? " s7" : " s8"))
        t.body.Value := StrReplace(body, " ", Chr(0xA0))     ; no word wrap inside a tile
        t.top.Redraw(), t.body.Redraw()
    }

    static _Select(id, *) {
        prev := this.sel
        this.sel := id
        if prev != "" && prev != id
            this._RefreshTile(prev)
        this._RefreshTile(id)
        this._ShowAction()
    }

    static _ShowAction() {
        c := this.c, id := this.sel
        layerName := Actions.LayerNames[this.layer]
        c.type.Delete()
        c.type.Add([this.layer = "base" ? "Not mapped - works as a normal key" : "Not mapped - same as on the Base layer",
            "Key or shortcut", "Switch layer", "Switch keymap", "Mouse key", "Play macro", "Disabled - does nothing"])
        if id = "" {
            c.title.Value := layerName " layer"
            c.desc.Value := "Click a key on the keyboard above to see or change what it does on this layer."
            c.type.Enabled := false
            this._ShowGroup("")
            return
        }
        c.type.Enabled := true
        a := this._Get(this.layer, id)
        c.title.Value := Keys.ById[id].name "    -    " layerName " layer"
        type := a = "" ? "" : a["type"]
        c.type.Choose(this._Index(this.TypeValues, type))
        this._ShowGroup(type)
        this._FillFields(a)
        this._UpdateDesc()
    }

    static _ShowGroup(type) {
        for name, ctrls in this.groups
            for ctrl in ctrls
                ctrl.Visible := name = type
    }

    static _FillFields(a) {
        c := this.c
        if a = ""
            return
        switch a["type"] {
            case "key":
                key := a.Get("key", "")
                c.key.Choose(Keys.OutById.Has(key) ? this._OutIndex(key) : 0)
                for i, m in Keys.Modifiers
                    c.mods[i].Value := this._Index(a.Get("mods", []), m) > 0
                secs := []
                for s in Actions.SecondaryChoices()
                    secs.Push(s[1])
                c.secondary.Choose(Max(1, this._Index(secs, a.Get("secondary", ""))))
            case "layer":
                c.layerPick.Choose(Max(1, this._Index(Actions.Layers, a["layer"]) - 1))
                modes := []
                for m in Actions.Modes
                    modes.Push(m[1])
                c.mode.Choose(Max(1, this._Index(modes, a.Get("mode", "hold"))))
            case "keymap":
                c.keymapPick.Choose(Config.KeymapIndex(this.cfg, a["keymap"]))
            case "mouse":
                acts := []
                for m in Actions.MouseActions
                    acts.Push(m[1])
                c.mouse.Choose(Max(1, this._Index(acts, a["action"])))
            case "macro":
                this._RefreshMacroList()
                for m in this.cfg["macros"]
                    if m["name"] == a["macro"]
                        c.macro.Choose(A_Index)
        }
    }

    static _UpdateDesc() {
        a := this._Get(this.layer, this.sel)
        if a != ""
            text := Actions.Describe(a, this.cfg) "."
        else if this.layer = "base"
            text := "Works as a normal key."
        else {
            b := this._Get("base", this.sel)
            text := "Not mapped on this layer, so it does what it does on the Base layer: "
                . (b = "" ? "works as a normal key." : StrLower(SubStr(Actions.Describe(b, this.cfg), 1, 1)) SubStr(Actions.Describe(b, this.cfg), 2) ".")
        }
        this.c.desc.Value := text
    }

    static _UpdateStatus() {
        if !this.gui
            return
        this.c.status.Value := this.dirty ? "Unsaved changes. Save & Apply to start using them." : "All changes saved."
        this.gui.Title := "KeyAgent" (this.dirty ? " *" : "")
    }

    ; ---------------------------------------------------------------- editing a key

    static _OnTypeChange(*) {
        if this.sel = ""
            return
        this.gui.Opt("+OwnDialogs")
        type := this.TypeValues[this.c.type.Value]
        old := this._Get(this.layer, this.sel)
        if old != "" && old["type"] = type
            return
        a := this._DefaultAction(type)
        if type = "macro" && a = "" {
            MsgBox("There are no macros yet. Create one with Macros… first.", "KeyAgent", "Iconi")
            this._ShowAction()
            return
        }
        this._Set(this.sel, a)
        this._ShowGroup(type)
        this._FillFields(a)
        this._UpdateDesc()
    }

    static _DefaultAction(type) {
        switch type {
            case "key":
                return Map("type", "key", "key", this.sel)
            case "layer":
                return Map("type", "layer", "layer", "mod", "mode", "holdAndDoubleTapToggle")
            case "keymap":
                for km in this.cfg["keymaps"]
                    if km["abbreviation"] != this.abbr
                        return Map("type", "keymap", "keymap", km["abbreviation"])
                return Map("type", "keymap", "keymap", this.abbr)
            case "mouse":
                return Map("type", "mouse", "action", "moveUp")
            case "macro":
                return this.cfg["macros"].Length ? Map("type", "macro", "macro", this.cfg["macros"][1]["name"]) : ""
            case "none":
                return Map("type", "none")
        }
        return ""
    }

    static _OnFieldChange(*) {
        if this.sel = ""
            return
        a := this._FromFields()
        if a = ""
            return
        this._Set(this.sel, a)
        this._UpdateDesc()
    }

    static _FromFields() {
        c := this.c
        switch this.TypeValues[c.type.Value] {
            case "key":
                a := Map("type", "key", "key", c.key.Value ? Keys.Out[c.key.Value].id : "")
                mods := []
                for i, m in Keys.Modifiers
                    if c.mods[i].Value
                        mods.Push(m)
                if mods.Length
                    a["mods"] := mods
                if (sec := Actions.SecondaryChoices()[Max(1, c.secondary.Value)][1]) != ""
                    a["secondary"] := sec
                return a
            case "layer":
                return Map("type", "layer", "layer", Actions.Layers[Max(1, c.layerPick.Value) + 1],
                    "mode", Actions.Modes[Max(1, c.mode.Value)][1])
            case "keymap":
                return Map("type", "keymap", "keymap", this.cfg["keymaps"][Max(1, c.keymapPick.Value)]["abbreviation"])
            case "mouse":
                return Map("type", "mouse", "action", Actions.MouseActions[Max(1, c.mouse.Value)][1])
            case "macro":
                return c.macro.Value ? Map("type", "macro", "macro", this.cfg["macros"][c.macro.Value]["name"]) : ""
            case "none":
                return Map("type", "none")
        }
        return ""
    }

    static _Set(id, a) {
        layerMap := this._Layers()[this.layer]
        if a = "" {
            if layerMap.Has(id)
                layerMap.Delete(id)
        } else
            layerMap[id] := a
        this._SetDirty()
        this._RefreshTile(id)
    }

    static _SetDirty() {
        this.dirty := true
        this._UpdateStatus()
    }

    static _CaptureOutput(*) {
        r := KeyCapture.Capture(this.gui, "Press the key or shortcut this key should send.", true)
        if !r
            return
        c := this.c
        c.key.Choose(Keys.OutById.Has(r.key) ? this._OutIndex(r.key) : 0)
        for i, m in Keys.Modifiers
            c.mods[i].Value := this._Index(r.mods, m) > 0
        this._OnFieldChange()
    }

    static _FindKey(*) {
        r := KeyCapture.Capture(this.gui, "Press the key you want to edit.", false)
        if r && this.tiles.Has(r.key)
            this._Select(r.key)
    }

    static _OnLayerPick(layer, *) {
        this.layer := layer
        this.c.layers[this._Index(Actions.Layers, layer)].Value := 1
        this._RefreshTiles()
        this._ShowAction()
    }

    ; ---------------------------------------------------------------- keymaps

    static _OnKeymapPick(*) {
        this.abbr := this.cfg["keymaps"][this.c.keymap.Value]["abbreviation"]
        this.c.makeDefault.Enabled := this.abbr != this.cfg["defaultKeymap"]
        this._RefreshTiles()
        this._ShowAction()
    }

    static _NewKeymap(*) {
        r := Dialogs.Form(this.gui, "New keymap", [{name: "name", label: "Name", value: "My keymap"}])
        if !r || Trim(r["name"]) = ""
            return
        km := Config.NewKeymap(Trim(r["name"]), Config.UniqueAbbr(this.cfg, r["name"]))
        for id, a in this._Layers()["base"]          ; keep the layer keys so its layers are reachable
            if a["type"] = "layer"
                km["layers"]["base"][id] := Config.Clone(a)
        this._AddKeymap(km)
    }

    static _DuplicateKeymap(*) {
        cur := Config.Keymap(this.cfg, this.abbr)
        r := Dialogs.Form(this.gui, "Duplicate keymap", [{name: "name", label: "Name of the copy", value: "Copy of " cur["name"]}])
        if !r || Trim(r["name"]) = ""
            return
        km := Config.Clone(cur)
        km["name"] := Trim(r["name"]), km["abbreviation"] := Config.UniqueAbbr(this.cfg, r["name"])
        this._AddKeymap(km)
    }

    static _AddKeymap(km) {
        this.cfg["keymaps"].Push(km)
        this.abbr := km["abbreviation"]
        this._SetDirty()
        this._RefreshKeymaps()
        this._RefreshTiles()
        this._ShowAction()
    }

    static _RenameKeymap(*) {
        this.gui.Opt("+OwnDialogs")
        cur := Config.Keymap(this.cfg, this.abbr)
        r := Dialogs.Form(this.gui, "Rename keymap", [{name: "name", label: "Name", value: cur["name"]},
            {name: "abbr", label: "Abbreviation (used by keymap-switch keys)", value: cur["abbreviation"]}])
        if !r
            return
        name := Trim(r["name"]), abbr := Trim(r["abbr"]), old := cur["abbreviation"]
        if abbr = "" || (abbr != old && Config.Keymap(this.cfg, abbr)) {
            MsgBox("The abbreviation must be unique and not empty.", "KeyAgent", "Icon!")
            return
        }
        if name != ""
            cur["name"] := name
        if abbr != old {
            cur["abbreviation"] := abbr
            for km in this.cfg["keymaps"]
                for lname, layerMap in km["layers"]
                    for id, a in layerMap
                        if a["type"] = "keymap" && a["keymap"] = old
                            a["keymap"] := abbr
            if this.cfg["defaultKeymap"] = old
                this.cfg["defaultKeymap"] := abbr
            this.abbr := abbr
        }
        this._SetDirty()
        this._RefreshKeymaps()
        this._RefreshTiles()
        this._ShowAction()
    }

    static _DeleteKeymap(*) {
        this.gui.Opt("+OwnDialogs")
        kms := this.cfg["keymaps"]
        if kms.Length = 1 {
            MsgBox("This is the only keymap, so it can't be deleted.", "KeyAgent", "Iconi")
            return
        }
        cur := Config.Keymap(this.cfg, this.abbr), old := this.abbr
        if MsgBox("Delete the keymap `"" cur["name"] "`"?`n`nKeys that switch to it are removed too.", "KeyAgent", "YesNo Icon?") != "Yes"
            return
        i := Config.KeymapIndex(this.cfg, old)
        kms.RemoveAt(i)
        for km in kms
            for lname, layerMap in km["layers"] {
                gone := []
                for id, a in layerMap
                    if a["type"] = "keymap" && a["keymap"] = old
                        gone.Push(id)
                for id in gone
                    layerMap.Delete(id)
            }
        if this.cfg["defaultKeymap"] = old
            this.cfg["defaultKeymap"] := kms[1]["abbreviation"]
        this.abbr := kms[Min(i, kms.Length)]["abbreviation"]
        this._SetDirty()
        this._RefreshKeymaps()
        this._RefreshTiles()
        this._ShowAction()
    }

    static _MakeDefault(*) {
        this.cfg["defaultKeymap"] := this.abbr
        this._SetDirty()
        this._RefreshKeymaps()
    }

    ; ---------------------------------------------------------------- other windows

    static _OpenMacros(*) => MacroEditor.Open(this.gui)
    static _OpenSettings(*) => SettingsDialog.Open(this.gui)
    static _OpenImport(*) => ImportDialog.Open(this.gui)

    ; Called by the macro editor / import after they changed the working copy.
    static Changed() {
        this._SetDirty()
        this._RefreshMacroList()
        this._RefreshKeymaps()
        this._RefreshTiles()
        this._ShowAction()
    }

    ; ---------------------------------------------------------------- save / close

    static _Save(*) {
        this.gui.Opt("+OwnDialogs")
        try
            App.SaveAndApply(this.cfg)
        catch as e {
            MsgBox("Couldn't save " App.configPath ":`n`n" e.Message, "KeyAgent", "Icon!")
            return false
        }
        this.dirty := false
        this._UpdateStatus()
        this.c.status.Value := "Saved. Your changes are active now."
        return true
    }

    static _Revert(*) {
        this.gui.Opt("+OwnDialogs")
        if this.dirty && MsgBox("Throw away your unsaved changes?", "KeyAgent", "YesNo Icon?") != "Yes"
            return
        this._Reset(Config.Clone(App.cfg))
    }

    static _Reset(cfg) {
        this.cfg := cfg
        this.dirty := false
        if !Config.Keymap(this.cfg, this.abbr)
            this.abbr := this.cfg["defaultKeymap"]
        this._RefreshKeymaps()
        this._RefreshMacroList()
        this._RefreshTiles()
        this._ShowAction()
        this._UpdateStatus()
    }

    static _OnClose(*) {
        this.gui.Opt("+OwnDialogs")
        if this.dirty {
            r := MsgBox("Save your changes before closing?", "KeyAgent", "YesNoCancel Icon?")
            if r = "Cancel" || (r = "Yes" && !this._Save())
                return true
        }
        MacroEditor.Close()
        this.gui.Destroy()
        this.gui := "", this.c := "", this.tiles := Map(), this.groups := Map(), this.sel := ""
        return true
    }

    ; ---------------------------------------------------------------- helpers

    static _Index(arr, value) {
        for x in arr
            if x == value
                return A_Index
        return 0
    }

    static _OutIndex(id) {
        for item in Keys.Out
            if item.id == id
                return A_Index
        return 0
    }
}
