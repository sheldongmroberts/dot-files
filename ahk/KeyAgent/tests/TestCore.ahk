#Requires AutoHotkey v2.0
#SingleInstance Off
; Unit tests for the JSON reader/writer, the remapping engine (with a recording output backend
; and a fake clock - no keyboard hook is installed) and the UHK Agent importer.
; Run:  AutoHotkey64.exe /ErrorStdOut tests\TestCore.ahk [path to a UHK Agent config]
; Results go to stdout and tests\out\TestCore.log.

#Include ..\lib\Json.ahk
#Include ..\lib\Keys.ahk
#Include ..\lib\Actions.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Engine.ahk
#Include ..\lib\MouseKeys.ahk
#Include ..\lib\Macros.ahk
#Include ..\lib\UhkImport.ahk

global Passed := 0, Failed := []
DirCreate(A_ScriptDir "\out")
global LogFile := A_ScriptDir "\out\TestCore.log"
try FileDelete(LogFile)
; Writes to stdout (when redirected) and to tests\TestCore.log.
Say(text) {
    try FileAppend(text, "*", "UTF-8")
    FileAppend(text, LogFile, "UTF-8")
}
OnError(ReportError)
ReportError(e, mode) {
    Say("ERROR: " e.Message " " e.Extra "`n  at " e.File ":" e.Line "`n" e.Stack "`n")
    ExitApp(2)
}
Keys.Init()

Check(cond, name) {
    global Passed
    if cond
        Passed++
    else
        Failed.Push(name)
}

Eq(actual, expected, name) {
    global Passed
    if actual == expected
        Passed++
    else
        Failed.Push(name "`n      expected: " expected "`n      actual:   " actual)
}

; ---------------------------------------------------------------- JSON
TestJson() {
    s := '{"a": [1, 2.5, -3e2, true, false, null], "b": {"c": "x\"y\\z\né😀"}, "d": []}'
    v := Json.Parse(s)
    Eq(v["a"][2], 2.5, "json float")
    Eq(v["a"][3], -300.0, "json exponent")
    Eq(v["a"][4], 1, "json true")
    Eq(v["a"][6], "", "json null")
    Eq(v["b"]["c"], 'x"y\z`né😀', "json escapes")
    Eq(v["d"].Length, 0, "json empty array")
    back := Json.Parse(Json.Dump(v))
    Eq(Json.Dump(back), Json.Dump(v), "json round trip")
    Eq(Json.Dump(Map("on", 1, "n", 1), Map("on", 1)), '{"n": 1, "on": true}', "json bool keys")
    try {
        Json.Parse('{"a": }')
        Check(false, "json rejects bad input")
    } catch
        Check(true, "json rejects bad input")
}

; ---------------------------------------------------------------- engine harness
class Rec {
    static log := []
    static KeyDown(n) => this.log.Push("v" n)
    static KeyUp(n) => this.log.Push("^" n)
    static ModDown(n) => this.log.Push("v" n)
    static ModUp(n) => this.log.Push("^" n)
    static Click(s) => this.log.Push("click:" s)
    static MouseDown(a) => this.log.Push("mouse:v" a)
    static MouseUp(a) => this.log.Push("mouse:^" a)
    static PlayMacro(n) => this.log.Push("macro:" n)
    static IsDown(k) => false
}

global Clock := 0

KeyAct(key, mods*) {
    a := Map("type", "key", "key", key)
    if mods.Length
        a["mods"] := mods
    return a
}
TapHold(key, secondary) => Map("type", "key", "key", key, "secondary", secondary)
LayerAct(layer, mode := "hold") => Map("type", "layer", "layer", layer, "mode", mode)

TestConfig(settings := "") {
    km := Config.NewKeymap("Test", "TST")
    b := km["layers"]["base"], m := km["layers"]["mod"], f := km["layers"]["fn"], ms := km["layers"]["mouse"]
    b["RAlt"] := LayerAct("mod", "holdAndDoubleTapToggle")
    b["CapsLock"] := LayerAct("mouse", "holdAndDoubleTapToggle")
    b["AppsKey"] := LayerAct("fn")
    b["F12"] := LayerAct("fn2", "toggle")
    b["f"] := TapHold("f", "LCtrl")
    b["Space"] := TapHold("Space", "mod")
    m["j"] := KeyAct("Left"), m["l"] := KeyAct("Right"), m["i"] := KeyAct("Up")
    m["w"] := KeyAct("PgUp", "LCtrl"), m["e"] := KeyAct("t", "LCtrl")
    m["a"] := KeyAct("LWin"), m["x"] := Map("type", "none"), m["m"] := Map("type", "macro", "macro", "hello")
    f["2"] := Map("type", "keymap", "keymap", "COL")
    ms["i"] := Map("type", "mouse", "action", "moveUp")
    km["layers"]["fn2"]["j"] := KeyAct("Down")
    col := Config.NewKeymap("Colemak", "COL")
    col["layers"]["base"]["e"] := KeyAct("f")
    col["layers"]["base"]["AppsKey"] := LayerAct("fn")
    col["layers"]["fn"]["1"] := Map("type", "keymap", "keymap", "TST")
    cfg := Config.Normalize(Map("keymaps", [km, col], "macros", [], "defaultKeymap", "TST"))
    if settings
        for k, v in settings
            cfg["settings"][k] := v
    return cfg
}

Reset(settings := "") {
    global Clock := 1000
    Engine.out := Rec, Engine.watchdog := false, Engine.Now := (*) => Clock
    Engine.keymap := "", Engine.held := [], Engine.toggled := "", Engine.pressed := Map()
    Engine.native := Map(), Engine.pending := "", Engine.lastLayerTap := "", Engine.lastPrimaryTap := Map()
    Engine.modRefs := Map(), Engine.queue := []
    Engine.Load(TestConfig(settings))
    Rec.log := []
}

; Simulates one key event the way the hook delivers it. Keys the engine lets through are
; logged as "native" because they reach Windows immediately; then the handler flushes.
Ev(id, up, flush := true) {
    taken := Engine.Event(id, up)
    if !taken
        Rec.log.Push("native" (up ? "^" : "v") id)
    if flush
        Engine._Flush()
    return taken
}
D(id, flush := true) => Ev(id, false, flush)
U(id, flush := true) => Ev(id, true, flush)
Tap(id) => (D(id), U(id))
Log() {
    s := ""
    for x in Rec.log
        s .= (A_Index > 1 ? " " : "") x
    Rec.log := []
    return s
}
At(t) {
    global Clock := t
}

TestEngine() {
    Reset()
    Tap("a")
    Eq(Log(), "nativeva native^a", "plain key passes through")

    D("RAlt"), D("j"), U("j"), U("RAlt")
    Eq(Log(), "vLeft ^Left", "hold Mod + J = Left")
    Eq(Engine.Layer(), "base", "layer released")
    Tap("j")
    Eq(Log(), "nativevj native^j", "J native again after Mod released")

    D("RAlt"), D("j"), U("RAlt"), D("j"), U("j")
    Eq(Log(), "vLeft vLeft ^Left", "action fixed at press, repeats after layer released")

    D("j"), D("RAlt"), At(1100), D("j"), U("j"), U("RAlt")
    Eq(Log(), "nativevj nativevj native^j", "key held from base stays native when layer comes on")

    Reset()
    D("RAlt"), D("w"), D("w"), U("w"), U("RAlt")
    Eq(Log(), "vLCtrl vPgUp vPgUp ^PgUp ^LCtrl", "shortcut with auto-repeat")

    D("RAlt"), D("w"), D("e"), U("w"), U("e"), U("RAlt")
    Eq(Log(), "vLCtrl vPgUp vSC014 ^PgUp ^SC014 ^LCtrl", "shared modifier released once, last")

    D("RAlt"), D("a"), U("RAlt"), D("e"), U("e"), U("a")
    Eq(Log(), "vLWin nativeve native^e ^LWin", "modifier action outlives its layer")

    D("RAlt"), Tap("x"), Tap("q"), U("RAlt")
    Eq(Log(), "nativevq native^q", "none blocks, unassigned falls through to base")

    D("RAlt"), Tap("m"), U("RAlt")
    Eq(Log(), "macro:hello", "macro key")

    ; double tap to lock
    Reset()
    At(1000), D("RAlt"), At(1050), U("RAlt"), At(1150), D("RAlt"), At(1200), U("RAlt")
    Eq(Engine.Layer(), "mod", "double tap locks layer")
    Tap("j")
    Eq(Log(), "vLeft ^Left", "locked layer active")
    At(2000), D("RAlt")
    Eq(Engine.Layer(), "mod", "unlock press still holds the layer")
    U("RAlt")
    Eq(Engine.Layer(), "base", "tap unlocks")
    At(2100), Tap("RAlt")
    Eq(Engine.Layer(), "base", "unlock tap doesn't start a double tap")

    Reset()
    At(1000), Tap("RAlt"), At(1400), D("RAlt"), U("RAlt")
    Eq(Engine.Layer(), "base", "slow double tap doesn't lock")
    At(2000), D("RAlt"), Tap("j"), U("RAlt"), At(2100), D("RAlt"), U("RAlt")
    Eq(Engine.Layer(), "base", "layer key used with another key isn't a tap")
    Log()

    Tap("F12")
    Eq(Engine.Layer(), "fn2", "toggle on")
    Tap("j")
    Eq(Log(), "vDown ^Down", "toggled layer")
    At(5000), D("RAlt"), Tap("j"), U("RAlt")
    Eq(Log(), "vLeft ^Left", "held layer beats toggled layer")
    Tap("F12")
    Eq(Engine.Layer(), "base", "toggle off")

    ; tap/hold (secondary role), Simple strategy
    Reset()
    D("f")
    Eq(Log(), "", "tap/hold key waits")
    U("f")
    Eq(Log(), "vSC021 ^SC021", "tap/hold tapped = primary")
    D("f"), D("j"), U("j"), U("f")
    Eq(Log(), "vLCtrl vSC024 ^SC024 ^LCtrl", "tap/hold + other key = Ctrl+J")
    D("f"), D("LShift"), D("j"), U("j"), U("LShift"), U("f")
    Eq(Log(), "nativevLShift vLCtrl vSC024 ^SC024 native^LShift ^LCtrl", "modifier doesn't decide the role")
    D("Space"), D("j"), U("j"), U("Space")
    Eq(Log(), "vLeft ^Left", "Space held = Mod layer")
    Tap("Space")
    Eq(Log(), "vSpace ^Space", "Space tapped")
    D("f"), D("f"), D("f"), U("f")
    Eq(Log(), "vSC021 ^SC021", "auto-repeat while undecided is ignored")

    ; Advanced strategy, Release trigger
    Reset(Map("secondaryRoleStrategy", "Advanced", "secondaryRoleTrigger", "Release"))
    D("f"), D("j"), U("f"), U("j")
    Eq(Log(), "vSC021 ^SC021 vSC024 ^SC024", "release trigger: rolled keys stay letters")
    D("f"), D("j"), U("j"), U("f")
    Eq(Log(), "vLCtrl vSC024 ^SC024 ^LCtrl", "release trigger: key inside the hold = Ctrl+J")

    ; Advanced strategy, timeout
    Reset(Map("secondaryRoleStrategy", "Advanced", "secondaryRoleTimeoutAction", "Secondary"))
    D("f"), Engine._PendingTimeout(), D("j"), U("j"), U("f")
    Eq(Log(), "vLCtrl nativevj native^j ^LCtrl", "timeout picks the hold role")
    Reset(Map("secondaryRoleStrategy", "Advanced", "secondaryRoleTimeoutAction", "Primary"))
    D("f"), Engine._PendingTimeout(), D("f"), U("f")
    Eq(Log(), "vSC021 vSC021 ^SC021", "timeout as primary holds the key")

    ; Advanced strategy, double tap = primary
    Reset(Map("secondaryRoleStrategy", "Advanced", "secondaryRoleDoubletapToPrimary", true))
    At(1000), Tap("f"), At(1100), D("f"), D("f"), U("f")
    Eq(Log(), "vSC021 ^SC021 vSC021 vSC021 ^SC021", "double tap repeats the letter")
    At(3000), D("f"), D("j"), U("j"), U("f")
    Eq(Log(), "vLCtrl vSC024 ^SC024 ^LCtrl", "later hold is the hold role again")

    ; keymaps, mouse
    Reset()
    D("AppsKey"), Tap("2"), U("AppsKey")
    Eq(Engine.keymap["abbreviation"], "COL", "Fn+2 switches keymap")
    Tap("e")
    Eq(Log(), "vSC021 ^SC021", "Colemak E types F")
    D("AppsKey"), Tap("1"), U("AppsKey")
    Eq(Engine.keymap["abbreviation"], "TST", "switch back")
    Log()
    D("CapsLock"), D("i"), U("i"), U("CapsLock")
    Eq(Log(), "mouse:vmoveUp mouse:^moveUp", "mouse layer")

    ; ordering: while output is queued, a plain key is queued behind it
    Reset()
    D("RAlt"), D("j", false), U("j", false), U("RAlt", false)
    Check(D("k", false), "plain key intercepted while output queued")
    Engine._Flush()
    U("k")
    Eq(Log(), "vLeft ^Left vSC025 ^SC025", "queued output keeps order")

    ; ReleaseAll
    Reset()
    D("RAlt"), D("w"), Log()
    Engine.ReleaseAll()
    Eq(Log(), "^PgUp ^LCtrl", "release all")
    Eq(Engine.Layer(), "base", "release all resets layers")
    U("w"), U("RAlt")
    Eq(Log(), "native^w native^RAlt", "keys released after ReleaseAll pass through")
}

; ---------------------------------------------------------------- importer
TestImport(path) {
    t0 := A_TickCount
    uhk := UhkImport.Load(path)
    parseMs := A_TickCount - t0
    Check(parseMs < 5000, "UHK config parses in under 5 s (took " parseMs " ms)")
    res := UhkImport.Convert(uhk, {keymaps: ["QWR"], triggers: UhkImport.DefaultTriggers(), macros: true, settings: true})
    Eq(res.keymaps.Length, 1, "one keymap imported")
    km := res.keymaps[1], lay := km["layers"]
    Desc(layer, id) => lay[layer].Has(id) ? Actions.Describe(lay[layer][id]) : "-"
    Eq(Desc("base", "CapsLock"), "Switches to the Mouse layer: hold, or double-tap to lock", "CapsLock = Mouse")
    Eq(Desc("base", "RAlt"), "Switches to the Mod layer: hold, or double-tap to lock", "RAlt = Mod")
    Eq(lay["base"].Count, 2, "base layer only has the layer keys")
    for id, want in Map("i", "Up Arrow", "j", "Left Arrow", "k", "Down Arrow", "l", "Right Arrow",
        "u", "Home", "o", "End", "y", "Page Up", "h", "Page Down", "p", "Delete", "7", "F7", "=", "F12",
        "1", "F1", "``", "Escape", "q", "Escape", ";", "Backspace", "/", "Menu (Apps key)",
        "Backspace", "Delete", "[", "Print Screen")
        Eq(Desc("mod", id), "Sends " want, "mod " id)
    Eq(Desc("mod", "w"), "Sends Left Ctrl + Page Up", "mod w")
    Eq(Desc("mod", "e"), "Sends Left Ctrl + T", "mod e")
    Eq(Desc("mod", "d"), "Sends Left Alt + Tab", "mod d")
    Eq(Desc("mod", "a"), "Holds Left Win", "mod a")
    Eq(Desc("mod", "RAlt"), "-", "Mod key itself not repeated on mod layer")
    for id, want in Map("i", "Move pointer up", "j", "Move pointer left", "y", "Scroll up",
        "h", "Scroll down", "Space", "Left button", "RAlt", "Right button")
        Eq(Desc("mouse", id), "Mouse: " want, "mouse " id)
    Eq(Desc("fn", "u"), "Sends Media: Play / Pause", "fn u")
    Eq(Desc("fn", "i"), "Sends Volume up", "fn i")
    Eq(Desc("fn", "2"), "-", "keymap switch to non-imported keymap dropped")
    Eq(res.macros.Length, 3, "3 macros")
    Eq(Macros.Describe(res.macros[1]["steps"][1]), "Tap Left Ctrl + L", "macro 1 step 1")
    Eq(res.settings["doubleTapLayerTimeout"], 250, "setting doubleTap")
    Eq(res.settings["mouseMove"]["deceleratedSpeed"], 12, "setting decelerated speed")
    log := ""
    for line in res.log
        log .= "`n      " line
    Say("  import notes:" log "`n")

    all := UhkImport.Convert(uhk, {keymaps: ["QWR", "COL", "DVO"], triggers: UhkImport.DefaultTriggers(), macros: true, settings: false})
    ByAbbr(abbr) {
        for km in all.keymaps
            if km["abbreviation"] = abbr
                return km["layers"]
    }
    col := ByAbbr("COL"), dvo := ByAbbr("DVO")
    Eq(col["base"].Has("e") ? Actions.Describe(col["base"]["e"]) : "-", "Sends F", "Colemak base E -> F")
    Eq(col["base"].Has("k") ? Actions.Describe(col["base"]["k"]) : "-", "Sends E", "Colemak base K -> E")
    Eq(col["base"].Has("Insert"), false, "non-letter base positions not remapped")
    Eq(dvo["base"].Has("e") ? Actions.Describe(dvo["base"]["e"]) : "-", "Sends . (period)", "Dvorak base E -> .")
    qwr := ByAbbr("QWR")
    Eq(qwr["fn"].Has("3") ? Actions.Describe(qwr["fn"]["3"]) : "-", "Switches to keymap COL", "fn 3 = Colemak when imported")
}

TestMouse() {
    s := Config.DefaultSettings(), p := s["mouseMove"]
    MouseKeys.Configure(s)
    MouseKeys.held := Map("moveUp", 1)
    st := {active: false, speed: 0, x: 0.0, y: 0.0}
    Eq(MouseKeys._Speed(st, p, 10), 4, "mouse starts at the initial speed")
    Eq(Round(MouseKeys._Speed(st, p, 100), 1), 10.8, "mouse accelerates (68 units/s)")
    loop 100
        MouseKeys._Speed(st, p, 50)
    Eq(st.speed, 32, "mouse levels off at the base speed")
    MouseKeys.held["accelerate"] := 1
    loop 100
        MouseKeys._Speed(st, p, 50)
    Eq(st.speed, 64, "accelerate key raises it to the fast speed")
    MouseKeys.held := Map("moveUp", 1, "decelerate", 1)
    loop 100
        MouseKeys._Speed(st, p, 50)
    Eq(st.speed, 12, "decelerate key slows it down")
    MouseKeys.held := Map()
}

TestJson()
TestMouse()
TestEngine()
uhkPath := A_Args.Length ? A_Args[1] : A_AppData "\uhk-agent\43627732.json"
if FileExist(uhkPath)
    TestImport(uhkPath)
else
    Say("  (skipping importer tests: " uhkPath " not found)`n")

report := Format("{} passed, {} failed`n", Passed, Failed.Length)
for f in Failed
    report .= "  FAIL " f "`n"
Say(report)
ExitApp(Failed.Length ? 1 : 0)
