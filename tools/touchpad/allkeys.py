#!/usr/bin/env python3
"""Count every EV_KEY and EV_MSC event on all input nodes of the touchpad's
HID device while you press the pad. Read-only; it only listens.

Usage: sudo python3 -I allkeys.py [--seconds N] [--hid ID] [--out FILE]

The touchpad is found at run time: the first input node named like a
touchpad, and then every input node of the same HID device. Pass --hid
(for example 0018:VVVV:PPPP.0001) to name the device yourself. The
discovery code is shared in spirit with common.sh and click-hid.py; keep
the three in sync.
"""
import argparse
import glob
import os
import re
import select
import struct
import sys
import time

HID_RE = re.compile(r"[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}")
EV_KEY, EV_MSC = 1, 4
EVENT = struct.Struct("llHHi")  # struct input_event on 64-bit Linux: 24 bytes
NAMES = {
    (EV_KEY, 0x110): "BTN_LEFT",
    (EV_KEY, 0x111): "BTN_RIGHT",
    (EV_KEY, 0x112): "BTN_MIDDLE",
    (EV_KEY, 0x14A): "BTN_TOUCH",
    (EV_KEY, 0x145): "BTN_TOOL_FINGER",
    (EV_KEY, 0x14D): "BTN_TOOL_DOUBLETAP",
    (EV_KEY, 0x14E): "BTN_TOOL_TRIPLETAP",
    (EV_MSC, 0x04): "MSC_SCAN",
}


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


def event_nodes(hid):
    """Every /dev/input/eventN that belongs to the HID device."""
    nodes = []
    for entry in sorted(glob.glob("/sys/class/input/event*")):
        if "/" + hid + "/" in os.path.realpath(entry) + "/":
            nodes.append("/dev/input/" + os.path.basename(entry))
    return nodes


def chown_for_sudo(path):
    uid, gid = os.environ.get("SUDO_UID"), os.environ.get("SUDO_GID")
    if uid and os.path.exists(path):
        os.chown(path, int(uid), int(gid or uid))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seconds", type=int, default=15)
    ap.add_argument("--hid", help="HID id; default: discover the touchpad")
    ap.add_argument("--out", help="also write the report to this file")
    args = ap.parse_args()
    if EVENT.size != 24:
        sys.exit("this tool expects the 64-bit input_event layout")

    hid = args.hid or find_hid()
    if not hid:
        sys.exit("no input node with Touchpad in its name")
    nodes = event_nodes(hid)
    if not nodes:
        sys.exit("no input nodes found for " + hid)

    fds = {}
    out = open(args.out, "w") if args.out else None
    try:
        for node in nodes:
            try:
                fds[os.open(node, os.O_RDONLY | os.O_NONBLOCK)] = node
            except PermissionError:
                sys.exit("cannot read " + node + "; run with sudo")
        header = "device %s, nodes: %s" % (hid, " ".join(os.path.basename(n) for n in nodes))
        print(header, flush=True)
        print("Press the pad down firmly, about once a second, for the whole window (%d s)" % args.seconds, flush=True)
        seen = {}
        end = time.time() + args.seconds
        while time.time() < end:
            for fd in select.select(list(fds), [], [], 0.2)[0]:
                data = os.read(fd, EVENT.size * 64)
                for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    _, _, etype, code, value = EVENT.unpack_from(data, off)
                    if etype in (EV_KEY, EV_MSC):
                        key = (os.path.basename(fds[fd]), etype, code, value)
                        seen[key] = seen.get(key, 0) + 1
        lines = [header]
        for (node, etype, code, value), count in sorted(seen.items()):
            name = NAMES.get((etype, code), "type%d/0x%x" % (etype, code))
            lines.append("  %s %s value=%d: %d" % (node, name, value, count))
        if not seen:
            lines.append("  no key or scan-code events seen")
        report = "\n".join(lines)
        print(report, flush=True)
        if out:
            out.write(report + "\n")
    finally:
        for fd in fds:
            os.close(fd)
        if out:
            out.close()
            chown_for_sudo(args.out)


if __name__ == "__main__":
    main()
