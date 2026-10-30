#!/usr/bin/env python3
import json
import signal
import subprocess
import sys
import os
import selectors
import time

MAX_LUA_LEN = 65536
MAX_OUTPUT_BYTES = 1048576  # 1 MiB bounded read
TIMEOUT_SECONDS = 5.0
DELAYS = [0.0, 2.0, 4.0]
EXPECTED_KEYS = {
    "mouse:275",
    "mouse:276",
    "mouse:274",
    "mouse_left",
    "mouse:278",
    "mouse_right",
    "mouse:279",
}
PROFILE_COMMAND = "omarchy-shell io.github.pavellizunov.mx-ergo nextProfile"
PROFILE_DESCRIPTION = "MX Ergo: Next Profile (keyboard)"
MODIFIERS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT")]
SHORTCUT_KEYS = {"space", "Return", "Escape", "Tab", "BackSpace", "Delete", "Insert",
                 "Home", "End", "Prior", "Next", "Left", "Right", "Up", "Down", "Print", "Pause", "Menu"}
SHORTCUT_KEYS |= set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") | {f"F{i}" for i in range(1, 25)}


def _handle_signal(signum, frame):
    raise SystemExit(128 + signum)


def _validate_payload(raw_json: str):
    if len(raw_json) > 131072:
        raise ValueError("Payload too large")
    try:
        data = json.loads(raw_json)
    except Exception:
        raise ValueError("Invalid JSON payload")

    if not isinstance(data, dict):
        raise ValueError("Payload must be a JSON object")

    lua = data.get("lua")
    if not isinstance(lua, str) or not lua.strip() or len(lua) > MAX_LUA_LEN:
        raise ValueError("Lua script must be a string <= 65536 chars")

    expected = data.get("expected")
    if not isinstance(expected, dict) or set(expected.keys()) != EXPECTED_KEYS:
        raise ValueError("Expected bindings must match required keys")

    for k, v in expected.items():
        if isinstance(v, dict):
            if v != {"description": "MX Ergo: Next Profile", "release": k not in ("mouse_left", "mouse_right"),
                     "dispatcher": "__lua"}:
                raise ValueError(f"Invalid profile target for {k}")
        elif v is not None and (not isinstance(v, str) or len(v) > 4096):
            raise ValueError(f"Invalid target for {k}")

    shortcut = data.get("profileShortcut")
    if shortcut is not None:
        if not isinstance(shortcut, dict) or set(shortcut) != {"key", "modmask", "keys"}:
            raise ValueError("Invalid profile shortcut")
        key, mask = shortcut["key"], shortcut["modmask"]
        if not isinstance(key, str) or key not in SHORTCUT_KEYS or type(mask) is not int or mask < 0 or mask & ~77:
            raise ValueError("Invalid profile shortcut")
        canonical = " + ".join([name for bit, name in MODIFIERS if mask & bit] + [key])
        if shortcut["keys"] != canonical:
            raise ValueError("Invalid profile shortcut")

    return lua, expected, shortcut, "profileShortcut" in data


def _run_bounded(cmd):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + TIMEOUT_SECONDS
    output = bytearray()
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise subprocess.TimeoutExpired(cmd, TIMEOUT_SECONDS)
                chunk = os.read(proc.stdout.fileno(), min(65536, MAX_OUTPUT_BYTES + 1 - len(output)))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > MAX_OUTPUT_BYTES:
                    raise ValueError("Command output exceeded bound")
        remaining = max(0, deadline - time.monotonic())
        return proc.wait(timeout=remaining), output.decode("utf-8", errors="replace")
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        proc.stdout.close()


def _read_binds():
    rc, out = _run_bounded(["hyprctl", "-j", "binds"])
    if rc != 0:
        raise ValueError("hyprctl binds command failed")

    try:
        binds = json.loads(out)
        if not isinstance(binds, list) or any(
            not isinstance(b, dict) or not isinstance(b.get("key"), str)
            or type(b.get("modmask")) is not int or not isinstance(b.get("submap"), str)
            for b in binds
        ):
            raise ValueError("Invalid binds data format")
    except (json.JSONDecodeError, TypeError):
        raise ValueError("Failed to parse binds JSON")
    return binds


def _owned_shortcut(binding):
    return (binding.get("description") == PROFILE_DESCRIPTION
            and binding.get("dispatcher") == "__lua"
            and isinstance(binding.get("arg"), str) and binding["arg"].isdigit()
            and binding.get("release") is True
            and not binding.get("repeat", False)
            and binding.get("submap") == ""
            and binding.get("keycode", 0) == 0
            and binding.get("key", "").casefold() in {key.casefold() for key in SHORTCUT_KEYS}
            and type(binding.get("modmask")) is int
            and 0 <= binding["modmask"] <= 77 and not binding["modmask"] & ~77)


def _same_shortcut(binding, shortcut):
    return (binding.get("key", "").casefold() == shortcut["key"].casefold()
            and binding.get("modmask") == shortcut["modmask"])


def _shortcut_conflict(binding, shortcut):
    # A code binding cannot be resolved safely from binds JSON alone. Treat a
    # matching modifier mask conservatively, including named submaps: this host's
    # unbind removes matching combinations across all submaps.
    mask_matches = binding.get("modmask") == shortcut["modmask"] or binding.get("ignore_mods") is True
    key_matches = binding.get("key", "").casefold() == shortcut["key"].casefold()
    return mask_matches and (key_matches
                             or binding.get("keycode", 0) != 0 or binding.get("catch_all") is True)


def _prepare_shortcut(shortcut):
    binds = _read_binds()
    owned = [b for b in binds if _owned_shortcut(b)]
    if shortcut and any(_shortcut_conflict(b, shortcut) and not _owned_shortcut(b) for b in binds):
        raise ValueError("shortcut_conflict")
    # Never unbind a combination shared with a foreign binding, including an
    # unexpected duplicate added after our last application.
    for binding in owned:
        if any(_shortcut_conflict(other, binding) and not _owned_shortcut(other) for other in binds):
            raise ValueError("shortcut_conflict")
    lua = "do\nlocal owned = _G.mx_ergo_profile_shortcut\n"
    # Hyprland's Lua callbacks appear as __lua/registry ID, not exec/command.
    # A matching description alone never grants cleanup authority: the live
    # binding handle must still match the callback reported by the compositor.
    for binding in owned:
        lua += ("if not owned or owned.arg ~= " + json.dumps(binding["arg"])
                + " or owned.description ~= " + json.dumps(PROFILE_DESCRIPTION)
                + " then error('shortcut_conflict') end\n")
    lua += "if owned then owned:unbind() end\n_G.mx_ergo_profile_shortcut = nil\n"
    if shortcut:
        lua += ("_G.mx_ergo_profile_shortcut = hl.bind(" + json.dumps(shortcut["keys"])
                + ", hl.dsp.exec_cmd(" + json.dumps(PROFILE_COMMAND) + "), { description = "
                + json.dumps(PROFILE_DESCRIPTION) + ", release = true })\n")
    return lua + "end\n"


def _check_binds(expected: dict, shortcut=None, manage_shortcut=False):
    try:
        binds = _read_binds()
    except ValueError as error:
        return False, str(error)

    for key, target in expected.items():
        matches = [
            b for b in binds
            if b.get("key") == key
            and b.get("modmask") == 0
            and b.get("submap") == ""
        ]

        if target is None:
            if len(matches) != 0:
                return False, f"Unexpected binding present for {key}"
        else:
            if len(matches) != 1:
                return False, f"Expected exactly one binding for {key}"
            description = target["description"] if isinstance(target, dict) else target
            if matches[0].get("description") != description:
                return False, f"Description mismatch for {key}"
            if isinstance(target, dict) and any(matches[0].get(k) != v for k, v in target.items()):
                return False, f"Profile switch binding mismatch for {key}"
            if isinstance(target, dict) and matches[0].get("repeat", False):
                return False, f"Repeating profile switch binding for {key}"
            if isinstance(target, dict) and (not isinstance(matches[0].get("arg"), str) or not matches[0]["arg"].isdigit()):
                return False, f"Invalid profile callback for {key}"

    if manage_shortcut:
        owned = [b for b in binds if _owned_shortcut(b)]
        if shortcut:
            matches = [b for b in binds if _same_shortcut(b, shortcut)]
            if len(matches) != 1 or not _owned_shortcut(matches[0]) or len(owned) != 1:
                return False, "Profile shortcut verification failed"
        elif owned:
            return False, "Profile shortcut cleanup failed"

    return True, None


def main():
    if len(sys.argv) != 2:
        out = {"ok": False, "attempts": 0, "error": "Invalid arguments"}
        print(json.dumps(out))
        sys.exit(1)

    try:
        lua, expected, shortcut, manage_shortcut = _validate_payload(sys.argv[1])
    except ValueError as e:
        out = {"ok": False, "attempts": 0, "error": str(e)}
        print(json.dumps(out))
        sys.exit(1)

    attempts = 0
    last_error = "Unknown error"

    for delay in DELAYS:
        attempts += 1
        if delay > 0:
            time.sleep(delay)

        try:
            prefix = _prepare_shortcut(shortcut) if manage_shortcut else ""
            rc, out = _run_bounded(["hyprctl", "eval", prefix + lua])
            if rc != 0 or out.strip() != "ok":
                last_error = "shortcut_conflict" if "shortcut_conflict" in out else "hyprctl eval failed"
                if last_error == "shortcut_conflict":
                    break
                continue

            ok, err = _check_binds(expected, shortcut, manage_shortcut)
            if ok:
                print(json.dumps({"ok": True, "attempts": attempts, "error": None}))
                sys.exit(0)
            last_error = err or "Verification failed"

        except subprocess.TimeoutExpired:
            last_error = "Command timed out"
        except ValueError as e:
            last_error = str(e)
            if last_error == "shortcut_conflict":
                break
        except Exception:
            last_error = "Execution error"

    print(json.dumps({"ok": False, "attempts": attempts, "error": last_error}))
    sys.exit(1)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)
    main()
