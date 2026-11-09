#!/usr/bin/env python3
"""Watch the touchpad's raw HID reports, below the kernel input layer, to see
whether a physical click arrives at all. Read-only; it only listens.

Usage: sudo python3 -I click-hid.py [--hid ID] [--out FILE] [offset options]

The report layout is device specific. The defaults below were read from the
report descriptor of one pad (vendor 093A, product 0255): report 1, byte 27,
bits 0-2 hold the click buttons; report 2, byte 1, bits 0-1 hold the mouse
buttons. A different pad needs its own offsets (read its report_descriptor in
sysfs); the tool warns when the vendor:product differs. The discovery code is
shared in spirit with common.sh and allkeys.py; keep the three in sync.
"""
import argparse
import glob
import os
import re
import select
import sys
import time

HID_RE = re.compile(r"[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}")
KNOWN_VID_PID = "093A:0255"


def find_hid():
    """HID id of the first input node whose name mentions a touchpad."""
    for name_file in sorted(glob.glob("/sys/class/input/event*/device/name")):
        with open(name_file) as fh:
            if "touchpad" not in fh.read().lower():
                continue
        match = HID_RE.search(os.path.realpath(name_file))
        if match:
            return match.group(0)
    return None


def hidraw_node(hid):
    nodes = sorted(glob.glob("/sys/bus/hid/devices/%s/hidraw/hidraw*" % hid))
    return "/dev/" + os.path.basename(nodes[0]) if nodes else None


def chown_for_sudo(path):
    uid, gid = os.environ.get("SUDO_UID"), os.environ.get("SUDO_GID")
    if uid and os.path.exists(path):
        os.chown(path, int(uid), int(gid or uid))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--hid", help="HID id; default: discover the touchpad")
    ap.add_argument("--out", help="also write the report to this file")
    ap.add_argument("--click-report", type=int, default=1)
    ap.add_argument("--click-byte", type=int, default=27)
    ap.add_argument("--click-mask", type=lambda s: int(s, 0), default=0x07)
    ap.add_argument("--mouse-report", type=int, default=2)
    ap.add_argument("--mouse-byte", type=int, default=1)
    ap.add_argument("--mouse-mask", type=lambda s: int(s, 0), default=0x03)
    args = ap.parse_args()

    hid = args.hid or find_hid()
    if not hid:
        sys.exit("no input node with Touchpad in its name")
    node = hidraw_node(hid)
    if not node:
        sys.exit("no hidraw node for " + hid)
    log = open(args.out, "w") if args.out else None

    def say(text):
        print(text, flush=True)
        if log:
            log.write(text + "\n")

    fd = None
    try:
        try:
            fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
        except PermissionError:
            sys.exit("cannot read " + node + "; run with sudo")
        say("device %s via %s" % (hid, node))
        if KNOWN_VID_PID not in hid.upper():
            say("WARN: offsets were taken from a %s pad; check them against this pad's report descriptor" % KNOWN_VID_PID)
        counts = {}
        state = {"last_click": None, "last_mouse": None, "changes": 0}

        def phase(title, seconds):
            say("\n%s (%d s) - starting now" % (title, seconds))
            end = time.time() + seconds
            while time.time() < end:
                if not select.select([fd], [], [], 0.2)[0]:
                    continue
                try:
                    report = os.read(fd, 64)
                except BlockingIOError:
                    continue
                if not report:
                    continue
                counts[report[0]] = counts.get(report[0], 0) + 1
                if report[0] == args.click_report and len(report) > args.click_byte:
                    value = report[args.click_byte] & args.click_mask
                    if value != state["last_click"]:
                        say("  report%d click bits=%s len=%d" % (report[0], bin(value), len(report)))
                        state["changes"] += 1
                        state["last_click"] = value
                elif report[0] == args.mouse_report and len(report) > args.mouse_byte:
                    value = report[args.mouse_byte] & args.mouse_mask
                    if value != state["last_mouse"]:
                        say("  report%d mouse buttons=%s" % (report[0], bin(value)))
                        state["changes"] += 1
                        state["last_mouse"] = value
            say("-> reports seen so far by id: %s; button changes so far: %d" % (counts, state["changes"]))

        phase("PHASE A: press the pad down firmly 5 times, slowly, one finger", 20)
        phase("PHASE B: press and HOLD the pad down for 5 s, then release", 15)
    finally:
        if fd is not None:
            os.close(fd)
        if log:
            log.close()
            chown_for_sudo(args.out)


if __name__ == "__main__":
    main()
