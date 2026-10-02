; MouseKeys.ahk - moving, scrolling and clicking the mouse from the keyboard, using the UHK's
; kinetic model: movement starts at the initial speed and accelerates towards the base speed,
; or towards the accelerated / decelerated speed while those keys are held.
;
; Speeds are in UHK Agent units. Pointer: 1 unit = 25 pixels/second. Scrolling: 1 unit = half
; a wheel notch per second. Acceleration is in units per second.

class MouseKeys {
    static settings := ""             ; the config's settings Map
    static held := Map()              ; action -> number of keys holding it
    static move := {active: false, speed: 0, x: 0.0, y: 0.0}
    static scroll := {active: false, speed: 0, x: 0.0, y: 0.0}
    static last := 0
    static running := false
    static _tickFn := ""

    static Configure(settings) => this.settings := settings

    static Press(action) {
        if btn := this._Button(action)
            Click(btn " Down")
        else {
            this.held[action] := this.held.Get(action, 0) + 1
            this._Start()
        }
    }

    static Release(action) {
        if btn := this._Button(action)
            Click(btn " Up")
        else if (n := this.held.Get(action, 0) - 1) > 0
            this.held[action] := n
        else if this.held.Has(action)
            this.held.Delete(action)
    }

    static _Button(action) {
        static buttons := Map("leftClick", "Left", "rightClick", "Right", "middleClick", "Middle",
            "button4", "X1", "button5", "X2")
        return buttons.Get(action, "")
    }

    static _Start() {
        if this.running
            return
        this.running := true
        this.last := A_TickCount
        DllCall("winmm\timeBeginPeriod", "UInt", 1)     ; smoother 10 ms ticks while moving
        if !this._tickFn
            this._tickFn := ObjBindMethod(this, "_Tick")
        SetTimer(this._tickFn, 10)
    }

    static _Stop() {
        SetTimer(this._tickFn, 0)
        DllCall("winmm\timeEndPeriod", "UInt", 1)
        this.running := false
        this.move := {active: false, speed: 0, x: 0.0, y: 0.0}
        this.scroll := {active: false, speed: 0, x: 0.0, y: 0.0}
    }

    static _Tick() {
        now := A_TickCount
        dt := Min(Max(now - this.last, 1), 50)
        this.last := now
        h := this.held, s := this.settings

        if h.Has("moveUp") || h.Has("moveDown") || h.Has("moveLeft") || h.Has("moveRight") {
            dx := h.Has("moveRight") - h.Has("moveLeft")
            dy := h.Has("moveDown") - h.Has("moveUp")
            dist := this._Speed(this.move, s["mouseMove"], dt) * 25 * dt / 1000
            if dx && dy && s["diagonalSpeedCompensation"]
                dist *= 0.70710678
            this.move.x += dx * dist, this.move.y += dy * dist
            ix := Integer(this.move.x), iy := Integer(this.move.y)
            this.move.x -= ix, this.move.y -= iy
            if ix || iy
                MouseMove(ix, iy, 0, "R")
        } else
            this.move := {active: false, speed: 0, x: 0.0, y: 0.0}

        if h.Has("scrollUp") || h.Has("scrollDown") || h.Has("scrollLeft") || h.Has("scrollRight") {
            sx := h.Has("scrollRight") - h.Has("scrollLeft")
            sy := h.Has("scrollUp") - h.Has("scrollDown")
            units := this._Speed(this.scroll, s["mouseScroll"], dt) / 2 * 120 * dt / 1000
            if sx && sy && s["diagonalSpeedCompensation"]
                units *= 0.70710678
            this.scroll.x += sx * units, this.scroll.y += sy * units
            stepSize := s["smoothScroll"] ? 15 : 120      ; 120 = one wheel notch
            if n := Integer(this.scroll.y / stepSize) {
                this.scroll.y -= n * stepSize
                DllCall("mouse_event", "UInt", 0x0800, "Int", 0, "Int", 0, "Int", n * stepSize, "UPtr", 0)
            }
            if n := Integer(this.scroll.x / stepSize) {
                this.scroll.x -= n * stepSize
                DllCall("mouse_event", "UInt", 0x1000, "Int", 0, "Int", 0, "Int", n * stepSize, "UPtr", 0)
            }
        } else
            this.scroll := {active: false, speed: 0, x: 0.0, y: 0.0}

        if !this.move.active && !this.scroll.active
            this._Stop()
    }

    ; Current speed of a kinetic state: starts at the initial speed, then approaches the target.
    static _Speed(state, p, dt) {
        target := this.held.Has("decelerate") ? p["deceleratedSpeed"]
            : this.held.Has("accelerate") ? p["acceleratedSpeed"] : p["baseSpeed"]
        if !state.active {
            state.active := true
            state.speed := p["initialSpeed"]
        } else if state.speed < target
            state.speed := Min(target, state.speed + p["acceleration"] * dt / 1000)
        else if state.speed > target
            state.speed := Max(target, state.speed - p["acceleration"] * dt / 1000)
        return state.speed
    }
}
