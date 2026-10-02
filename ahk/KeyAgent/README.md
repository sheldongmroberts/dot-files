# KeyAgent

UHK Agent-style remapping for a normal keyboard, written in AutoHotkey v2. It brings your UHK's
layers (Mod, Fn, Mouse, Fn2–Fn5), tap/hold keys, keymaps, mouse keys and macros to a laptop or
any regular keyboard. You edit them in a GUI modelled on Agent: pick a keymap and a layer, click
a key, choose what it does.

## Quick start

1. Requires AutoHotkey v2 (2.0.27 is installed on this PC).
3. Double-click `KeyAgent.ahk`. A keyboard icon appears in the tray; double-click it to open
   the editor. Right-click it for: keymap, pause, reload config, start with Windows, exit.

On first run, `config.json` is created from `default-config.json`, which was generated from your
UHK Agent configuration (`%APPDATA%\uhk-agent\43627732.json`).

To use the script version on another computer, copy `KeyAgent.ahk`, the `lib\` folder,
`default-config.json` and (to keep your edits) `config.json`, and install AutoHotkey v2 there.

## Single-file KeyAgent.exe (optional)

`dist\KeyAgent.exe` is the same program as one file that runs **without AutoHotkey installed**,
so it's the easiest thing to put on another computer.

- **Build it**: double-click `tools\BuildExe.ahk` (it uses AutoHotkey's compiler, Ahk2Exe).
  Rebuild after changing KeyAgent's code. Editing your layout doesn't need a rebuild, because
  that lives in `config.json`.
- **Share just `KeyAgent.exe`.** It carries your UHK-based default layout inside it. On first
  run it creates `config.json` next to itself, or in `%APPDATA%\KeyAgent` if that folder isn't
  writable (e.g. Program Files). To bring your edits along, put your `config.json` next to the
  exe. A `default-config.json` next to the exe replaces the built-in default.
- Same tray menu, editor and command-line options (`KeyAgent.exe --editor`).
- Run either the exe or `KeyAgent.ahk`, not both at once: they'd both remap the keyboard.
- **Unsigned exe**: SmartScreen may warn the first time it runs on another computer
  (*More info → Run anyway*), and some antivirus or company-managed PCs block programs compiled
  with AutoHotkey. The build turns off exe compression, which is what antivirus flags most.

## Your layout

Your UHK puts Mod on the thumb keys and Mouse where Caps Lock is. A normal keyboard has no
spare thumb keys, so the defaults are:

| Key | Does | Like the UHK's |
|---|---|---|
| **Right Alt** | Mod layer while held; double-tap to lock it, tap again to unlock | thumb Mod keys |
| **Caps Lock** | Mouse layer while held; double-tap to lock | Mouse key |
| Left Alt | stays Alt (and is right-click on the Mouse layer) | |

Your **Mod layer**, ported from QWERTY for PC: F1–F12 on the number row, Esc on `` ` `` and Q;
↑←↓→ on I/J/K/L; Home/End on U/O; Page Up/Down on Y/H; Delete on P and Backspace; Backspace on
`;`; Ctrl+PgUp/Ctrl+T/Ctrl+PgDn on W/E/R (tabs); Alt+Tab on D; Ctrl+Alt+←/→ on S/F;
Ctrl+Shift+PgUp/Ctrl+W/Ctrl+Shift+PgDn on X/C/V; Win on A; Esc on N; Menu on `/`;
PrtSc/ScrLk/Pause on `[ ] \`.

Your **Mouse layer**: I/J/K/L move the pointer, Y/H scroll up/down, U/O scroll left/right,
Space = left click, Left Alt or Right Alt = right click. Speeds and acceleration are your UHK's
(including the slow speed of 12 and diagonal speed compensation).

The **Fn layer** (media keys on U/I/J/K/L, mute on `,`) is ported too but has no key, because
your UHK QWERTY keymap has no Fn key either. To use it, pick a key on the Base layer (for example
Menu/AppsKey) and set it to *Switch layer → Fn*.

Your three UHK macros came along as examples. None of them is on a key yet.

## The editor

- **Keymap** bar: switch, add, duplicate, rename, delete keymaps; *Make default* sets the one
  KeyAgent starts with. Keymap-switch keys (and the tray menu) change keymaps on the fly.
- **Layer tabs**: Base, Mod, Fn, Mouse, Fn2–Fn5.
- **Keyboard**: click a key (or *Find key…* and press it). Tile text colours follow the UHK's
  functional backlighting: white = key, blue = shortcut, cyan = modifier, yellow = layer,
  red = keymap, green = mouse, purple = macro. Dimmed tiles aren't mapped on this layer and fall
  through to the Base layer. `^ + ! #` = Ctrl, Shift, Alt, Win.
- **Action** for the selected key:
  - *Key or shortcut*: any key, media key or F13–F24, plus modifiers (*Capture…* records a key
    or shortcut). *When held* turns it into a tap/hold key: tap = the key, hold = a modifier or
    a layer (e.g. Space: tap Space, hold Mod).
  - *Switch layer*: hold, toggle, or hold + double-tap to lock.
  - *Switch keymap*, *Mouse key*, *Play macro*, *Disabled*.
  - *Not mapped*: a normal key on Base; on other layers, whatever the Base layer does.
- **Macros…**: text, key taps/presses/releases, delays, mouse buttons, pointer moves, scrolling,
  and running programs/URLs. *Test* plays the macro after 3 seconds.
- **Settings…**: double-tap timing, tap/hold strategy (Simple or Advanced: timeout, trigger on
  press or release, double-tap repeat, Ctrl+click), mouse key speeds, the on-screen layer
  indicator, pausing while a UHK is connected, start with Windows.
- **Import from UHK…**: re-import keymaps, macros and settings from UHK Agent at any time (e.g.
  after changing your UHK), choosing which key here acts as the UHK's Mod/Mouse/Fn/Fn2 keys.
- Edits apply on **Save & Apply**. *Try it here* is a text box for testing the saved layout.

## How it behaves

- **Same rules as the UHK**: a key's action is decided when it goes down; releasing it always
  undoes that, even if the layer changed in between. A key held before a layer switch keeps
  doing what it did.
- **Order is kept**: while remapped output is still being sent, plain keys queue up behind it,
  so fast rolls like Mod+L, x, c come out in the order typed.
- **Pauses while a UHK is connected**, because AutoHotkey can't tell keyboards apart and the
  UHK already does all this in firmware. Detection uses UHK Agent's USB IDs (verified with your
  UHK 80 on USB); Bluetooth detection is best-effort. The UHK dongle doesn't count unless you
  tick that in Settings, so a dongle left plugged in won't keep KeyAgent paused. Untick *Pause
  KeyAgent while a UHK is connected* to use KeyAgent on another keyboard while the UHK is
  plugged in (then the UHK's Right Alt also acts as Mod).
- **Apple keyboards**: the key right of Space is Command (Right Win), not Alt. If that's your
  keyboard, set Right Win to *Switch layer → Mod* instead of Right Alt.
- **Admin windows**: for the script version, *Start with Windows* launches KeyAgent with
  AutoHotkey's UI Access build, so remapping also works in windows running as administrator.
  When you double-click `KeyAgent.ahk`, and always with `KeyAgent.exe`, remapping doesn't reach
  admin windows (normal AutoHotkey limitation).
- **Not carried over from the UHK**: smart-macro commands, Bluetooth/host-connection keys,
  backlight and keyboard-sleep keys (keyboard hardware only).

## Files

| Path | What |
|---|---|
| `KeyAgent.ahk` | the program (tray, pause, startup); `--editor` opens the editor |
| `config.json` | your configuration, written by the editor (plain JSON) |
| `default-config.json` | first-run configuration, from your UHK Agent config |
| `KeyAgent.ico` | the keyboard icon (tray and exe) |
| `dist\KeyAgent.exe` | the single-file version, built by `tools\BuildExe.ahk` |
| `lib\Engine.ahk` | remapping engine: layers, tap/hold keys, keymaps |
| `lib\Editor.ahk`, `lib\Dialogs.ahk` | editor, macros, settings, import, key capture |
| `lib\UhkImport.ahk` | UHK Agent config converter |
| `lib\MouseKeys.ahk`, `lib\Macros.ahk` | mouse keys and macro playback |
| `lib\Keys.ahk`, `lib\Actions.ahk`, `lib\Config.ahk`, `lib\Json.ahk`, `lib\Osd.ahk`, `lib\UhkDetect.ahk` | supporting modules |
| `tools\MakeDefaultConfig.ahk` | regenerates `default-config.json` from your UHK Agent config |
| `tools\BuildExe.ahk` | builds `dist\KeyAgent.exe` |
| `tools\MakeIcon.ps1` | redraws `KeyAgent.ico` |
| `tests\` | automated tests (below) |

## Tests

```
AutoHotkey64.exe /ErrorStdOut tests\TestCore.ahk   # engine, importer, JSON, mouse math (no hook)
AutoHotkey64.exe /ErrorStdOut tests\GuiSmoke.ahk   # drives the editor and dialogs, saves screenshots
AutoHotkey64.exe /ErrorStdOut tests\Startup.ahk    # first run, tray, UHK auto-pause, config location
AutoHotkey64.exe /ErrorStdOut tests\E2E.ahk        # real keyboard hook: types into a test window
AutoHotkey64.exe /ErrorStdOut tests\E2E.ahk --exe dist\KeyAgent.exe   # same, against the exe
```

`E2E.ahk` takes the focus for about 5 seconds, so don't type while it runs. Results and
screenshots go to `tests\out\`.
