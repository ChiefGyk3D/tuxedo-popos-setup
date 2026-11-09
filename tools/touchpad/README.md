# Touchpad diagnostics

Diagnostics only. This version ships no boot-time fix: the fix is pending a
reboot test, and nothing here changes the system permanently.

## The finding

On the TUXEDO Stellaris Slim 16 AMD under Pop!_OS 24.04, a physical click on
the touchpad sometimes did nothing, so click-drag failed.

What was observed:

1. The raw HID report shows the click. The pad sends it (`click-hid.py`).
2. The kernel's `hid-multitouch` driver is the one expected to turn that into
   a `BTN_LEFT` event on the touchpad's input node.
3. The symptom was that no `BTN_LEFT` reached the input node (`allkeys.py`,
   `trace-click.sh`) until the touchpad was rebound to another driver and
   back (`driver-swap-test.sh`).

**The cause is unproven.** The evidence above says the click is lost between
the HID report and the input event, inside or around `hid-multitouch`. It does
not say why, and it does not show that a rebind is a reliable cure. Treat the
rebind as a diagnostic, not a fix.

## Tools

All tools find the touchpad at run time, by an input node name that contains
"Touchpad" and then its HID device. No device id, user name or home path is
written into them. Set `TP_HID` (shell tools) or pass `--hid` (Python tools)
to name a device yourself.

Run them with `sudo`. They are meant to be run one at a time while you press
the pad, from this directory.

| Tool | What it does | Changes system state? |
| --- | --- | --- |
| `touchpad-diag.sh` | Records libinput events during a click-drag phase and a tap-drag phase. | No. |
| `click-hid.py` | Prints raw HID report changes for the click and mouse buttons, below the input layer. | No. |
| `allkeys.py` | Counts every key and scan-code event on all input nodes of the touchpad's HID device. | No. |
| `trace-click.sh` | Uses kernel kprobes to count `input_event` calls and `mt_sync_frame` calls. | Temporarily (two kprobes and the trace buffer size); both are removed or restored on exit. x86_64 only. |
| `driver-swap-test.sh` | Rebinds the touchpad to `hid-generic`, counts button events, then rebinds the original driver. | Temporarily; the original driver and the `hid` module parameter are restored on exit, also on Ctrl-C. Asks first unless `--yes`. |

Each tool accepts `--seconds` and (except `trace-click.sh`) `--out FILE`; run
it with a bad option to see its usage.

### Things to know

- `click-hid.py` reads byte offsets from the HID report descriptor of one pad
  (vendor `093A`, product `0255`). On any other pad the offsets are likely
  wrong; it warns, and the offsets can be set with its `--click-*` and
  `--mouse-*` options after reading the pad's `report_descriptor` in sysfs.
- `trace-click.sh` sees events from every input device, keystrokes included.
  Do not type while it runs. Only per-code counts are printed; the raw trace is
  discarded unless you pass `--keep-raw FILE`.
- `libinput debug-events` comes from the `libinput-tools` package. The
  `touchpad` installer module installs it.
- Nothing here was run as root by the author of this repository's first
  version; see the main README for what is verified.
