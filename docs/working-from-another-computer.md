# Working from another computer

A runbook for picking up bedit on a second machine, and for the serve/attach
(daemon/emacsclient) modes. bedit lives in **two** repos and the editor depends on
the language's `std/`, so you set up both.

| Repo | Remote | What it is |
|---|---|---|
| `brood` | `git@github.com:broodlang/brood.git` | the Brood language + `std/` (buffer, serve, ui, …) and the `nest`/`bedit` build |
| `bedit` | `git@github.com:broodlang/bedit.git` | the editor itself (pure Brood over `std/`) |

Both are pushed to `main`. `bedit` builds against the **installed** `nest`, whose
`std/` is baked in at build time — so after pulling `brood` you must reinstall `nest`
for the editor to see std changes (markers, buffer subscribe/push, `attach-display-local`).

## First-time setup on a fresh machine

```bash
# 1. clone both, side by side (bedit expects ../brood)
git clone git@github.com:broodlang/brood.git
git clone git@github.com:broodlang/bedit.git

# 2. build + install a GUI-enabled nest (heavy deps, one-time)
cd brood
./configure --with-gui && make install      # installs nest / brood / brood-lsp to ~/.local/bin

# 3. build + install the standalone editor binary
cd ../bedit
make install                                  # `nest release` → ~/.local/bin/bedit
```

Make sure `~/.local/bin` is on your `PATH`.

## Picking up after work was pushed (already set up)

```bash
cd brood       && git pull && ./configure --with-gui && make install   # if std changed
cd ../bedit && git pull && make install                            # rebuild bedit
```

If only `bedit` changed (no std change), you can skip the `brood` reinstall.

## Running the editor

```bash
nest run                      # a *scratch* buffer (uses local source + installed std)
nest run -- notes.txt         # open notes.txt (C-x C-s saves / creates it)
bedit notes.txt               # the standalone binary — same thing, no repo needed
nest test                     # the test suite   ·   nest check   # advisory type/lint
```

## Serve / attach — one editor, many windows (same machine today)

The Emacs `--daemon` / `emacsclient` model. The **daemon** runs the editor; **clients**
paint its frames and ship back keys. As of the latest push, `--serve` *also opens the
host's own window* by default, so serving isn't blind.

```bash
# host: serve AND open your own window (others can attach)
bedit --name ed --serve notes.txt

# host: SHARED — everyone edits the SAME document, each with their OWN cursor
bedit --name ed --serve --shared --as wilhelm notes.txt

# host: headless — no local window, a pure background daemon (displayless server, or a
#       daemon that should outlive your window). Ctrl-C to stop.
bedit --name ed --serve --headless notes.txt

# another terminal on the SAME machine: open a window attached to the daemon
bedit --attach ed --as alice

# …or draw it in THIS terminal (emacsclient -nw): also what --attach does by itself
# where there is no display, e.g. over ssh; kills reach your clipboard via OSC 52
bedit --attach ed --as alice -nw
```

- `--serve` alone → each client gets its **own** buffer (independent sessions).
- `--serve --shared` (alias `--collab`) → THE collaborative mode: shared *content* (one
  buffer process serializes all edits) while each client keeps its own cursor, panes, and
  minibuffer. A late joiner syncs to the live document, not the file on disk. **Presence**:
  everyone else's caret renders live as a coloured bar with a name tag; joins/leaves are
  echoed; a detached/crashed participant's caret is cleaned up, never a ghost. Fast typing
  never flickers under its own round-trip (origin-tagged echo suppression).
- **Every file is shared.** Any file buffer any participant visits is auto-backed by one
  shared process (the daemon's file registry) — so you can roam a whole project together,
  not just the launch file.
- **`share-follow` (`C-x f`)** — ride a participant's caret: your point AND buffer track
  theirs (switching files with them). With one other person it follows immediately; with
  more it prompts by name. Any move of your own takes the wheel back; `C-x f` again stops.
- **`share-mirror` (`C-x F`)** — like share-follow, but your window also reproduces their
  viewport (scroll), so you see exactly what they see — the classic one-view pairing.
- **`M-x share-session` / `M-x share-session-stop`** — start/stop hosting from a NORMAL
  running editor (no --serve needed): it becomes the daemon `bedit --attach bedit` reaches.
- **Names**: `--as NAME` → `:share-name "you"` in `~/.config/bedit/init.blsp` → your
  OS username; `share-session` prompts if none is set. Name tags show quietly — only for a
  few seconds after that caret moves; the coloured bar stays.
- `M-x collab-status` echoes who's here and what you're following.
- Close the host window to stop serving (use `--headless` for a daemon that persists).

## Over the network — `--listen`

Every attach is a Brood **node link**, and node links run over TCP. `--listen
[HOST:]PORT` makes the daemon listen on TCP as well as the per-user Unix socket:

```bash
# host machine: it prints the attach command, with a fresh GUEST cookie for this session
bedit --name ed --serve --shared --listen 0.0.0.0:7457 --as wilhelm notes.txt
#   attach:  BEDIT_COOKIE=3f9c… bedit --attach ed@0.0.0.0:7457 [--as NAME]

# any machine that can reach it (substitute the host's address for 0.0.0.0):
BEDIT_COOKIE=3f9c… bedit --attach ed@HOST:7457 --as alice

# or keep the cookie in an owner-only file (bedit refuses a file others can read)
umask 077; echo 3f9c… > ~/.config/bedit/state/ed.cookie
bedit --attach ed@HOST:7457 --cookie-file ~/.config/bedit/state/ed.cookie
```

- A bare port binds **loopback only** (`127.0.0.1`); to be reachable from another machine,
  say so: `0.0.0.0:PORT` (every interface) or `HOST:PORT` (one).
- **The cookie is a guest cookie, minted per session** (brood ADR-415), not the machine's
  `~/.config/brood/cookie`. It reaches only the session server: it cannot ship code or
  reach your other Brood nodes. `--invite alice,bob` mints one per person with the name
  bound, so the daemon knows who attached rather than taking `--as` on trust. The machine
  cookie still links two of your own machines with full trust; never hand it out.
- **Pass the cookie in the environment (`BEDIT_COOKIE`) or a file (`--cookie-file PATH`,
  mode 0600), not as `--cookie VALUE`.** A command line is visible to every user on the
  machine through `ps`; a process's environment is readable only by its owner (and root).
  `--cookie VALUE` still works, and warns on stderr that it was visible. Precedence:
  `--cookie-file`, then `$BEDIT_COOKIE`, then `--cookie`.
- **Node links are encrypted.** Every link, TCP and Unix socket alike, is authenticated by
  an HMAC over the cookie (the cookie itself never goes on the wire), then runs an
  ephemeral X25519 key exchange folded into that HMAC, and seals every frame with
  ChaCha20-Poly1305 (brood ADR-089, `crates/lisp/src/dist.rs` "Channel security"). An
  observer on the network sees neither your keys nor your text, a forged or altered frame
  fails its tag and ends the link, and the per-link ephemeral keys give forward secrecy. So
  `--listen 0.0.0.0` across machines is safe on an untrusted network **as long as the
  cookie stays secret**: the cookie is the only credential, there is no certificate, and
  anyone who holds it is a guest of the session. It is not a defence against someone who
  can read the cookie (a shared terminal log, a chat message, shell history).
- Dual-listen: the per-user Unix socket stays bound alongside TCP, so local attaches
  keep the bare-NAME form (and need no cookie: the machine's own reaches them) while remote
  machines use `@HOST:PORT`.
- Verified over a real TCP link (loopback: two runtimes, full presence + edit fan-out);
  cross-machine is the same code path — try it from the second machine.

## Editing a file on a machine that has no bedit (`/ssh:`)

The serve/attach modes need bedit on both ends. To edit a file on a server that has only
`sshd` and a POSIX `sh`, visit it by its TRAMP path, as in Emacs:

```
C-x C-f /ssh:web1:/etc/nginx/nginx.conf
C-x C-f /ssh:deploy@web1#2222:~/app/.env      # a user, a port; ~ is the REMOTE home
C-x C-f /ssh:web1:~www/site/index.html        # another user's home there
C-x C-f /ssh:[fe80::1]:/etc/hosts             # an IPv6 host in brackets
C-x C-f /ssh:bastion|ssh:db1:/etc/my.cnf      # through a jump host (TRAMP's multi-hop)
C-x d   /ssh:web1:/var/log/                   # a remote directory in dired
```

- **What it runs.** The system `ssh`, with your `~/.ssh/config` (host aliases, `ProxyJump`,
  `IdentityFile`) and your agent. Every operation shares one connection per host (OpenSSH's
  `ControlMaster`; the socket is under `~/.config/bedit/state/ssh/`, owner-only, and lives
  five minutes past the last use). Nothing is installed on the host: each operation is a short
  `/bin/sh` script sent on ssh's standard input, so the account's login shell (bash, zsh,
  fish) never parses a path, and a file name with spaces, quotes or `$` is safe.
- **Jump hosts.** `/ssh:bastion|ssh:db1:PATH` reaches db1 through bastion (any number of
  hops, each `[user@]host[#port]`): bedit hands ssh a `ProxyCommand` that runs `ssh -W` to
  each hop in turn, in batch mode like everything else — so a jump host is reached with a key
  or your agent, never a password. (ssh's own `-J` passes none of bedit's options on to the
  jump, so a hop wanting a password would prompt on a terminal.) A `ProxyJump` in your
  `~/.ssh/config` keeps working as it always does.
- **Opening.** A `Loading…` buffer appears at once and the file replaces it when ssh answers;
  C-g stops it. The bytes come through `base64`, so the file's coding is detected as any
  file's is: a binary opens as the read-only hex view, and a file past
  `:large-file-warning-threshold` is asked about before it is sent. In the find-file prompt,
  Tab completes a remote directory's entries (listed over ssh, kept 10 s).
- **Directories.** A remote directory opens in dired, listed over ssh with the same `ls -l`
  columns and sorting (`s`) as a local one. RET visits a file or enters a directory, `^` goes
  up, `g` lists it again; `+` makes a directory, `R` moves and `C` copies (marked entries or
  the one at point, a directory with everything in it) within that host, and `D` / `x` delete
  — for good, after a question that says so: there is no trash on the other machine. A move
  or copy never replaces an entry already there (it is reported, not asked about: the far
  disk cannot be asked from the editor's loop), and it stays on the one host. Each operation
  runs off the loop; a buffer visiting a moved file follows it, one visiting a deleted file
  is kept and marked modified.
- **Saving.** C-x C-s writes the file back atomically — staged in the file's directory with
  the file's mode, checked by size and SHA-256, then renamed over it — and the buffer stays
  modified until the write has landed. A connection that drops is said in the echo area and
  the buffer stays modified; C-x C-s again once it is back. C-x C-c asks about remote files as
  about any, and saves them after its questions. M-x revert-buffer and C-x RET r read the file
  again; C-x C-w to an `/ssh:` path moves a buffer there. The mode line shows `@host`.
- **Passwords and host keys.** ssh runs in batch mode, so it never waits on a prompt. A host
  that refuses every key but takes a password gets one asked for, masked, in the minibuffer;
  it opens the shared connection (through an `SSH_ASKPASS` helper reading it from ssh's own
  input — never the environment or a file; OpenSSH 8.4 or newer) and is kept nowhere. A host
  key that is not yet known, or has CHANGED, is never accepted: bedit says so, and you check
  it with `ssh host` in a terminal.
- **What stays local.** The auto-save sidecar is private, under
  `~/.config/bedit/state/auto-save/`, named for the TRAMP path (M-x recover-session lists it).
  Auto-revert, the diff-hl gutter, language servers, the formatter, `.editorconfig`,
  `.bedit-locals.blsp`, `M-x compile`, `M-!` and the project commands leave a remote buffer
  alone: they would run here, on a path that exists only there.
- **Proven against a real sshd.** CI's `ssh-real` job (tools/ci/ssh-real.sh) runs OpenSSH's
  server on localhost and drives all of the above through the real `ssh`: key and password
  logins, a jump host, an unknown host key, dired's operations, and sshd killed mid-session.
- **Not there yet.** A password for a jump host; a file moved or copied from one host to
  another, or between a host and this machine; replacing an existing entry from dired (asked
  about locally, refused remotely); C-x C-j from a remote file lands on the listing's first
  entry rather than the file; and hops other than `ssh:` (TRAMP's `sudo:` as the last hop).

## Collaboration status (what's built vs runnable)

| Capability | State |
|---|---|
| Remote attach + host window (`--serve`, private session per client) | ✅ |
| Shared editing, own cursor each (`--serve --shared`, alias `--collab`) | ✅ |
| Presence: named, coloured remote carets + join/leave echoes (`--as`) | ✅ |
| `follow` (C-x f): ride a participant's caret — the pairing view | ✅ |
| Echo suppression (own round-trip never flickers fast typing) | ✅ |
| Cross-machine over TCP (`--listen`, guest cookie, encrypted link) | ✅ (loopback-verified; try your second machine) |
| Delta pushes (splices/marker moves on the wire — the document never ships) | ✅ |
| Concurrent typing merges exactly (OT for disjoint edits; same-span resyncs) | ✅ |
| Shared selections (everyone's region, tinted in their colour) | ✅ |
| Modeline presence chip (`shared: alice, bob → alice`) | ✅ |
| Kernel dual-listen (Unix socket *and* TCP at once) | ✅ |
| `share-session-stop` fully tears down (sessions, registry, buffer procs) | ✅ |

The independent-cursor collab layer (a shared buffer process, positional-splice edits,
per-pane cursors — `src/collab.blsp`) is live as `--serve --collab`: each attaching client
gets its own session whose buffer is backed by the daemon's one buffer process, so edits
serialize with no CRDT while every cursor stays independent (see
`docs/remote-multiplayer-plan.md` for the architecture).

## Verify a setup is good

```bash
cd brood       && cargo run -q -p nest -- test tests/buffer_test.blsp   # markers + subscribe/push
cd ../bedit && nest test                                            # whole editor (~771 tests)
```

All green ⇒ the language foundation and the editor are in sync on this machine.
