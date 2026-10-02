; Osd.ahk - a small on-screen indicator for the active layer and keymap (what the UHK shows on
; its display). It is click-through and never takes the focus.

class Osd {
    static gui := ""
    static label := ""
    static _hideFn := ""

    ; Shows msg near the bottom of the primary screen; hides it again after ms (0 = stays).
    static Show(msg, ms := 0) {
        if !this.gui {
            ; WS_EX_TRANSPARENT (click-through) | WS_EX_NOACTIVATE
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000")
            g.BackColor := "1E1F22"
            g.MarginX := 16, g.MarginY := 7
            g.SetFont("s11 bold cF5D547", "Segoe UI")
            this.label := g.Add("Text", "Center w220", "")
            this.gui := g
            this._hideFn := ObjBindMethod(this, "Hide")
        }
        this.label.Value := msg
        this.gui.Show("Hide AutoSize")
        this.gui.GetPos(, , &w, &h)
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        this.gui.Show("NoActivate x" (left + (right - left - w) // 2) " y" (bottom - h - 48))
        WinSetTransparent(230, this.gui)
        SetTimer(this._hideFn, ms ? -ms : 0)
    }

    static Hide(*) {
        if this.gui
            this.gui.Hide()
    }
}
