# Auto-mode

This fork adds an optional automatic mode: instead of always waiting for
Pause/Break, Easy Switcher can watch each word as you finish typing it
(on Space) and silently fix it if it looks like it was typed in the
wrong layout — the way the original Windows Punto Switcher behaves in
its default mode.

## How it decides

Nothing here needs to know what layout is "supposed" to be active. The
daemon already buffers raw keystrokes; auto-mode just decodes that
buffer twice — once as if US/EN layout was active, once as if RU was —
using a static, physical-key-position mapping between the two
(the same kind of table any Punto-like tool uses).

It also watches your configured layout-switch key(s) live, so it always
has a best guess of which of those two readings is actually on screen
right now. If that reading is not a real word (checked against
[Hunspell](http://hunspell.github.io/) dictionaries) but the other
reading is, the word gets corrected exactly the way a manual
Pause/Break correction would — same erase-switch-retype mechanism,
just triggered automatically instead of by a keypress.

If **neither** reading is a dictionary word — your own name, a brand,
`kubectl`, `gitignore`, anything Hunspell has simply never heard of —
dictionary lookup alone can't tell you anything. That's also roughly
how upstream Windows Punto Switcher works: per Russian Wikipedia, it
performs a statistical analysis of the entered character sequence and
switches layout when the letter combination is atypical for the
language being typed, rather than relying on a fixed word list. This
fork approximates the same idea with a letter-bigram model built at
startup straight from the same Hunspell `.dic` word lists (no extra
data, no extra dependency): each reading gets a smoothed log-probability
score for "does this look like a typical sequence of letters in this
language", and if the *other* reading scores clearly higher than the
one currently on screen (by more than `bigram-threshold`), it's
corrected the same way. It's a word-list frequency model, not a real
text corpus, and it only ever gets consulted when dictionary lookup
came back empty-handed both ways — known words always win over
statistics.

Both readings valid, both invalid, both dictionary-unknown but equally
(a)typical, or the word is shorter than `min-word-length` → left
alone. When in doubt, auto-mode does nothing.

## Requirements

Auto-mode needs [Hunspell](http://hunspell.github.io/) and dictionaries
for both languages, loaded dynamically at startup (no build-time
dependency):

```
# Fedora
sudo dnf install hunspell-devel hunspell-en hunspell-ru

# Debian / Ubuntu
sudo apt install libhunspell-dev hunspell-en-us hunspell-ru
```

If the dictionaries can't be loaded, auto-mode is simply unavailable
for that run (logged as an error) — manual Pause/Break correction is
unaffected either way.

## Excluding apps by window class

Auto-mode has no idea what window is focused unless you tell it to
check. Set `exclude-apps` to a comma-separated list of substrings
matched (case-insensitively) against the active window's resource
class, and auto-mode stays out of anything that matches — the
Hunspell check isn't even run:

```
exclude-apps=konsole,yakuake,code,alacritty,foot
```

Checking the active window means shelling out to a small helper on
every word, so this is capped and cached rather than run
unconditionally — see the table below.

**You almost certainly also need `active-window-user`.** This daemon
runs as root (upstream's own systemd unit never sets `User=` — see
`RunInstall` in the source, it writes `#User` as a commented-out
suggestion, not a real directive). `kdotool` needs your *logged-in
session's* DBus bus to ask KWin anything, and a root process has no
standing invitation onto that bus — no `DBUS_SESSION_BUS_ADDRESS`, no
`XDG_RUNTIME_DIR` pointing at it. Without `active-window-user` set,
every active-window check will simply fail, and because failures fail
closed (see below), auto-mode will *silently* stop correcting anything
at all the moment you set `exclude-apps` — no crash, no obvious error,
it just quietly does nothing. Set it to your own login username and
the daemon resolves your uid once at startup (via `id -u`) and routes
each check through `runuser -u <you> -- env XDG_RUNTIME_DIR=... DBUS_SESSION_BUS_ADDRESS=... kdotool ...`
so it reaches your actual session bus. Startup logs (`journalctl -u
easy-switcher`) say clearly which case you're in - check there first
if exclude-apps doesn't seem to do anything.

This piece is KDE Wayland-specific: it shells out to
[kdotool](https://github.com/jinliu/kdotool), which asks KWin for the
active window over DBus (there's no portable way to do this across
compositors). On Fedora it's packaged directly (`sudo dnf install
kdotool`). On another desktop, or without kdotool installed, either
leave `exclude-apps` empty (the default — no active-window checking at
all, no subprocess ever spawned) or point `active-window-tool` at your
own script that prints something useful to stdout given the same
`getactivewindow getwindowclassname` arguments.

## Configuration

Not yet wired into the `-c` configuration wizard — add these by hand to
`/etc/easy-switcher/default.conf`, under `[Easy Switcher]`:

| Key | Default | Meaning |
|---|---|---|
| `auto-mode-start` | `false` | Start with auto-mode already on |
| `auto-mode-key` | `70` (SCROLLLOCK) | Scancode that toggles auto-mode on/off at runtime |
| `min-word-length` | `4` | Words shorter than this are never auto-corrected |
| `start-layout` | `en` | Best guess for which layout is active when the daemon starts, before it has observed a real switch |
| `dict-en-aff` / `dict-en-dic` | `/usr/share/hunspell/en_US.{aff,dic}` | English dictionary files |
| `dict-ru-aff` / `dict-ru-dic` | `/usr/share/hunspell/ru_RU.{aff,dic}` | Russian dictionary files |
| `exclude-apps` | *(empty)* | Comma-separated substrings matched against the active window class; empty = feature off |
| `active-window-tool` | `kdotool` | Binary called as `<tool> getactivewindow getwindowclassname` |
| `active-window-user` | *(empty)* | Your login username — needed so the daemon (running as root) can reach *your* session DBus bus. See above; leaving this unset when exclude-apps is non-empty means every check fails closed. |
| `active-window-timeout-ms` | `200` | The helper is killed if it doesn't answer in time; treated as if an excluded app were focused (fail closed) |
| `active-window-cache-ms` | `400` | Re-checking is skipped for this long after the last check |
| `bigram-threshold` | `1.2` | Letter-typicality fallback for words in neither dictionary — how much more "typical" the other reading has to score before correcting anyway; lower = more aggressive |

Restart the daemon after editing the config (`sudo systemctl restart
easy-switcher`).

## Known limitations

* The decode table only fully covers the letter keys plus the
  punctuation keys that are letters in the Russian layout
  (`[`, `]`, `;`, `'`, `` ` ``). The digit row and backslash are
  intentionally left identical between the two readings — they rarely
  decide whether a word is valid, and a mistake in the shifted
  digit-row symbols is a wasted risk for something this feature
  doesn't actually depend on. Easy to extend in `InitCharTables` if
  you need it.
* `start-layout` is a guess, not a query — the daemon has no way to
  ask the OS which layout is actually active at startup. It resyncs
  itself the moment you press your real layout-switch shortcut (or
  after any correction, since correcting also switches the layout),
  so it's only ever wrong for whatever you type *before* the first
  switch of the session.
* `exclude-apps` matching is a plain substring check against the
  window class, not a real allow/deny rule language — good enough for
  "don't touch my terminal", not meant for anything fancier.
* The bigram fallback is trained on word-list frequency (how many
  *distinct dictionary words* contain a given letter pair), not real
  text corpus frequency (how often that pair actually appears in
  writing) — cheap to build from files we already need, but a real
  corpus would weight common words more sensibly. `bigram-threshold`'s
  default was picked from a handful of manually-checked examples, not
  a proper validation set; if it feels too trigger-happy or too shy in
  practice, that's a config knob, not a rebuild.