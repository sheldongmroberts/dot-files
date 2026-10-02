; Engine.ahk - the remapping engine: layers, tap/hold keys, keymaps.
;
; How it hooks the keyboard
; -------------------------
; Every physical key gets a "*key" and a "*key up" hotkey whose HotIf filter (_Filter) is
; called by AutoHotkey's keyboard hook, in event order, before the key reaches Windows. The
; filter runs the whole state machine and returns whether KeyAgent takes the event (true) or
; lets it through untouched (false). The filter never sends input itself - sending from inside
; the hook's callback stalls the hook - it queues the output, and the hotkey handler (_Flush)
; sends the queue right afterwards. While output is queued, keys that would otherwise pass
; through are queued as well, so a plain key can never overtake earlier remapped output.
;
; As on the UHK, the action a key performs is decided when it goes down: releasing it undoes
; exactly what the press did, even if the layer changed in between.

class Engine {
    static cfg := ""
    static keymap := ""
    static held := []                ; layers held by keys, oldest first: {key, layer}
    static toggled := ""             ; layer locked by a toggle key or a double tap
    static pressed := Map()          ; key id -> state object describing what its press did
    static native := Map()           ; key id -> tick of the last down passed through to Windows
    static pending := ""             ; tap/hold key that hasn't decided its role yet
    static lastLayerTap := ""        ; {key, layer, time}: first tap of a possible double tap
    static lastPrimaryTap := Map()   ; key id -> tick a tap/hold key was last tapped
    static modRefs := Map()          ; modifier -> number of active actions holding it down
    static queue := []               ; output waiting to be sent: [method, arg]
    static out := SendOutput         ; output backend; the tests swap in a recorder
    static Now := (*) => A_TickCount
    static OnChange := ""            ; callback(kind) after the layer or keymap changes
    static watchdog := true          ; release keys whose key-up event got lost
    static _hk := Map()
    static _upCheck := ""
    static _clicks := Map()           ; mouse buttons whose press KeyAgent took
    static _mouseInstalled := false
    static _watching := false
    static _changeKind := ""
    static _flushFn := "", _timeoutFn := "", _watchFn := "", _notifyFn := ""

    ; ---- setup ----

    static Install() {
        this._Bind()
        this._hk.CaseSense := "Off"
        HotIf(ObjBindMethod(this, "_Filter"))
        for k in Keys.List {
            Hotkey("*" k.hk, this._flushFn)
            Hotkey("*" k.hk " up", this._flushFn)
            this._hk["*" k.hk] := {id: k.id, up: false, mouse: false}
            this._hk["*" k.hk " up"] := {id: k.id, up: true, mouse: false}
        }
        HotIf()
    }

    ; Mouse buttons are only hooked when a tap/hold key could need them (so that holding a
    ; tap/hold key and clicking applies its hold role, e.g. Ctrl+click).
    static InstallMouse() {
        if this._mouseInstalled
            return
        this._mouseInstalled := true
        HotIf(ObjBindMethod(this, "_Filter"))
        for btn in ["LButton", "RButton", "MButton", "XButton1", "XButton2"] {
            Hotkey("*" btn, this._flushFn)
            Hotkey("*" btn " up", this._flushFn)
            this._hk["*" btn] := {id: btn, up: false, mouse: true}
            this._hk["*" btn " up"] := {id: btn, up: true, mouse: true}
        }
        HotIf()
    }

    static _Bind() {
        if !this._flushFn {
            this._flushFn := ObjBindMethod(this, "_Flush")
            this._timeoutFn := ObjBindMethod(this, "_PendingTimeout")
            this._watchFn := ObjBindMethod(this, "_Watchdog")
            this._notifyFn := ObjBindMethod(this, "_Notify")
        }
    }

    ; Applies a (new) configuration. Keys that are currently down keep doing what they did.
    static Load(cfg) {
        crit := A_IsCritical        ; Critical lasts for the caller's whole thread: restore it after
        Critical
        try {
            this._Bind()
            this.cfg := cfg
            abbr := this.keymap ? this.keymap["abbreviation"] : cfg["defaultKeymap"]
            km := Config.Keymap(cfg, abbr)
            this.keymap := km ? km : Config.Keymap(cfg, cfg["defaultKeymap"])
            if this.toggled != "" && !this.keymap["layers"][this.toggled].Count
                this.toggled := ""
            if this._hk.Count && this.NeedsMouseHook()      ; only once the key hotkeys exist
                this.InstallMouse()
            this._Changed("load")
        } finally {
            Critical(crit)
        }
    }

    static NeedsMouseHook() {
        if !this.cfg["settings"]["secondaryRoleTriggerByMouse"]
            return false
        for km in this.cfg["keymaps"]
            for name, layer in km["layers"]
                for id, a in layer
                    if a["type"] = "key" && a.Get("secondary", "") != ""
                        return true
        return false
    }

    ; ---- state for the UI ----

    static Layer() {
        if this.held.Length
            return this.held[this.held.Length].layer
        return this.toggled != "" ? this.toggled : "base"
    }

    static SwitchKeymap(abbr) {
        km := Config.Keymap(this.cfg, abbr)
        if !km
            return
        this.keymap := km
        this.toggled := ""
        this._Changed("keymap")
    }

    ; Undoes everything KeyAgent is holding down (used before pausing and on exit).
    static ReleaseAll() {
        crit := A_IsCritical
        Critical
        try {
            if this.pending {
                this.pending := ""
                SetTimer(this._timeoutFn, 0)
            }
            ids := []
            for id in this.pressed
                ids.Push(id)
            for id in ids {
                st := this.pressed[id]
                this.pressed.Delete(id)
                this._Undo(id, st)
            }
            for m in this.modRefs
                this._Out("ModUp", m)
            for btn in this._clicks
                this._Out("Click", this._ClickName(btn) " Up")
            this.modRefs := Map(), this._clicks := Map(), this.native := Map()
            this.held := [], this.toggled := "", this.lastLayerTap := "", this._upCheck := ""
            this._Flush()
            this._Changed("layer")
        } finally {
            Critical(crit)
        }
    }

    ; ---- the hook side ----

    ; HotIf filter: called by the keyboard hook for every event on a registered key.
    static _Filter(hk) {
        Critical
        info := this._hk.Get(hk, 0)
        if !info
            return false
        if info.up && this._upCheck = info.id {
            ; After letting a key-down through, AHK immediately asks about the matching
            ; key-up hotkey too. That isn't a real event, so it must not change anything.
            this._upCheck := ""
            return false
        }
        this._upCheck := ""
        taken := this.Event(info.id, info.up, info.mouse)
        if !taken && !info.up
            this._upCheck := info.id
        if this.queue.Length
            SetTimer(this._flushFn, -1)      ; backup, normally the hotkey handler flushes first
        return taken
    }

    ; One key event. Returns true if KeyAgent takes it, false to let Windows have it.
    static Event(id, up, mouse := false) {
        if mouse
            return up ? this._MouseUp(id) : this._MouseDown(id)
        return up ? this._Up(id) : this._Down(id)
    }

    static _Down(id) {
        now := this.Now()
        if st := this.pressed.Get(id, 0) {              ; auto-repeat of a key we own
            if st.kind = "key" && st.send != ""
                this._Out("KeyDown", st.send)
            return true
        }
        if (t := this.native.Get(id, 0)) && now - t < 2000 {
            this.native[id] := now                       ; auto-repeat of a key we let through
            if !this.queue.Length
                return false
            this._Out("KeyDown", Keys.ById[id].send)
            return true
        }
        if p := this.pending {
            if this._HeldBack(id)
                return true                              ; auto-repeat while undecided
            if !Keys.ById[id].isMod || this._Resolve(id) != "" {
                if this._ReleaseTrigger() {
                    p.buffer.Push(id)                    ; decide once we see what comes first
                    return true
                }
                this._Decide(true)                       ; another key while held: hold role
            }
        }
        this._MarkLayersUsed()
        if this._Resolve(id) = "" && !this.queue.Length {
            this.native[id] := now
            return false
        }
        this._Press(id, this._Resolve(id), now)
        return true
    }

    static _Up(id) {
        if p := this.pending {
            if p.key = id {
                this._Decide(false, true)                ; released on its own: it was a tap
                return true
            }
            if this._HeldBack(id)
                this._Decide(true)                       ; pressed and released inside: hold
        }
        if st := this.pressed.Get(id, 0) {
            this.pressed.Delete(id)
            this._Undo(id, st)
            return true
        }
        if this.native.Has(id)
            this.native.Delete(id)
        if !this.queue.Length
            return false
        this._Out("KeyUp", Keys.ById[id].send)          ; keep order behind queued output
        return true
    }

    static _MouseDown(btn) {
        holdRole := this.pending && this.cfg["settings"]["secondaryRoleTriggerByMouse"]
        if !holdRole && !this.queue.Length
            return false
        if holdRole
            this._Decide(true)
        this._clicks[btn] := true
        this._Out("Click", this._ClickName(btn) " Down")
        return true
    }

    static _MouseUp(btn) {
        if !this._clicks.Has(btn)
            return false
        this._clicks.Delete(btn)
        this._Out("Click", this._ClickName(btn) " Up")
        return true
    }

    ; What the key does right now: an action Map, or "" for "behave like a normal key".
    static _Resolve(id) {
        layers := this.keymap["layers"]
        layer := this.Layer()
        if layer != "base" && layers[layer].Has(id)
            return layers[layer][id]
        return layers["base"].Get(id, "")
    }

    static _Press(id, a, now) {
        if a = "" {
            this._PressKey(id, Keys.ById[id].send, [])  ; a normal key, re-sent to keep order
        } else {
            switch a["type"] {
                case "key":
                    if a.Get("secondary", "") != "" && !this._DoubleTapPrimary(id, now) {
                        this.pending := {key: id, action: a, time: now, buffer: []}
                        if this._S("secondaryRoleStrategy") = "Advanced"
                            SetTimer(this._timeoutFn, -Max(1, this._S("secondaryRoleTimeout")))
                    } else
                        this._PressKeyAction(id, a)
                case "layer":
                    this._PressLayer(id, a, now)
                case "keymap":
                    this.pressed[id] := {kind: "none"}
                    this.SwitchKeymap(a["keymap"])
                case "mouse":
                    this.pressed[id] := {kind: "mouse", action: a["action"]}
                    this._Out("MouseDown", a["action"])
                case "macro":
                    this.pressed[id] := {kind: "none"}
                    this._Out("PlayMacro", a["macro"])
                default:
                    this.pressed[id] := {kind: "none"}
            }
        }
        this._StartWatchdog()
    }

    static _PressResolved(id, now) {
        this._MarkLayersUsed()
        this._Press(id, this._Resolve(id), now)
    }

    static _PressKeyAction(id, a) {
        key := a.Get("key", ""), mods := []
        if key != "" && Keys.IsModifier(key)
            mods.Push(key), key := ""
        for m in a.Get("mods", [])
            mods.Push(m)
        this._PressKey(id, key != "" ? Keys.SendName(key) : "", mods)
    }

    static _PressKey(id, send, mods) {
        for m in mods
            this._ModDown(m)
        if send != ""
            this._Out("KeyDown", send)
        this.pressed[id] := {kind: "key", send: send, mods: mods}
    }

    static _PressLayer(id, a, now) {
        layer := a["layer"], mode := a.Get("mode", "hold")
        if mode = "toggle" {
            this.toggled := this.toggled = layer ? "" : layer
            this.pressed[id] := {kind: "none"}
            this._Changed("layer")
            return
        }
        noTap := false
        if mode = "holdAndDoubleTapToggle" {
            t := this.lastLayerTap
            this.lastLayerTap := ""
            if this.toggled = layer {
                this.toggled := "", noTap := true        ; tapping a locked layer's key unlocks it
            } else if t && t.key = id && t.layer = layer && now - t.time <= this._S("doubleTapLayerTimeout") {
                this.toggled := layer                     ; second tap: lock the layer
                this.pressed[id] := {kind: "none"}
                this._Changed("layer")
                return
            }
        }
        this.held.Push({key: id, layer: layer})
        this.pressed[id] := {kind: "layer", layer: layer, mode: mode, time: now, used: false, noTap: noTap}
        this._Changed("layer")
    }

    static _Undo(id, st) {
        switch st.kind {
            case "key":
                if st.send != ""
                    this._Out("KeyUp", st.send)
                i := st.mods.Length
                while i
                    this._ModUp(st.mods[i--])
            case "mod":
                this._ModUp(st.mod)
            case "layer":
                loop this.held.Length
                    if this.held[A_Index].key = id {
                        this.held.RemoveAt(A_Index)
                        break
                    }
                if st.mode = "holdAndDoubleTapToggle" && !st.used && !st.noTap
                    this.lastLayerTap := {key: id, layer: st.layer, time: st.time}
                this._Changed("layer")
            case "mouse":
                this._Out("MouseUp", st.action)
        }
    }

    ; A tap/hold key has decided: secondary (hold) role, or primary (and maybe a quick tap).
    static _Decide(secondary, tap := false) {
        p := this.pending
        if !p
            return
        this.pending := ""
        if this._timeoutFn
            SetTimer(this._timeoutFn, 0)
        now := this.Now()
        if secondary {
            sec := p.action["secondary"]
            if Keys.IsModifier(sec) {
                this._ModDown(sec)
                this.pressed[p.key] := {kind: "mod", mod: sec}
            } else {
                this.held.Push({key: p.key, layer: sec})
                this.pressed[p.key] := {kind: "layer", layer: sec, mode: "hold", time: p.time, used: true, noTap: true}
                this._Changed("layer")
            }
        } else {
            this._PressKeyAction(p.key, p.action)
            if tap {
                st := this.pressed[p.key]
                this.pressed.Delete(p.key)
                this._Undo(p.key, st)
                this.lastPrimaryTap[p.key] := now
            }
        }
        if p.HasProp("seen") && this.pressed.Has(p.key)
            this.pressed[p.key].seen := p.seen
        for k in p.buffer
            this._PressResolved(k, now)
    }

    static _PendingTimeout() {
        Critical
        if this.pending {
            this._Decide(this._S("secondaryRoleTimeoutAction") != "Primary")
            this._Flush()
        }
    }

    static _DoubleTapPrimary(id, now) {
        if this._S("secondaryRoleStrategy") != "Advanced" || !this._S("secondaryRoleDoubletapToPrimary")
            return false
        t := this.lastPrimaryTap.Get(id, 0)
        return t && now - t <= this._S("secondaryRoleDoubletapTimeout")
    }

    static _ReleaseTrigger() => this._S("secondaryRoleStrategy") = "Advanced" && this._S("secondaryRoleTrigger") = "Release"

    static _HeldBack(id) {
        if !(p := this.pending)
            return false
        if p.key = id
            return true
        for k in p.buffer
            if k = id
                return true
        return false
    }

    static _MarkLayersUsed() {
        for h in this.held
            if st := this.pressed.Get(h.key, 0)
                st.used := true
    }

    static _ModDown(m) {
        n := this.modRefs.Get(m, 0)
        this.modRefs[m] := n + 1
        if !n
            this._Out("ModDown", m)
    }

    static _ModUp(m) {
        n := this.modRefs.Get(m, 0) - 1
        if n > 0 {
            this.modRefs[m] := n
            return
        }
        if this.modRefs.Has(m)
            this.modRefs.Delete(m)
        this._Out("ModUp", m)
    }

    static _ClickName(btn) => Map("LButton", "Left", "RButton", "Right", "MButton", "Middle",
        "XButton1", "X1", "XButton2", "X2")[btn]

    static _S(name) => this.cfg["settings"][name]

    ; ---- output ----

    static _Out(method, arg) => this.queue.Push([method, arg])

    ; Hotkey handler: sends whatever the filter queued. Also used directly by timers.
    static _Flush(*) {
        crit := A_IsCritical
        Critical
        while this.queue.Length {
            item := this.queue.RemoveAt(1)
            try this.out.%item[1]%(item[2])
        }
        Critical(crit)
    }

    static _Changed(kind) {
        this._changeKind := kind
        if this.OnChange && this._notifyFn
            SetTimer(this._notifyFn, -1)
    }

    static _Notify() {
        if this.OnChange
            this.OnChange.Call(this._changeKind)
    }

    ; ---- watchdog: if a key-up event never arrives (e.g. it was swallowed while another
    ; program held the keyboard), release the key once it's physically up. Keys only count once
    ; they have been seen physically down, so injected input (remote tools, tests) is left alone.

    static _StartWatchdog() {
        if this.watchdog && !this._watching && this._watchFn {
            this._watching := true
            SetTimer(this._watchFn, 300)
        }
    }

    static _Watchdog() {
        Critical
        stale := []
        if p := this.pending
            this._WatchCheck(p.key, p, stale)
        for id, st in this.pressed
            this._WatchCheck(id, st, stale)
        for id in stale
            this._Up(id)
        if stale.Length
            this._Flush()
        if !this.pending && !this.pressed.Count {
            SetTimer(this._watchFn, 0)
            this._watching := false
        }
    }

    static _WatchCheck(id, st, stale) {
        if this.out.IsDown(Keys.ById[id].hk)
            st.seen := true
        else if st.HasProp("seen")
            stale.Push(id)
    }
}

; The real output backend. Each method runs from _Flush, in queue order.
class SendOutput {
    static KeyDown(name) => Send("{Blind}{" name " DownR}")
    static KeyUp(name) => Send("{Blind}{" name " Up}")
    static ModDown(name) => Send("{Blind}{" name " DownR}")
    static ModUp(name) {
        if !GetKeyState(name, "P")                  ; the user may be holding it themselves
            Send("{Blind}{" name " Up}")
    }
    static Click(spec) => Click(spec)
    static MouseDown(action) => MouseKeys.Press(action)
    static MouseUp(action) => MouseKeys.Release(action)
    static PlayMacro(name) => Macros.Play(name)
    static IsDown(keyName) => GetKeyState(keyName, "P")
}
