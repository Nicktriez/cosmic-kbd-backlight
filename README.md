# cosmic-kbd-backlight

Makes the keyboard backlight brightness keys work on the COSMIC desktop.

## The problem

COSMIC recognises the keyboard backlight keys — F5/F6 on Apple keyboards, the
equivalent keys elsewhere — but does nothing with them, for two reasons:

- the settings daemon's keyboard-brightness controls are unimplemented
  placeholders, so there is nothing for the keys to call;
- the keys have no default assignment.

The backlight itself works fine: the battery applet's slider already drives it.

## What this does

Binds `XF86KbdBrightnessDown` and `XF86KbdBrightnessUp` to a small helper that
steps the backlight by 5% through UPower's `KbdBacklight` interface — the same
route the battery applet uses. Because the write goes through UPower, the
existing on-screen indicator appears as well.

Nothing is hardcoded to particular hardware: whatever `*kbd_backlight` device the
machine exposes is used, so it works on Apple, System76, ThinkPad and others.

## Install

```sh
./install.sh            # install (idempotent — also repairs)
./install.sh verify     # report the current state, change nothing
./install.sh uninstall  # remove everything it installed
./install.sh help       # usage
```

Everything is installed under your home directory, so OS and desktop updates do
not disturb it:

| path | purpose |
|---|---|
| `~/.local/bin/cosmic-kbd-backlight` | the helper that steps the backlight |
| `~/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom` | the two key bindings |
| `~/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions` | the commands those actions run |

`install.sh` merges rather than replaces: any other custom shortcuts you have are
preserved, and if one of these two entries has been given a modifier it is put
back to unmodified.

## Caveat

COSMIC Settings' shortcut editor cannot record these keys — it attaches a
modifier (for example `Super`) and rewrites the file in its own format. If the
keys stop working after visiting that page, run `./install.sh repair`.

## Options

`INSTALL_BIN_DIR` overrides where the helper is installed and `XDG_CONFIG_HOME`
overrides the config root. Both are mainly useful for testing in a sandbox.

## License

MIT — see [LICENSE](LICENSE). Use it, change it, ship it.

## Upstream

This is a workaround, not the real fix. The proper solution belongs in
`cosmic-settings-daemon`:

- https://github.com/pop-os/cosmic-settings-daemon/issues/115
- https://github.com/pop-os/cosmic-epoch/issues/2925

Once that is implemented, run `./install.sh uninstall`.
