#!/bin/sh
# SPDX-License-Identifier: MIT
# cosmic-kbd-backlight - make the keyboard backlight brightness keys work on COSMIC
#
#   ./install.sh            install (or repair) the helper and the two bindings
#   ./install.sh verify     report the current state, change nothing
#   ./install.sh uninstall  remove everything this script installed
#   ./install.sh help       show this text
#
# Environment overrides (mainly for testing in a sandbox):
#   INSTALL_BIN_DIR   where the helper script goes (default: ~/.local/bin)
#   XDG_CONFIG_HOME   configuration root (default: ~/.config)
#
# Background: COSMIC recognises the keyboard backlight keys but does not act on
# them - the settings daemon's keyboard-brightness controls are not implemented,
# and the keys have no default assignment. This script binds the two keysyms to a
# small helper that drives the backlight through UPower, the same route the
# battery applet's slider already uses. Every installed piece lives in your home
# directory, so OS updates do not touch it.
#
# Editing the same two rows in COSMIC Settings' shortcut editor will attach a
# modifier and rewrite the file; run './install.sh repair' to put it back.
set -eu

PROG=$(basename "$0")
SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")

BIN_DIR=${INSTALL_BIN_DIR:-$HOME/.local/bin}
HELPER=$BIN_DIR/cosmic-kbd-backlight
SRC_HELPER=$HERE/bin/cosmic-kbd-backlight

CONF_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}
CONF_DIR=$CONF_ROOT/cosmic/com.system76.CosmicSettings.Shortcuts/v1
CUSTOM=$CONF_DIR/custom
ACTIONS=$CONF_DIR/system_actions

# The command recorded in the shortcuts config. Use $HOME when the helper is in
# its default location, so the config survives a moved home directory.
if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
    HELPER_CMD='$HOME/.local/bin/cosmic-kbd-backlight'
else
    HELPER_CMD=$HELPER
fi

usage() {
    # Print the leading comment block, minus the shebang and the SPDX line.
    awk 'NR==1 || /^# SPDX-License-Identifier:/ {next}
         /^#/ {sub(/^# ?/, ""); print; next}
         {exit}' "$SELF"
}

merge_config() {
    python3 - "$1" "$CUSTOM" "$ACTIONS" "$HELPER_CMD" <<'PYEOF'
import os, re, sys

mode, custom_path, actions_path, helper = sys.argv[1:5]

BINDING_KEYS = ["XF86KbdBrightnessUp", "XF86KbdBrightnessDown"]
ACTION_KEYS = ["KeyboardBrightnessUp", "KeyboardBrightnessDown"]

CANON_BINDINGS = [
    '    (modifiers: [], key: "XF86KbdBrightnessUp"): System(KeyboardBrightnessUp),',
    '    (modifiers: [], key: "XF86KbdBrightnessDown"): System(KeyboardBrightnessDown),',
]
CANON_ACTIONS = [
    '    KeyboardBrightnessUp: "%s +",' % helper,
    '    KeyboardBrightnessDown: "%s -",' % helper,
]


def split_entries(body):
    """Split a RON map body on top-level commas."""
    entries, buf, depth, instr, esc = [], "", 0, False, False
    for ch in body:
        if instr:
            buf += ch
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                instr = False
            continue
        if ch == '"':
            instr = True
            buf += ch
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            if buf.strip():
                entries.append(buf.strip())
            buf = ""
            continue
        buf += ch
    if buf.strip():
        entries.append(buf.strip())
    return entries


def read_entries(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    body = text.strip()
    if body in ("", "{}"):
        return []
    if not (body.startswith("{") and body.endswith("}")):
        raise SystemExit("error: %s is not a RON map; refusing to touch it" % path)
    return split_entries(body[1:-1])


def is_ours(entry, key):
    if '"%s"' % key in entry:
        return True
    return re.match(r"^%s\s*:" % re.escape(key), entry) is not None


def has_modifiers(entry):
    match = re.search(r"modifiers\s*:\s*\[([^\]]*)\]", entry)
    return bool(match and match.group(1).strip())


def render(entries):
    out = []
    for entry in entries:
        entry = entry.strip()
        if not entry.endswith(","):
            entry += ","
        out.append("    " + entry)
    return "{\n" + "\n".join(out) + "\n}\n" if out else None


if mode == "check":
    ok = True
    for path, keys, kind in (
        (custom_path, BINDING_KEYS, "binding"),
        (actions_path, ACTION_KEYS, "command"),
    ):
        try:
            entries = read_entries(path) or []
        except SystemExit as err:
            print("  %-24s ERROR  %s" % (kind, err))
            ok = False
            continue
        for key in keys:
            found = [e for e in entries if is_ours(e, key)]
            if not found:
                print("  %-24s MISSING" % key)
                ok = False
            elif kind == "binding" and has_modifiers(found[0]):
                print("  %-24s WRONG (a modifier is attached)" % key)
                ok = False
            else:
                print("  %-24s OK" % key)
    sys.exit(0 if ok else 1)

for path, keys, canon in (
    (custom_path, BINDING_KEYS, CANON_BINDINGS),
    (actions_path, ACTION_KEYS, CANON_ACTIONS),
):
    existing = read_entries(path)
    if existing is None and mode == "remove":
        continue
    kept = [e for e in (existing or []) if not any(is_ours(e, k) for k in keys)]
    if mode == "ensure":
        kept = kept + canon

    out = render(kept)
    current = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            current = fh.read()

    if out == current:
        print("  unchanged %s" % path)
    elif out is None:
        os.remove(path)
        print("  removed   %s" % path)
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(out)
        print("  %s %s" % ("updated  " if current is not None else "created  ", path))
PYEOF
}

case "${1:-install}" in
    install|repair)
        [ -x "$SRC_HELPER" ] || { echo "$PROG: cannot find $SRC_HELPER" >&2; exit 1; }
        command -v python3 >/dev/null || { echo "$PROG: python3 is required" >&2; exit 1; }
        mkdir -p "$BIN_DIR" "$CONF_DIR"
        cp "$SRC_HELPER" "$HELPER"
        chmod 0755 "$HELPER"
        echo "helper:   $HELPER"
        echo "config:"
        merge_config ensure
        echo
        echo "Done. '$PROG verify' reports the state; '$PROG uninstall' removes it."
        echo "Do not re-record these two keys in COSMIC Settings' shortcut editor -"
        echo "it attaches a modifier and rewrites the file. Run '$PROG repair' instead."
        ;;
    uninstall)
        rm -f "$HELPER"
        echo "helper:   removed $HELPER"
        echo "config:"
        merge_config remove
        ;;
    verify)
        status=0
        if [ -x "$HELPER" ]; then
            echo "helper:   OK        $HELPER"
        else
            echo "helper:   MISSING   $HELPER"
            status=1
        fi

        led=
        for candidate in /sys/class/leds/*kbd_backlight; do
            [ -e "$candidate" ] || continue
            led=$candidate
            break
        done
        if [ -n "$led" ]; then
            echo "backlight: OK        $led"
        else
            echo "backlight: NONE      no *kbd_backlight LED on this machine"
            status=1
        fi

        value=$(
            /usr/bin/busctl --system call org.freedesktop.UPower \
                /org/freedesktop/UPower/KbdBacklight \
                org.freedesktop.UPower.KbdBacklight GetBrightness 2>/dev/null
        ) || value=
        maximum=$(
            /usr/bin/busctl --system call org.freedesktop.UPower \
                /org/freedesktop/UPower/KbdBacklight \
                org.freedesktop.UPower.KbdBacklight GetMaxBrightness 2>/dev/null
        ) || maximum=
        if [ -n "$value" ] && [ -n "$maximum" ]; then
            echo "upower:   OK        level ${value##* } of ${maximum##* }"
        else
            echo "upower:   UNAVAILABLE (is upower running?)"
            status=1
        fi

        echo "bindings:"
        merge_config check || status=1
        exit "$status"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
