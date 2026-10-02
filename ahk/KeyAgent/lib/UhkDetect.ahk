; UhkDetect.ahk - is an Ultimate Hacking Keyboard connected? KeyAgent pauses itself while one is,
; so the UHK's own keys (which already do all of this in firmware) aren't remapped a second time.
;
; USB IDs come from UHK Agent: UHK 60 v1/v2 (VID 1D50 PID 6122/6124, or VID 37A8 PID 1/3),
; UHK 80 left/right halves (VID 37A8 PID 7/9) and the UHK dongle (VID 37A8 PID 5). Bluetooth LE
; device paths spell the vendor as "VID&0237A8".

class UhkDetect {
    static Connected(includeDongle := false) {
        static RIDI_DEVICENAME := 0x20000007
        pids := includeDongle ? "[13579]" : "[1379]"
        pattern := "i)VID_1D50&PID_612[24]|VID[_&](?:02)?37A8[_&]PID[_&]000" pids "(?![0-9A-F])"
        size := A_PtrSize * 2                       ; sizeof(RAWINPUTDEVICELIST)
        count := 0
        DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &count, "UInt", size)
        if !count
            return false
        list := Buffer(size * count)
        n := DllCall("GetRawInputDeviceList", "Ptr", list, "UInt*", &count, "UInt", size, "Int")
        loop Max(n, 0) {
            handle := NumGet(list, (A_Index - 1) * size, "Ptr")
            chars := 0
            DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", RIDI_DEVICENAME, "Ptr", 0, "UInt*", &chars)
            if !chars
                continue
            name := Buffer(chars * 2 + 2, 0)
            DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", RIDI_DEVICENAME, "Ptr", name, "UInt*", &chars)
            if RegExMatch(StrGet(name), pattern)
                return true
        }
        return false
    }
}
