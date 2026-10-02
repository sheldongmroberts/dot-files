; Macros.ahk - plays macros: sequences of text, keys, mouse actions and delays.
;
; A macro is {name: "...", steps: [...]} with these step shapes:
;   {type: "text",   text: "Hello`n"}                       types the text (newlines = Enter)
;   {type: "key",    mode: "tap" | "press" | "release", key: "l", mods: ["LCtrl"]}
;   {type: "delay",  ms: 100}
;   {type: "mouse",  mode: "tap" | "press" | "release", button: "Left" | "Right" | "Middle" | "X1" | "X2"}
;   {type: "move",   x: 10, y: -5}                          moves the pointer by x, y pixels
;   {type: "scroll", x: 0, y: 3}                            scrolls by wheel notches (y > 0 = up)
;   {type: "run",    target: "notepad.exe" | "https://..."} starts a program or opens a URL/file

class Macros {
    static list := []
    static running := Map()
    static Buttons := ["Left", "Right", "Middle", "X1", "X2"]

    static Configure(macros) => this.list := macros

    static Find(name) {
        for m in this.list
            if m["name"] == name
                return m
        return ""
    }

    ; Starts a macro in its own thread so keys keep working while it plays. A macro that is
    ; still playing isn't started a second time.
    static Play(name) {
        m := this.Find(name)
        if !m || this.running.Has(name)
            return
        this.running[name] := true
        SetTimer(ObjBindMethod(this, "_Run", name, m), -1)
    }

    ; Plays a macro object that isn't in the active config (the macro editor's Test button).
    static PlayObject(m) {
        if this.running.Has(m["name"])
            return
        this.running[m["name"]] := true
        SetTimer(ObjBindMethod(this, "_Run", m["name"], m), -1)
    }

    static _Run(name, m) {
        try {
            for step in m["steps"]
                this.Step(step)
        } catch as e {
            TrayTip("Macro `"" name "`" stopped: " e.Message, "KeyAgent", "Iconx")
        } finally {
            this.running.Delete(name)
        }
    }

    static Step(s) {
        switch s["type"] {
            case "text":
                SendText(s["text"])
            case "key":
                key := s.Get("key", ""), mode := s.Get("mode", "tap")
                send := key != "" ? Keys.SendName(key) : ""
                down := "", up := ""
                for m in s.Get("mods", [])
                    down .= "{" m " down}", up := "{" m " up}" up
                if mode = "press"
                    Send("{Blind}" down (send != "" ? "{" send " down}" : ""))
                else if mode = "release"
                    Send("{Blind}" (send != "" ? "{" send " up}" : "") up)
                else
                    Send(down (send != "" ? "{" send "}" : "") up)
            case "delay":
                Sleep(s["ms"])
            case "mouse":
                btn := s.Get("button", "Left"), mode := s.Get("mode", "tap")
                Click(btn (mode = "press" ? " Down" : mode = "release" ? " Up" : ""))
            case "move":
                MouseMove(s.Get("x", 0), s.Get("y", 0), 0, "R")
            case "scroll":
                if y := s.Get("y", 0)
                    DllCall("mouse_event", "UInt", 0x0800, "Int", 0, "Int", 0, "Int", Round(y * 120), "UPtr", 0)
                if x := s.Get("x", 0)
                    DllCall("mouse_event", "UInt", 0x1000, "Int", 0, "Int", 0, "Int", Round(x * 120), "UPtr", 0)
            case "run":
                Run(s["target"])
        }
    }

    ; One-line description of a step, for the macro editor.
    static Describe(s) {
        switch s["type"] {
            case "text":
                t := StrReplace(StrReplace(s["text"], "`r"), "`n", " ⏎ ")
                return "Type `"" (StrLen(t) > 60 ? SubStr(t, 1, 57) "..." : t) "`""
            case "key":
                mode := s.Get("mode", "tap")
                verb := mode = "press" ? "Press" : mode = "release" ? "Release" : "Tap"
                names := []
                for m in s.Get("mods", [])
                    names.Push(Keys.Name(m))
                if s.Get("key", "") != ""
                    names.Push(Keys.Name(s["key"]))
                return verb " " Actions._Join(names, " + ")
            case "delay":
                return "Wait " s["ms"] " ms"
            case "mouse":
                mode := s.Get("mode", "tap")
                verb := mode = "press" ? "Press" : mode = "release" ? "Release" : "Click"
                return verb " " s.Get("button", "Left") " mouse button"
            case "move":
                return "Move pointer by " s.Get("x", 0) ", " s.Get("y", 0) " px"
            case "scroll":
                return "Scroll " s.Get("x", 0) ", " s.Get("y", 0) " notches"
            case "run":
                return "Run " s["target"]
        }
        return s["type"]
    }
}
