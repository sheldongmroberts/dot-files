; Dialogs.ahk - the editor's smaller windows: a simple form, key capture, the macro editor,
; settings, and importing from UHK Agent.

class Dialogs {
    ; Shows g as a modal dialog of owner and returns once it's closed.
    static RunModal(g, owner, showOptions := "") {
        hwnd := g.Hwnd
        owner.Opt("+Disabled")
        g.Show(showOptions)
        WinWaitClose("ahk_id " hwnd)
        owner.Opt("-Disabled")
        try WinActivate("ahk_id " owner.Hwnd)
    }

    ; fields: [{name, label, value}] -> Map(name -> text), or "" if cancelled.
    static Form(owner, title, fields) {
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", title)
        g.SetFont("s9", "Segoe UI")
        edits := Map()
        for f in fields {
            g.Add("Text", "xm w320", f.label)
            edits[f.name] := g.Add("Edit", "xm w320", f.value)
        }
        state := {result: ""}
        submit(*) {
            r := Map()
            for name, e in edits
                r[name] := e.Value
            state.result := r
            g.Destroy()
        }
        g.Add("Button", "xm y+14 w90 Default", "OK").OnEvent("Click", submit)
        g.Add("Button", "x+8 w90", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        this.RunModal(g, owner)
        return state.result
    }

    static On(target, ctrl, event, method, args*) {
        ctrl.OnEvent(event, ObjBindMethod(target, method, args*))
        return ctrl
    }

    static ModLabel(m) => StrReplace(StrReplace(Keys.Name(m), "Left ", "L "), "Right ", "R ")

    static Num(edit, default) {
        v := Trim(edit.Value)
        return IsInteger(v) ? Integer(v) : IsNumber(v) ? Float(v) : default
    }
}

; ---------------------------------------------------------------------------------------------

class KeyCapture {
    ; Waits for a key press, with remapping paused. With combos, modifiers held together with the
    ; key are returned too, and a modifier pressed and released on its own counts as the key.
    ; Returns {key: id, mods: [...]}, or "" if cancelled or timed out.
    static Capture(owner, prompt, combos := false) {
        App.SetPaused("capture", true)
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox +AlwaysOnTop", "KeyAgent")
        g.SetFont("s10", "Segoe UI")
        g.Add("Text", "w340 Center", prompt)
        g.SetFont("s8")
        g.Add("Text", "w340 Center c666C75", "Remapping is paused while KeyAgent listens (up to 10 seconds).")
        g.SetFont("s9")
        cancel := g.Add("Button", "x140 w80", "Cancel")

        ih := InputHook("L0 T10")
        ih.KeyOpt("{All}", "ES")
        state := {held: [], lastMod: "", result: ""}
        if combos {
            ih.KeyOpt("{LCtrl}{RCtrl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}", "-E +N")
            ih.OnKeyDown := ModDown
            ih.OnKeyUp := ModUp
        }
        ModDown(ih, vk, sc) {
            id := KeyCapture._Id(vk, sc)
            if !Editor._Index(state.held, id)
                state.held.Push(id)
            state.lastMod := id
        }
        ModUp(ih, vk, sc) {
            id := KeyCapture._Id(vk, sc)
            if id = state.lastMod {                       ; released without another key
                state.result := {key: id, mods: []}
                ih.Stop()
            }
            if i := Editor._Index(state.held, id)
                state.held.RemoveAt(i)
        }
        cancel.OnEvent("Click", (*) => ih.Stop())
        g.OnEvent("Close", (*) => ih.Stop())
        owner.Opt("+Disabled")
        g.Show()
        ih.Start()
        ih.Wait()
        g.Destroy()
        owner.Opt("-Disabled")
        try WinActivate("ahk_id " owner.Hwnd)
        App.SetPaused("capture", false)
        if state.result
            return state.result
        if ih.EndReason != "EndKey"
            return ""
        key := this._Name(ih.EndKey)
        mods := []
        for m in state.held
            if m != key
                mods.Push(m)
        return {key: key, mods: mods}
    }

    static _Id(vk, sc) => this._Name(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))

    ; AHK key name -> KeyAgent key id (physical key by scan code, else the name itself).
    static _Name(name) {
        id := Keys.FromSc(GetKeySC(name))
        return id != "" ? id : name
    }
}

; ---------------------------------------------------------------------------------------------

class MacroEditor {
    static gui := ""
    static c := ""
    static groups := Map()
    static StepTypes := [
        ["text", "", "Type text"], ["key", "tap", "Tap a key / shortcut"], ["key", "press", "Press a key (hold it down)"],
        ["key", "release", "Release a key"], ["delay", "", "Wait"], ["mouse", "tap", "Click a mouse button"],
        ["mouse", "press", "Press a mouse button"], ["mouse", "release", "Release a mouse button"],
        ["move", "", "Move the pointer"], ["scroll", "", "Scroll"], ["run", "", "Run a program / open a URL or file"]]

    static Items => Editor.cfg["macros"]

    static Open(owner) {
        if this.gui {
            this.gui.Show()
            return
        }
        g := Gui("+Owner" owner.Hwnd " -MaximizeBox -MinimizeBox", "KeyAgent - Macros")
        g.SetFont("s9", "Segoe UI")
        g.BackColor := "F3F4F6"
        g.OnEvent("Close", ObjBindMethod(this, "Close"))
        g.OnEvent("Escape", ObjBindMethod(this, "Close"))
        this.gui := g
        c := this.c := {}
        on(ctrl, event, method, args*) => Dialogs.On(MacroEditor, ctrl, event, method, args*)

        g.Add("Text", "x12 y12", "Macros")
        c.list := on(g.Add("ListBox", "x12 y32 w210 h300"), "Change", "_OnPick")
        on(g.Add("Button", "x12 y338 w102 h26", "New…"), "Click", "_New")
        on(g.Add("Button", "x120 y338 w102 h26", "Rename…"), "Click", "_Rename")
        on(g.Add("Button", "x12 y368 w102 h26", "Duplicate"), "Click", "_Duplicate")
        on(g.Add("Button", "x120 y368 w102 h26", "Delete"), "Click", "_Delete")

        c.title := g.Add("Text", "x236 y12 w512", "Steps")
        c.steps := on(g.Add("ListView", "x236 y32 w512 h190 -Multi NoSortHdr Grid", ["#", "Step"]), "ItemSelect", "_OnStepPick")
        c.steps.ModifyCol(1, 34), c.steps.ModifyCol(2, 455)
        on(g.Add("Button", "x236 y228 w90 h26", "Move up"), "Click", "_Move", -1)
        on(g.Add("Button", "x+6 yp w90 h26", "Move down"), "Click", "_Move", 1)
        on(g.Add("Button", "x+6 yp w100 h26", "Remove step"), "Click", "_RemoveStep")

        g.Add("GroupBox", "x236 y262 w512 h178", "Step")
        g.Add("Text", "x250 y286 w46", "Type")
        names := []
        for t in this.StepTypes
            names.Push(t[3])
        c.type := on(g.Add("DropDownList", "x300 y282 w260 R12", names), "Change", "_ShowFields")
        grp := Map()
        grp["text"] := [c.text := g.Add("Edit", "x300 y316 w432 h64 Multi WantReturn")]
        keyNames := []
        for item in Keys.Out
            keyNames.Push(item.name)
        grp["key"] := [g.Add("Text", "x250 y320 w46", "Key"),
            c.key := g.Add("DropDownList", "x300 y316 w230 R24", keyNames),
            on(g.Add("Button", "x+6 yp-1 w90 h25", "Capture…"), "Click", "_Capture")]
        c.mods := []
        for i, m in Keys.Modifiers {                     ; left modifiers, then right ones below
            x := 300 + Mod(i - 1, 4) * 80, y := i <= 4 ? 350 : 372
            c.mods.Push(cb := g.Add("Checkbox", Format("x{} y{} w76", x, y), Dialogs.ModLabel(m)))
            grp["key"].Push(cb)
        }
        c.ms := g.Add("Edit", "x300 y316 w80 Number")
        grp["delay"] := [c.ms, g.Add("UpDown", "Range0-600000 0x80", 100), g.Add("Text", "x+8 y320", "milliseconds")]
        grp["mouse"] := [g.Add("Text", "x250 y320 w46", "Button"),
            c.button := g.Add("DropDownList", "x300 y316 w160", ["Left", "Right", "Middle", "X1 (back)", "X2 (forward)"])]
        grp["xy"] := [g.Add("Text", "x300 y320", "X"), c.x := g.Add("Edit", "x316 y316 w60"),
            g.Add("Text", "x390 y320", "Y"), c.y := g.Add("Edit", "x406 y316 w60"),
            c.xyHint := g.Add("Text", "x480 y320 w250 c666C75")]
        grp["run"] := [c.target := g.Add("Edit", "x300 y316 w340"),
            on(g.Add("Button", "x+6 yp-1 w80 h25", "Browse…"), "Click", "_Browse")]
        this.groups := grp
        on(g.Add("Button", "x250 y402 w110 h26", "Add step"), "Click", "_AddStep")
        on(g.Add("Button", "x+6 yp w160 h26", "Replace selected step"), "Click", "_ReplaceStep")

        on(g.Add("Button", "x12 y452 w210 h28", "Test (plays in 3 seconds)"), "Click", "_Test")
        on(g.Add("Button", "x668 y452 w80 h28", "Close"), "Click", "Close")
        c.type.Choose(1)
        this._ShowFields()
        this._RefreshList(1)
        g.Show("w760 h494")
    }

    static Close(*) {
        if this.gui {
            this.gui.Destroy()
            this.gui := "", this.c := "", this.groups := Map()
        }
        return true
    }

    static _Current() => this.c.list.Value ? this.Items[this.c.list.Value] : ""

    static _RefreshList(select := 0) {
        names := []
        for m in this.Items
            names.Push(m["name"])
        this.c.list.Delete(), this.c.list.Add(names)
        if select && select <= names.Length
            this.c.list.Choose(select)
        this._OnPick()
    }

    static _OnPick(*) {
        m := this._Current()
        this.c.title.Value := m ? "Steps of `"" m["name"] "`"" : "Create a macro with New…, then add its steps."
        this._FillSteps()
    }

    static _FillSteps(selectRow := 0) {
        lv := this.c.steps
        lv.Delete()
        if m := this._Current()
            for s in m["steps"]
                lv.Add(, A_Index, Macros.Describe(s))
        if selectRow
            lv.Modify(selectRow, "Select Focus Vis")
    }

    static _Changed() {
        Editor._SetDirty()
        Editor._RefreshMacroList()
    }

    ; ---- macros

    static _AskName(title, value) {
        r := Dialogs.Form(this.gui, title, [{name: "name", label: "Macro name", value: value}])
        if !r
            return ""
        name := Trim(r["name"])
        if name = "" || Config.Macro(Editor.cfg, name) {
            this.gui.Opt("+OwnDialogs")
            MsgBox("Macro names must be unique and not empty.", "KeyAgent", "Icon!")
            return ""
        }
        return name
    }

    static _New(*) {
        if (name := this._AskName("New macro", "My macro")) = ""
            return
        this.Items.Push(Map("name", name, "steps", []))
        this._Changed()
        this._RefreshList(this.Items.Length)
    }

    static _Duplicate(*) {
        if !(m := this._Current())
            return
        if (name := this._AskName("Duplicate macro", "Copy of " m["name"])) = ""
            return
        copy := Config.Clone(m), copy["name"] := name
        this.Items.Push(copy)
        this._Changed()
        this._RefreshList(this.Items.Length)
    }

    static _Rename(*) {
        if !(m := this._Current())
            return
        old := m["name"]
        if (name := this._AskName("Rename macro", old)) = ""
            return
        m["name"] := name
        for km in Editor.cfg["keymaps"]                 ; keys that play it follow the new name
            for lname, layerMap in km["layers"]
                for id, a in layerMap
                    if a["type"] = "macro" && a["macro"] == old
                        a["macro"] := name
        this._Changed()
        this._RefreshList(this.c.list.Value)
    }

    static _Delete(*) {
        if !(m := this._Current())
            return
        this.gui.Opt("+OwnDialogs")
        if MsgBox("Delete the macro `"" m["name"] "`"?`n`nKeys that play it are cleared too.", "KeyAgent", "YesNo Icon?") != "Yes"
            return
        for km in Editor.cfg["keymaps"]
            for lname, layerMap in km["layers"] {
                gone := []
                for id, a in layerMap
                    if a["type"] = "macro" && a["macro"] == m["name"]
                        gone.Push(id)
                for id in gone
                    layerMap.Delete(id)
            }
        i := this.c.list.Value
        this.Items.RemoveAt(i)
        this._Changed()
        Editor._RefreshTiles()
        this._RefreshList(Min(i, this.Items.Length))
    }

    static _Test(*) {
        if !(m := this._Current())
            return
        ToolTip("Playing `"" m["name"] "`" in 3 seconds - click where it should type.")
        SetTimer(() => (ToolTip(), Macros.PlayObject(Config.Clone(m))), -3000)
    }

    ; ---- steps

    static _ShowFields(*) {
        t := this.StepTypes[this.c.type.Value][1]
        show := t = "move" || t = "scroll" ? "xy" : t
        for name, ctrls in this.groups
            for ctrl in ctrls
                ctrl.Visible := name = show
        if show = "xy"
            this.c.xyHint.Value := t = "move" ? "pixels (+X right, +Y down)" : "wheel notches (+Y up, +X right)"
    }

    static _OnStepPick(lv, row, selected) {
        if !selected || !(m := this._Current())
            return
        s := m["steps"][row], c := this.c
        for i, t in this.StepTypes
            if t[1] = s["type"] && (t[2] = "" || t[2] = s.Get("mode", "tap"))
                c.type.Choose(i)
        this._ShowFields()
        switch s["type"] {
            case "text": c.text.Value := StrReplace(s["text"], "`n", "`r`n")
            case "key":
                c.key.Choose(Keys.OutById.Has(s.Get("key", "")) ? Editor._OutIndex(s["key"]) : 0)
                for i, mod in Keys.Modifiers
                    c.mods[i].Value := Editor._Index(s.Get("mods", []), mod) > 0
            case "delay": c.ms.Value := s["ms"]
            case "mouse": c.button.Choose(Max(1, Editor._Index(Macros.Buttons, s.Get("button", "Left"))))
            case "move", "scroll": c.x.Value := s.Get("x", 0), c.y.Value := s.Get("y", 0)
            case "run": c.target.Value := s["target"]
        }
    }

    static _StepFromFields() {
        c := this.c, t := this.StepTypes[c.type.Value]
        this.gui.Opt("+OwnDialogs")
        switch t[1] {
            case "text":
                if c.text.Value = "" {
                    MsgBox("Enter the text to type.", "KeyAgent", "Icon!")
                    return ""
                }
                return Map("type", "text", "text", StrReplace(c.text.Value, "`r`n", "`n"))
            case "key":
                s := Map("type", "key", "mode", t[2], "key", c.key.Value ? Keys.Out[c.key.Value].id : "")
                mods := []
                for i, m in Keys.Modifiers
                    if c.mods[i].Value
                        mods.Push(m)
                if mods.Length
                    s["mods"] := mods
                if s["key"] = "" && !mods.Length {
                    MsgBox("Pick a key (or at least one modifier).", "KeyAgent", "Icon!")
                    return ""
                }
                return s
            case "delay":
                return Map("type", "delay", "ms", Dialogs.Num(c.ms, 100))
            case "mouse":
                return Map("type", "mouse", "mode", t[2], "button", Macros.Buttons[Max(1, c.button.Value)])
            case "move", "scroll":
                return Map("type", t[1], "x", Dialogs.Num(c.x, 0), "y", Dialogs.Num(c.y, 0))
            case "run":
                if Trim(c.target.Value) = "" {
                    MsgBox("Enter a program, file or URL.", "KeyAgent", "Icon!")
                    return ""
                }
                return Map("type", "run", "target", Trim(c.target.Value))
        }
        return ""
    }

    static _AddStep(*) {
        if !(m := this._Current()) {
            this._New()
            if !(m := this._Current())
                return
        }
        if !(s := this._StepFromFields())
            return
        row := this.c.steps.GetNext()
        pos := row ? row + 1 : m["steps"].Length + 1
        m["steps"].InsertAt(pos, s)
        this._Changed()
        this._FillSteps(pos)
    }

    static _ReplaceStep(*) {
        if !(m := this._Current()) || !(row := this.c.steps.GetNext())
            return
        if !(s := this._StepFromFields())
            return
        m["steps"][row] := s
        this._Changed()
        this._FillSteps(row)
    }

    static _RemoveStep(*) {
        if !(m := this._Current()) || !(row := this.c.steps.GetNext())
            return
        m["steps"].RemoveAt(row)
        this._Changed()
        this._FillSteps(Min(row, m["steps"].Length))
    }

    static _Move(dir, *) {
        if !(m := this._Current()) || !(row := this.c.steps.GetNext())
            return
        to := row + dir
        if to < 1 || to > m["steps"].Length
            return
        s := m["steps"].RemoveAt(row)
        m["steps"].InsertAt(to, s)
        this._Changed()
        this._FillSteps(to)
    }

    static _Capture(*) {
        r := KeyCapture.Capture(this.gui, "Press the key or shortcut for this step.", true)
        if !r
            return
        this.c.key.Choose(Keys.OutById.Has(r.key) ? Editor._OutIndex(r.key) : 0)
        for i, m in Keys.Modifiers
            this.c.mods[i].Value := Editor._Index(r.mods, m) > 0
    }

    static _Browse(*) {
        this.gui.Opt("+OwnDialogs")
        if f := FileSelect(1, , "Program or file to open")
            this.c.target.Value := f
    }
}

; ---------------------------------------------------------------------------------------------

class SettingsDialog {
    static Open(owner) {
        s := Editor.cfg["settings"]
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", "KeyAgent - Settings")
        g.SetFont("s9", "Segoe UI")
        g.BackColor := "F3F4F6"
        c := {}

        g.Add("GroupBox", "x12 y10 w560 h58", "Layers")
        g.Add("Text", "x26 y36", "Double-tap a layer key within")
        c.doubleTap := g.Add("Edit", "x+6 y32 w60 Number", s["doubleTapLayerTimeout"])
        g.Add("Text", "x+6 y36", "ms to lock its layer (tap it again to unlock).")

        g.Add("GroupBox", "x12 y76 w560 h176", "Tap/hold keys (keys with a `"When held`" role)")
        g.Add("Text", "x26 y102 w80", "Strategy")
        c.strategy := g.Add("DropDownList", "x110 y98 w440", ["Simple - the hold role starts as soon as another key is pressed",
            "Advanced - timeout, release trigger and double-tap options below"])
        c.strategy.Choose(s["secondaryRoleStrategy"] = "Advanced" ? 2 : 1)
        adv := []
        adv.Push(g.Add("Text", "x26 y136", "After"))
        adv.Push(c.timeout := g.Add("Edit", "x+6 y132 w60 Number", s["secondaryRoleTimeout"]))
        adv.Push(g.Add("Text", "x+6 y136", "ms held on its own, use the"))
        adv.Push(c.timeoutAction := g.Add("DropDownList", "x+6 y132 w110", ["hold role", "tap role"]))
        c.timeoutAction.Choose(s["secondaryRoleTimeoutAction"] = "Primary" ? 2 : 1)
        adv.Push(g.Add("Text", "x26 y168", "Another key triggers the hold role on its"))
        adv.Push(c.trigger := g.Add("DropDownList", "x+6 y164 w250", ["press", "release (fewer mistakes when typing fast)"]))
        c.trigger.Choose(s["secondaryRoleTrigger"] = "Release" ? 2 : 1)
        adv.Push(c.doubletap := g.Add("Checkbox", "x26 y198 Checked" s["secondaryRoleDoubletapToPrimary"],
            "Tap then hold within"))
        adv.Push(c.doubletapMs := g.Add("Edit", "x+4 y194 w60 Number", s["secondaryRoleDoubletapTimeout"]))
        adv.Push(g.Add("Text", "x+6 y198", "ms repeats the tap role (e.g. a held letter)"))
        c.byMouse := g.Add("Checkbox", "x26 y226 Checked" s["secondaryRoleTriggerByMouse"],
            "A mouse click while holding a tap/hold key uses its hold role (e.g. Ctrl+click)")
        toggleAdv(*) {
            for ctrl in adv
                ctrl.Enabled := c.strategy.Value = 2
        }
        c.strategy.OnEvent("Change", toggleAdv)
        toggleAdv()

        g.Add("GroupBox", "x12 y260 w560 h132", "Mouse keys (UHK Agent units: pointer x25 px/s, scroll x0.5 notches/s)")
        fields := ["initialSpeed", "baseSpeed", "acceleratedSpeed", "deceleratedSpeed", "acceleration"]
        for i, h in ["Initial", "Base", "Fast", "Slow", "Acceleration"]
            g.Add("Text", Format("x{} y282 w76 Center", 120 + (i - 1) * 84), h)
        c.speeds := Map()
        for row, kind in ["mouseMove", "mouseScroll"] {
            y := 302 + (row - 1) * 30
            g.Add("Text", Format("x26 y{} w90", y + 4), row = 1 ? "Pointer" : "Scrolling")
            for i, f in fields
                c.speeds[kind "." f] := g.Add("Edit", Format("x{} y{} w76 Number", 120 + (i - 1) * 84, y), s[kind][f])
        }
        c.diagonal := g.Add("Checkbox", "x26 y366 Checked" s["diagonalSpeedCompensation"], "Same speed diagonally")
        c.smooth := g.Add("Checkbox", "x+20 yp Checked" s["smoothScroll"], "Smooth scrolling (some older apps ignore partial wheel steps)")

        g.Add("GroupBox", "x12 y400 w560 h134", "General")
        c.osdLocked := g.Add("Checkbox", "x26 y422 Checked" s["osdLocked"], "Show an on-screen indicator while a layer is locked, and on keymap switches")
        c.osdHeld := g.Add("Checkbox", "x26 y444 Checked" s["osdHeld"], "Also show it while a layer key is held down")
        c.pauseUhk := g.Add("Checkbox", "x26 y466 Checked" s["pauseWhenUhkConnected"], "Pause KeyAgent while a UHK is connected (it remaps itself)")
        c.dongle := g.Add("Checkbox", "x46 y488 Checked" s["uhkDongleCounts"], "Count a plugged-in UHK dongle as a connected UHK")
        c.startup := g.Add("Checkbox", "x26 y510 Checked" (FileExist(App.StartupLink) ? 1 : 0), "Start KeyAgent when Windows starts (applies right away)")

        ok(*) {
            s["doubleTapLayerTimeout"] := Dialogs.Num(c.doubleTap, 250)
            s["secondaryRoleStrategy"] := c.strategy.Value = 2 ? "Advanced" : "Simple"
            s["secondaryRoleTimeout"] := Dialogs.Num(c.timeout, 350)
            s["secondaryRoleTimeoutAction"] := c.timeoutAction.Value = 2 ? "Primary" : "Secondary"
            s["secondaryRoleTrigger"] := c.trigger.Value = 2 ? "Release" : "Press"
            s["secondaryRoleDoubletapToPrimary"] := c.doubletap.Value
            s["secondaryRoleDoubletapTimeout"] := Dialogs.Num(c.doubletapMs, 200)
            s["secondaryRoleTriggerByMouse"] := c.byMouse.Value
            for key, edit in c.speeds {
                parts := StrSplit(key, ".")
                s[parts[1]][parts[2]] := Dialogs.Num(edit, s[parts[1]][parts[2]])
            }
            s["diagonalSpeedCompensation"] := c.diagonal.Value
            s["smoothScroll"] := c.smooth.Value
            s["osdLocked"] := c.osdLocked.Value
            s["osdHeld"] := c.osdHeld.Value
            s["pauseWhenUhkConnected"] := c.pauseUhk.Value
            s["uhkDongleCounts"] := c.dongle.Value
            if c.startup.Value != (FileExist(App.StartupLink) ? 1 : 0)
                App.SetStartup(c.startup.Value)
            Editor._SetDirty()
            g.Destroy()
        }
        g.Add("Button", "x392 y546 w86 h28 Default", "OK").OnEvent("Click", ok)
        g.Add("Button", "x486 y546 w86 h28", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        Dialogs.RunModal(g, owner, "w584 h586")
    }
}

; ---------------------------------------------------------------------------------------------

class ImportDialog {
    static Open(owner) {
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", "KeyAgent - Import from UHK Agent")
        g.SetFont("s9", "Segoe UI")
        g.BackColor := "F3F4F6"
        c := {}, state := {uhk: ""}

        g.Add("Text", "x12 y12", "UHK Agent configuration file (UHK Agent keeps it in %APPDATA%\uhk-agent)")
        found := UhkImport.FindConfigs()
        c.path := g.Add("Edit", "x12 y32 w470", found.Length ? found[1] : "")
        g.Add("Button", "x+6 yp-1 w80 h25", "Browse…").OnEvent("Click", browse)

        g.Add("Text", "x12 y68", "Keymaps to import")
        c.list := g.Add("ListView", "x12 y88 w556 h150 Checked -Multi NoSortHdr", ["Keymap", "Abbr.", ""])
        c.list.ModifyCol(1, 300), c.list.ModifyCol(2, 60), c.list.ModifyCol(3, 160)

        g.Add("Text", "x12 y250 w556", "A normal keyboard has no Mod, Fn or Mouse keys. Which key should act as them here?")
        physical := ["(none)"]
        for k in Keys.List
            physical.Push(k.name)
        c.triggers := Map()
        defaults := UhkImport.DefaultTriggers()
        for i, layer in ["mod", "mouse", "fn", "fn2"] {
            x := 12 + (i - 1) * 140
            g.Add("Text", Format("x{} y276 w130", x), Actions.LayerNames[layer] " key")
            ddl := g.Add("DropDownList", Format("x{} y294 w130 R20", x), physical)
            pick := 1
            for j, k in Keys.List
                if k.id = defaults[layer]
                    pick := j + 1
            ddl.Choose(pick)
            c.triggers[layer] := ddl
        }
        c.macros := g.Add("Checkbox", "x12 y334 Checked", "Import macros")
        c.settings := g.Add("Checkbox", "x+20 yp Checked", "Import mouse-key speeds and tap/hold timing")
        c.add := g.Add("Radio", "x12 y362 Checked", "Add to my keymaps and macros (replacing ones with the same abbreviation / name)")
        c.replace := g.Add("Radio", "x12 y384", "Replace all my keymaps and macros")
        g.Add("Button", "x388 y416 w86 h28 Default", "Import").OnEvent("Click", doImport)
        g.Add("Button", "x482 y416 w86 h28", "Cancel").OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        c.path.OnEvent("Change", (*) => load())

        browse(*) {
            g.Opt("+OwnDialogs")
            dir := FileExist(A_AppData "\uhk-agent") ? A_AppData "\uhk-agent" : ""
            if f := FileSelect(1, dir, "UHK Agent configuration", "JSON files (*.json)") {
                c.path.Value := f
                load()
            }
        }
        load() {
            c.list.Delete()
            state.uhk := ""
            if !FileExist(c.path.Value)
                return
            try
                state.uhk := UhkImport.Load(c.path.Value)
            catch
                return
            for km in UhkImport.ListKeymaps(state.uhk) {
                row := c.list.Add(km.isDefault ? "Check" : "", km.name, km.abbreviation, km.isDefault ? "your default keymap" : "")
                if km.isDefault
                    c.list.Modify(row, "Vis")
            }
        }
        doImport(*) {
            g.Opt("+OwnDialogs")
            if !state.uhk {
                MsgBox("Pick a UHK Agent configuration file first.", "KeyAgent", "Icon!")
                return
            }
            abbrs := [], row := 0
            while row := c.list.GetNext(row, "Checked")
                abbrs.Push(c.list.GetText(row, 2))
            if !abbrs.Length {
                MsgBox("Tick at least one keymap.", "KeyAgent", "Icon!")
                return
            }
            triggers := Map()
            for layer, ddl in c.triggers
                triggers[layer] := ddl.Value > 1 ? Keys.List[ddl.Value - 1].id : ""
            res := UhkImport.Convert(state.uhk, {keymaps: abbrs, triggers: triggers,
                macros: c.macros.Value, settings: c.settings.Value})
            ImportDialog._Merge(res, c.replace.Value)
            notes := ""
            for line in res.log
                notes .= "`n  - " line
            MsgBox(Format("Imported {} keymap(s) and {} macro(s).{}`n`nReview the result, then Save & Apply.",
                res.keymaps.Length, res.macros.Length, notes ? "`n`nNot carried over:" notes : ""), "KeyAgent", "Iconi")
            g.Destroy()
        }
        load()
        Dialogs.RunModal(g, owner, "w580 h456")
    }

    static _Merge(res, replaceAll) {
        cfg := Editor.cfg
        if replaceAll {
            cfg["keymaps"] := res.keymaps
            if res.macros.Length
                cfg["macros"] := res.macros
        } else {
            for km in res.keymaps
                if i := Config.KeymapIndex(cfg, km["abbreviation"])
                    cfg["keymaps"][i] := km
                else
                    cfg["keymaps"].Push(km)
            for m in res.macros {
                done := false
                for j, existing in cfg["macros"]
                    if existing["name"] == m["name"] {
                        cfg["macros"][j] := m, done := true
                        break
                    }
                if !done
                    cfg["macros"].Push(m)
            }
        }
        for k, v in res.settings
            if v is Map
                for k2, v2 in v
                    cfg["settings"][k][k2] := v2
            else
                cfg["settings"][k] := v
        if !Config.Keymap(cfg, cfg["defaultKeymap"])
            cfg["defaultKeymap"] := cfg["keymaps"][1]["abbreviation"]
        Editor.abbr := res.keymaps[1]["abbreviation"]
        Editor.Changed()
    }
}
