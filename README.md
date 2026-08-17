# zellij-switch

[![CI](https://github.com/paulomcnally/zellij-switch/actions/workflows/ci.yml/badge.svg)](https://github.com/paulomcnally/zellij-switch/actions/workflows/ci.yml)

Switch between Zellij keybinding variants for `Ctrl+P` with a single command.

Instead of reaching for a sidebar-style switcher, Zellij's default `Ctrl+P`
behavior just isn't a good pane switcher. `zellij-switch` gives you a clean
CLI that swaps your `~/.config/zellij/config.kdl` between three variants:

| Variant | `Ctrl+P` does… |
| --- | --- |
| `actual` | Creates a new pane (the original behavior) |
| `a` | Opens the native pane picker (`SwitchFocus`) — a list of all panes you navigate with ↑/↓ and confirm with `Enter` |
| `b` | Opens the **Session Manager** plugin as a floating sidebar — browse sessions → tabs → panes with ↑/↓ (and ←/→ to expand) |

The first time you use it, `zellij-switch` backs up your current config, so you
can always go back to how things were with `zellij-switch actual`.

---

## Why?

In Zellij, `Ctrl+P` is bound to pane-related actions, but moving focus between
panes usually means directional keys (spatial hopping). Many people prefer a
**menu/sidebar** where you list the panes and pick one with the arrow keys.

This repo turns that preference into a reproducible, installable CLI that you
can take to any fresh machine.

### Built for Omakub-style setups

[Omakub](https://omakub.org/) — a turnkey Ubuntu setup for developers — ships
**Zellij as its default terminal multiplexer** with its own customized,
generated config. If you use Omakub (or plan to set up a fresh machine with
it), `zellij-switch` is the quickest way to get a sidebar-style pane switcher
on top of that setup without fighting the generated config: point it at your
config, `snapshot`, `switch`, and revert to the original anytime with a single
command. The script's locked-mode/`NewPane` `Ctrl+P` scenario is directly
covered by the CI test suite, so Omakub-style configs are a first-class use
case.

> If you already ran Omakub and Zellij is configured, you only need a working
> `~/.config/zellij/config.kdl` — everything else is handled automatically.

## How it works

`zellij-switch` stores three full config files inside your Zellij config
directory, under `~/.config/zellij/variants/`:

```
~/.config/zellij/
├── config.kdl          # active config (the one Zellij actually reads)
└── variants/
    ├── actual.kdl      # pristine backup of your original config
    ├── a.kdl           # variant A: Ctrl+P = SwitchFocus (pane picker)
    └── b.kdl           # variant B: Ctrl+P = Session Manager sidebar
```

- `actual.kdl` is a **backup** of your config taken on first use. It is never
  touched again unless you run `zellij-switch snapshot`.
- `a.kdl` and `b.kdl` are **generated** from `actual.kdl` by patching only the
  single-line `bind "Ctrl p" { ... }` statement. Everything else stays identical.
- Switching a variant just copies the chosen file over `config.kdl`.

> **Note:** Zellij reads its config when a session starts. After switching, you
> must restart Zellij (or start a new session) for the new keybindings to apply.

## Requirements / Prerequisites

- **Linux or macOS** (any other OS is rejected with a clear error).
- **Zellij** installed and available in your `PATH` (`command -v zellij`).
- An existing Zellij config at `~/.config/zellij/config.kdl`
  (run `zellij setup` if you don't have one).
- **GNU sed**:
  - Linux: already present.
  - macOS: install coreutils (`brew install coreutils`) so `gsed` is available,
    or set `SED_BIN=/path/to/gsed`.
- **Bash** 4+.

## Installation

Clone the repo and install the CLI into your `PATH`:

```sh
git clone https://github.com/paulomcnally/zellij-switch.git
cd zellij-switch

# installs to ~/.local/bin/zellij-switch (add it to PATH if needed)
./zellij-switch install

# or install to a custom location
./zellij-switch install /usr/local/bin/zellij-switch
```

You can also run it directly from the repo without installing:

```sh
./zellij-switch status
```

## Usage

```
zellij-switch <command>
```

| Command | Description |
| --- | --- |
| `status` | Show which variant is currently active |
| `actual` | Restore the original config (`Ctrl+P` creates a new pane) |
| `a` | Variant A: `Ctrl+P` opens the pane picker (`SwitchFocus`) |
| `b` | Variant B: `Ctrl+P` opens the Session Manager sidebar |
| `snapshot` | Save the current config as the new `actual` baseline (rebuilds `a`/`b` from it) |
| `install [path]` | Install the script to `~/.local/bin/zellij-switch` (or `path`) |
| `help` | Show help |
| `version` | Show the version |

### Examples

```sh
# try the Session Manager sidebar
zellij-switch b
# restart Zellij, try it, and go back if you don't like it
zellij-switch actual

# try the native pane picker instead
zellij-switch a

# what am I using right now?
zellij-switch status
```

### Environment variables

| Variable | Purpose |
| --- | --- |
| `ZELLIJ_CONFIG_DIR` | Override the Zellij config directory (default: `~/.config/zellij`) |
| `SED_BIN` | Override the sed binary used for patching (default: `sed`) |

## Validations

Before doing anything, `zellij-switch` validates its environment so it fails
with a clear, actionable message instead of a cryptic one when run somewhere it
doesn't apply. It checks:

1. **Operating system** — Linux and macOS only.
2. **Zellij binary** — must be installed and in `PATH`.
3. **Config file** — `config.kdl` must exist (hint: run `zellij setup`).
4. **GNU sed** — required for multi-line patching (hint on macOS: `brew install coreutils`).
5. **Patchable config** — if your config has no single-line `bind "Ctrl p" { ... }`,
   the `a`/`b` commands fail and tell you why instead of silently doing nothing.

## Troubleshooting

- **`zellij is not installed or not in your PATH`** — install Zellij first, or
  ensure its directory is in `PATH`.
- **`no Zellij config found at ...`** — run `zellij setup` once to generate the
  default config, then retry.
- **`GNU sed is required ...`** — on macOS run `brew install coreutils`. On
  Linux you usually already have GNU sed.
- **`unable to patch variant 'a'/'b' ...`** — your `Ctrl+P` binding is not a
  single-line `bind "Ctrl p" { ... }` statement. Run `zellij-switch snapshot`,
  then edit the binding manually and snapshot again.
- **Changes don't take effect** — remember to restart Zellij or start a new
  session; keybindings are loaded at session start.
- **`status` says unknown** — your `config.kdl` has drifted (e.g. Zellij
  regenerated it, or you edited it). Run `zellij-switch snapshot` to rebase.

## Customization

`actual.kdl` is your base. If you tweak your config and want that to become the
new baseline (and have `a`/`b` rebuilt from it), run:

```sh
zellij-switch snapshot
```

This is also the right thing to do after Zellij regenerates `config.kdl`
(e.g. after `zellij setup`).

## Uninstall

```sh
rm ~/.local/bin/zellij-switch        # remove the CLI
rm -rf ~/.config/zellij/variants     # remove backups and generated variants
```

## Development

Run the script directly from the repo:

```sh
./zellij-switch status
```

The script is a single self-contained Bash file with no external dependencies
beyond Zellij, sed, and coreutils.

### Testing / CI

The scenario suite (`test/run-tests.sh`) exercises every command against
isolated sandbox config dirs — including all environment validations, the
switch/revert flow, drift detection, unpatchable configs, and a round-trip on
the genuine default config generated by Zellij itself. It also asks the real
Zellij binary (`zellij setup --check`) to parse every generated variant.

```sh
bash test/run-tests.sh
```

[GitHub Actions](.github/workflows/ci.yml) runs this suite on **Ubuntu** images
on every pull request and on every push to `main`, and lints both scripts with
[ShellCheck](https://www.shellcheck.net/).

## License

[MIT](LICENSE)