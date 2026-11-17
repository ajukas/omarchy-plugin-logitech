#!/usr/bin/env python3
"""Talk to the Logitech mouse, headset and webcam for the ajukas.logitech widget.

Every command prints one JSON object on stdout, so the widget never has to
parse tool output itself.

  logi-helper.py status [--notify-below N] [--fresh-headset]
                                             battery and camera state (fast)
  logi-helper.py mouse-settings              DPI and report rate via solaar (slow)
  logi-helper.py mouse-set <setting> <value> e.g. mouse-set dpi 1600
  logi-helper.py headset-set <sidetone|inactive> <value>
  logi-helper.py camera-set <control> <value>
  logi-helper.py camera-apply                re-apply the saved camera profile
  logi-helper.py camera-reset                back to factory defaults
  logi-helper.py camera-preview              open a live preview in mpv
"""

import fcntl
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

LOGITECH_VENDOR = "046d"
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "ajukas-logitech")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "ajukas-logitech")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
CAMERA_FILE = os.path.join(CONFIG_DIR, "camera.json")

# Automatic modes have to be switched off before their manual value sticks.
CAMERA_APPLY_ORDER = [
    "auto_exposure", "focus_automatic_continuous", "white_balance_automatic",
    "exposure_dynamic_framerate",
]


def run(argv, timeout=10):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return out.returncode, out.stdout, out.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


class Lock:
    """One bar widget runs per monitor, so serialize writes and notifications."""

    def __enter__(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        self.f = open(os.path.join(STATE_DIR, "lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        self.f.close()


def emit(data):
    print(json.dumps(data))


# ---------------------------------------------------------------- mouse

def mouse_status():
    # The kernel's hid-logitech-hidpp driver exposes the battery of HID++
    # devices behind a Lightspeed/Unifying receiver, no extra tool needed.
    for path in sorted(glob.glob("/sys/class/power_supply/hidpp_battery_*")):
        model = read(os.path.join(path, "model_name"))
        if not model:
            continue
        capacity = read(os.path.join(path, "capacity"))
        level = read(os.path.join(path, "capacity_level"))
        return {
            "present": True,
            "name": model,
            "battery": int(capacity) if capacity.isdigit() else None,
            "level": level,
            "status": read(os.path.join(path, "status")),
            "solaar": shutil.which("solaar") is not None,
        }
    return {"present": False, "solaar": shutil.which("solaar") is not None}


def solaar_device():
    name = mouse_status().get("name", "")
    # solaar matches a device by any word of its name; the model code is the safest.
    match = re.search(r"\b([A-Z]+\d+\w*)\b", name)
    return match.group(1) if match else (name or "1")


def parse_solaar_config(text):
    """Parse `solaar config <device>` into {setting: {value, choices, min, max}}."""
    settings = {}
    pending = {}
    for raw in text.splitlines():
        line = raw.strip()
        choices = re.match(r"#\s*possible values:\s*one of \[(.*)\]", line)
        between = re.match(r"#\s*possible values:\s*between (\d+) and (\d+)", line)
        if choices:
            items = [c.strip().strip("'\"") for c in choices.group(1).split(",") if c.strip()]
            pending = {"choices": items}
        elif between:
            pending = {"min": int(between.group(1)), "max": int(between.group(2))}
        elif not line.startswith("#") and "=" in line:
            key, value = [p.strip() for p in line.split("=", 1)]
            entry = dict(pending)
            entry["value"] = value
            settings[key] = entry
            pending = {}
    return settings


def mouse_settings():
    if not shutil.which("solaar"):
        return {"ok": False, "error": "solaar não está instalado"}
    code, out, err = run(["solaar", "config", solaar_device()], timeout=20)
    if code != 0:
        return {"ok": False, "error": (err or out).strip().splitlines()[-1:] or ["solaar falhou"]}
    settings = parse_solaar_config(out)
    result = {"ok": True}
    dpi = settings.get("dpi")
    if dpi:
        values = [int(c) for c in dpi.get("choices", []) if c.isdigit()]
        result["dpi"] = {
            "value": int(dpi["value"]) if dpi["value"].isdigit() else None,
            "min": dpi.get("min", min(values) if values else 100),
            "max": dpi.get("max", max(values) if values else 25600),
            "step": (values[1] - values[0]) if len(values) > 1 else 50,
        }
    rate = settings.get("report_rate")
    if rate:
        result["reportRate"] = {"value": rate["value"], "choices": rate.get("choices", [])}
    return result


def mouse_set(setting, value):
    if not shutil.which("solaar"):
        return {"ok": False, "error": "solaar não está instalado"}
    if setting not in ("dpi", "report_rate") or not re.fullmatch(r"[\w.]+", value):
        return {"ok": False, "error": "valor inválido"}
    with Lock():
        code, out, err = run(["solaar", "config", solaar_device(), setting, value], timeout=20)
    return {"ok": code == 0, "error": (err or out).strip() if code else ""}


# ---------------------------------------------------------------- headset

def headset_usb_name():
    """The headset's USB product name, read from sysfs without touching the device."""
    for dev in glob.glob("/sys/bus/usb/devices/*"):
        product = read(os.path.join(dev, "product"))
        # The PRO X's charging dock enumerates as a separate "... Battery Charger".
        if read(os.path.join(dev, "idVendor")) == LOGITECH_VENDOR and \
                "headset" in product.lower() and "charger" not in product.lower():
            return product
    return None


def headset_poll_interval(state):
    """Seconds between headsetcontrol queries.

    Every query talks to the headset over the wireless link and seems to count
    as activity, so polling faster than its auto power-off keeps it awake.
    Stay a few minutes past the configured inactive time.
    """
    inactive = state.get("inactive")
    if isinstance(inactive, int) and inactive > 0:
        return (inactive + 5) * 60
    return 30 * 60


def headset_status(state, fresh=False):
    tool = shutil.which("headsetcontrol")
    base = {
        "present": False,
        "headsetcontrol": tool is not None,
        "sidetone": state.get("sidetone"),
        "inactive": state.get("inactive"),
    }
    name = headset_usb_name()
    if name:
        # Without headsetcontrol the USB id still tells whether it is plugged in.
        base.update(present=True, name=name)
    if not tool or not name:
        return base
    with Lock():
        # Re-read under the lock: the widget on another monitor may have just polled.
        cache = load_json(STATE_FILE, {}).get("headsetCache") or {}
        age = time.time() - float(cache.get("at", 0))
        if not fresh and 0 <= age < headset_poll_interval(state) and cache.get("data"):
            base.update(cache["data"])
            return base
        data = headset_query(tool)
        if data:
            current = load_json(STATE_FILE, {})
            current["headsetCache"] = {"at": time.time(), "data": data}
            save_json(STATE_FILE, current)
    base.update(data)
    return base


def headset_query(tool):
    base = {}
    code, out, _ = run([tool, "-o", "json"])
    try:
        data = json.loads(out)
    except ValueError:
        return base
    for dev in data.get("devices", []):
        if str(dev.get("id_vendor", "")).lower().replace("0x", "") != LOGITECH_VENDOR:
            continue
        battery = dev.get("battery") or {}
        caps = dev.get("capabilities_str") or dev.get("capabilities") or []
        base.update(
            present=True,
            name=dev.get("product") or dev.get("device") or "Headset",
            battery=battery.get("level") if isinstance(battery.get("level"), int) and battery.get("level") >= 0 else None,
            batteryStatus=battery.get("status", ""),
            capabilities=[str(c).lower() for c in caps],
        )
        break
    return base


def headset_set(what, value):
    tool = shutil.which("headsetcontrol")
    if not tool:
        return {"ok": False, "error": "headsetcontrol não está instalado"}
    flag = {"sidetone": "-s", "inactive": "-i"}.get(what)
    if not flag or not value.isdigit():
        return {"ok": False, "error": "valor inválido"}
    with Lock():
        code, out, err = run([tool, flag, value])
        if code == 0:
            # headsetcontrol can only write these, so remember what we set.
            state = load_json(STATE_FILE, {})
            state[what] = int(value)
            save_json(STATE_FILE, state)
    return {"ok": code == 0, "error": (err or out).strip() if code else ""}


# ---------------------------------------------------------------- camera

def camera_device():
    """The capture node of the first Logitech webcam (/dev/videoN, index 0)."""
    for node in sorted(glob.glob("/sys/class/video4linux/video*"), key=lambda p: int(re.sub(r"\D", "", p) or 0)):
        if read(os.path.join(node, "index")) != "0":
            continue
        usb = os.path.realpath(os.path.join(node, "device"))
        # The interface's parent is the USB device that carries the ids.
        if read(os.path.join(os.path.dirname(usb), "idVendor")) == LOGITECH_VENDOR:
            return "/dev/" + os.path.basename(node), read(os.path.join(node, "name"))
    return None, None


CTRL_RE = re.compile(r"^\s*(\w+)\s+0x[0-9a-f]+\s+\((\w+)\)\s*:\s*(.*)$")
MENU_RE = re.compile(r"^\s*(\d+):\s*(.+)$")


def camera_controls(device):
    code, out, _ = run(["v4l2-ctl", "-d", device, "--list-ctrls-menus"])
    if code != 0:
        return []
    controls = []
    for line in out.splitlines():
        m = CTRL_RE.match(line)
        if m:
            name, kind, rest = m.groups()
            ctrl = {"name": name, "type": kind, "inactive": "inactive" in rest}
            for key, val in re.findall(r"(\w+)=(-?\d+)", rest):
                ctrl[key] = int(val)
            if kind == "menu":
                ctrl["menu"] = []
            controls.append(ctrl)
            continue
        m = MENU_RE.match(line)
        if m and controls and controls[-1]["type"] == "menu":
            controls[-1]["menu"].append({"value": m.group(1), "label": m.group(2).strip()})
    return controls


def camera_status():
    if not shutil.which("v4l2-ctl"):
        return {"present": False, "v4l2": False}
    device, name = camera_device()
    if not device:
        return {"present": False, "v4l2": True}
    return {"present": True, "v4l2": True, "device": device, "name": name,
            "controls": camera_controls(device), "saved": load_json(CAMERA_FILE, {})}


def camera_set(control, value, save=True):
    device, _ = camera_device()
    if not device:
        return {"ok": False, "error": "câmera não encontrada"}
    if not re.fullmatch(r"\w+", control) or not re.fullmatch(r"-?\d+", value):
        return {"ok": False, "error": "valor inválido"}
    with Lock():
        code, out, err = run(["v4l2-ctl", "-d", device, "-c", f"{control}={value}"])
        if code == 0 and save:
            profile = load_json(CAMERA_FILE, {})
            profile[control] = int(value)
            save_json(CAMERA_FILE, profile)
    return {"ok": code == 0, "error": (err or out).strip() if code else ""}


def camera_apply():
    """Webcams forget their settings when unplugged; put the saved ones back."""
    device, _ = camera_device()
    profile = load_json(CAMERA_FILE, {})
    if not device or not profile:
        return {"ok": True, "applied": 0}
    ordered = [k for k in CAMERA_APPLY_ORDER if k in profile] + \
              [k for k in profile if k not in CAMERA_APPLY_ORDER]
    failed = []
    with Lock():
        for key in ordered:
            code, _, _ = run(["v4l2-ctl", "-d", device, "-c", f"{key}={profile[key]}"])
            if code != 0:
                failed.append(key)
    return {"ok": not failed, "applied": len(ordered) - len(failed), "failed": failed}


def camera_reset():
    device, _ = camera_device()
    if not device:
        return {"ok": False, "error": "câmera não encontrada"}
    controls = camera_controls(device)
    by_name = {c["name"]: c for c in controls}
    ordered = [k for k in CAMERA_APPLY_ORDER if k in by_name] + \
              [c["name"] for c in controls if c["name"] not in CAMERA_APPLY_ORDER]
    with Lock():
        for key in ordered:
            if "default" in by_name[key]:
                run(["v4l2-ctl", "-d", device, "-c", f"{key}={by_name[key]['default']}"])
        try:
            os.remove(CAMERA_FILE)
        except OSError:
            pass
    return {"ok": True}


def camera_preview():
    device, name = camera_device()
    if not device:
        return {"ok": False, "error": "câmera não encontrada"}
    if not shutil.which("mpv"):
        return {"ok": False, "error": "mpv não está instalado"}
    subprocess.Popen(
        ["mpv", "--profile=low-latency", "--untimed", "--no-osc", "--no-audio",
         "--title=" + (name or "Webcam"), "--wayland-app-id=ajukas-logitech-preview",
         "av://v4l2:" + device],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True)
    return {"ok": True}


# ---------------------------------------------------------------- notifications

def notify_low(status, threshold):
    """Warn once per device when its battery drops below the threshold."""
    with Lock():
        state = load_json(STATE_FILE, {})
        warned = state.get("warned", {})
        changed = False
        for key, label in (("mouse", "Mouse"), ("headset", "Headset")):
            dev = status[key]
            pct = dev.get("battery")
            state_text = str(dev.get("status") or dev.get("batteryStatus") or "").lower()
            # "Discharging" contains "charging", so match the whole word.
            charging = state_text in ("charging", "full", "battery_charging")
            if not dev.get("present") or pct is None:
                continue
            if pct < threshold and not charging:
                if not warned.get(key):
                    run(["notify-send", "-u", "critical", "-a", "Logitech", "-i", "battery-caution",
                         f"{label} com bateria abaixo de {threshold}%", f"{dev.get('name', label)}: {pct}%. Coloque para carregar."])
                    warned[key] = True
                    changed = True
            elif warned.get(key) and pct > threshold + 5:
                warned[key] = False
                changed = True
        if changed:
            state["warned"] = warned
            save_json(STATE_FILE, state)


def status(args):
    state = load_json(STATE_FILE, {})
    fresh = "--fresh-headset" in args
    result = {"mouse": mouse_status(), "headset": headset_status(state, fresh), "camera": camera_status()}
    if "--notify-below" in args:
        i = args.index("--notify-below")
        threshold = args[i + 1] if i + 1 < len(args) else ""
        if threshold.isdigit() and int(threshold) > 0:
            notify_low(result, int(threshold))
    return result


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    commands = {
        "status": lambda: status(args),
        "mouse-settings": mouse_settings,
        "mouse-set": lambda: mouse_set(*args[:2]),
        "headset-set": lambda: headset_set(*args[:2]),
        "camera-set": lambda: camera_set(*args[:2]),
        "camera-apply": camera_apply,
        "camera-reset": camera_reset,
        "camera-preview": camera_preview,
    }
    if cmd not in commands:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        emit(commands[cmd]())
    except TypeError:
        emit({"ok": False, "error": "argumentos faltando"})
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
