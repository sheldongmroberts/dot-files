; Json.ahk - small JSON reader/writer used for KeyAgent's config and UHK Agent imports.
;
;   Json.Parse(text)            objects -> Map, arrays -> Array, true/false -> 1/0, null -> ""
;   Json.Dump(value, boolKeys)  Map -> object (keys come out sorted, as AHK Maps enumerate them)
;                               Values stored under a key listed in boolKeys are written as
;                               true/false, since AHK has no separate boolean type.

class Json {
    static Parse(text) {
        pos := 1
        value := Json._Value(&text, &pos)
        Json._SkipWs(&text, &pos)
        if pos <= StrLen(text)
            throw ValueError("JSON: unexpected text at position " pos)
        return value
    }

    static Dump(value, boolKeys := "", indent := "  ") {
        return Json._Dump(value, boolKeys ? boolKeys : Map(), indent, "", "")
    }

    ; ---- reader ----

    static _SkipWs(&s, &pos) {
        if RegExMatch(s, "\G[ \t\r\n]+", &m, pos)
            pos += m.Len
    }

    static _Value(&s, &pos) {
        Json._SkipWs(&s, &pos)
        ch := SubStr(s, pos, 1)
        if ch = "{" {
            obj := Map()
            pos++
            Json._SkipWs(&s, &pos)
            if SubStr(s, pos, 1) = "}" {
                pos++
                return obj
            }
            loop {
                Json._SkipWs(&s, &pos)
                if SubStr(s, pos, 1) != '"'
                    throw ValueError("JSON: expected a key at position " pos)
                key := Json._String(&s, &pos)
                Json._SkipWs(&s, &pos)
                if SubStr(s, pos, 1) != ":"
                    throw ValueError("JSON: expected ':' at position " pos)
                pos++
                obj[key] := Json._Value(&s, &pos)
                Json._SkipWs(&s, &pos)
                ch := SubStr(s, pos++, 1)
                if ch = "}"
                    return obj
                if ch != ","
                    throw ValueError("JSON: expected ',' or '}' at position " (pos - 1))
            }
        }
        if ch = "[" {
            arr := []
            pos++
            Json._SkipWs(&s, &pos)
            if SubStr(s, pos, 1) = "]" {
                pos++
                return arr
            }
            loop {
                arr.Push(Json._Value(&s, &pos))
                Json._SkipWs(&s, &pos)
                ch := SubStr(s, pos++, 1)
                if ch = "]"
                    return arr
                if ch != ","
                    throw ValueError("JSON: expected ',' or ']' at position " (pos - 1))
            }
        }
        if ch = '"'
            return Json._String(&s, &pos)
        if RegExMatch(s, "\G(?:true|false|null)", &m, pos) {
            pos += m.Len
            return m[0] == "true" ? 1 : m[0] == "false" ? 0 : ""
        }
        if RegExMatch(s, "\G-?\d+(\.\d+)?([eE][+-]?\d+)?", &m, pos) {
            pos += m.Len
            return (m[1] = "" && m[2] = "") ? Integer(m[0]) : Float(m[0])
        }
        throw ValueError("JSON: unexpected character at position " pos)
    }

    static _String(&s, &pos) {
        start := pos + 1
        q := InStr(s, '"', true, start)
        if !q
            throw ValueError("JSON: unterminated string at position " pos)
        raw := SubStr(s, start, q - start)
        if !InStr(raw, "\") {               ; fast path: no escapes
            pos := q + 1
            return raw
        }
        out := "", i := start
        loop {
            c := SubStr(s, i, 1)
            if c = ""
                throw ValueError("JSON: unterminated string at position " pos)
            if c = '"'
                break
            if c != "\" {
                RegExMatch(s, '\G[^"\\]+', &m, i)
                out .= m[0], i += m.Len
                continue
            }
            e := SubStr(s, i + 1, 1)
            switch e, true {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "b": out .= "`b"
                case "f": out .= "`f"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "u":
                    out .= Chr(Integer("0x" SubStr(s, i + 2, 4)))
                    i += 4
                default: throw ValueError("JSON: bad escape at position " i)
            }
            i += 2
        }
        pos := i + 1
        return out
    }

    ; ---- writer ----

    static _Dump(v, boolKeys, indent, pad, key) {
        if v is Map {
            if !v.Count
                return "{}"
            if Json._IsFlat(v) {
                line := ""
                for k, x in v
                    line .= (line = "" ? "" : ", ") Json._Quote(k) ": " Json._Dump(x, boolKeys, indent, pad, k)
                if StrLen(line) <= 110
                    return "{" line "}"
            }
            inner := pad indent, out := "{`n", n := 0
            for k, x in v
                out .= (n++ ? ",`n" : "") inner Json._Quote(k) ": " Json._Dump(x, boolKeys, indent, inner, k)
            return out "`n" pad "}"
        }
        if v is Array {
            if !v.Length
                return "[]"
            if Json._IsFlat(v) {
                line := ""
                for x in v
                    line .= (A_Index > 1 ? ", " : "") Json._Dump(x, boolKeys, indent, pad, "")
                if StrLen(line) <= 110
                    return "[" line "]"
            }
            inner := pad indent, out := "[`n"
            for x in v
                out .= (A_Index > 1 ? ",`n" : "") inner Json._Dump(x, boolKeys, indent, inner, "")
            return out "`n" pad "]"
        }
        if key != "" && boolKeys.Has(key)
            return v ? "true" : "false"
        if v is Number
            return String(v)
        return Json._Quote(v)
    }

    ; A container is "flat" when it holds only scalars (or arrays of scalars); such
    ; containers are written on one line to keep the config file readable.
    static _IsFlat(v) {
        for k, x in v {
            if x is Map
                return false
            if x is Array {
                for y in x
                    if IsObject(y)
                        return false
            }
        }
        return true
    }

    static _Quote(s) {
        s := StrReplace(String(s), "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        while RegExMatch(s, "[\x00-\x1F]", &m)
            s := StrReplace(s, m[0], Format("\u{:04X}", Ord(m[0])))
        return '"' s '"'
    }
}
