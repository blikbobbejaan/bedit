#!/usr/bin/env bash
# bedit's `/ssh:` editing against a REAL sshd (.github/workflows/ci.yml, `ssh-real`): an sshd on
# localhost on a high port with a throwaway host key and config, ssh host aliases for every
# case the driver needs, then tools/ci/ssh-real.blsp, which drives sshremote / sshedit /
# remotejob / dired through the system ssh and says what each check proves.
#
#   tools/ci/ssh-real.sh NEST OUT-DIR [ci|local]
#
#   ci     (the default) sshd runs as ROOT through sudo — the only way it can check a password —
#          and a throwaway user `bedittest` with a random password is made for the password
#          login (and allowed sudo WITH that password, for the `|sudo:` hop's password; a
#          root-only file is staged for the runner's own passwordless sudo). Root gets a password
#          for the run (the `|su:` hop; locked again after), and where doas is installed a
#          doas.conf of the run's own (`nopass` for you, a password for `bedittest`). With
#          BEDIT_SSH_SUDO naming another sudo binary (sudo-rs), it is installed setuid as
#          /usr/local/bin/sudo for the run — first on an ssh session's PATH — so the `|sudo:`
#          checks run against it (BEDIT_SSH_ONLY=root runs just the root hops). The aliases go into
#          ~/.ssh/config, which the driver's plain `ssh` reads, as a user's would. Nothing else
#          of the machine is changed: the system's own sshd, if any, keeps its port and config.
#   local  sshd runs as YOU (no sudo, no new user, ~/.ssh untouched): key logins only, so the
#          password check is skipped. The aliases go into a config file of the run's own that
#          a wrapper hands ssh with -F. SSHD names the sshd binary (default /usr/sbin/sshd);
#          SSHD_SESSION / SSHD_AUTH name sshd-session / sshd-auth for an sshd unpacked
#          somewhere else (OpenSSH 9.8+ runs them by path).
#
# OUT-DIR gets sshd.log (the server's own account of every connection) and driver.log.
# BEDIT_SSH_PORT picks the port (default 2222).
set -euo pipefail

nest="${1:?usage: ssh-real.sh NEST OUT-DIR [ci|local]}"
out="${2:?usage: ssh-real.sh NEST OUT-DIR [ci|local]}"
mode="${3:-ci}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
port="${BEDIT_SSH_PORT:-2222}"
sshd="${SSHD:-/usr/sbin/sshd}"
me="$(id -un)"

stage="$(mktemp -d /tmp/bedit-ssh-stage.XXXXXX)"
chmod 755 "$stage"
# the `|sudo:` hop's root-only file (ci mode)
root_file="$stage/root-only.conf"

case "$mode" in
  # the system's own sudo by its path: BEDIT_SSH_SUDO may put another first on PATH below
  ci) as_root="$(command -v sudo)" ;;
  local) as_root= ;;
  *) echo "ssh-real.sh: unknown mode '$mode' (ci or local)" >&2; exit 2 ;;
esac

# ---- the server: a host key, a config, a key to log in with -----------------------------
ssh-keygen -q -t ed25519 -N '' -C bedit-ssh-real-host -f "$stage/host_key"
ssh-keygen -q -t ed25519 -N '' -C bedit-ssh-real-client -f "$stage/client_key"
cp "$stage/client_key.pub" "$stage/authorized_keys"
chmod 644 "$stage/authorized_keys"

{
  echo "Port $port"
  echo "ListenAddress 127.0.0.1"
  # the hop target's address: a second loopback name, so its connection is not the key host's
  echo "ListenAddress 127.0.0.2"
  # the unknown host key's address: a third, so no connection already made is reused for it
  echo "ListenAddress 127.0.0.3"
  echo "HostKey $stage/host_key"
  echo "PidFile $stage/sshd.pid"
  echo "AuthorizedKeysFile $stage/authorized_keys"
  echo "StrictModes no"
  echo "PubkeyAuthentication yes"
  echo "KbdInteractiveAuthentication no"
  echo "PermitRootLogin no"
  echo "AllowTcpForwarding yes"
  echo "LogLevel VERBOSE"
  if [ "$mode" = ci ]; then
    echo "PasswordAuthentication yes"
    echo "UsePAM yes"
  else
    echo "PasswordAuthentication no"
    echo "UsePAM no"
    [ -n "${SSHD_SESSION:-}" ] && echo "SshdSessionPath $SSHD_SESSION"
    [ -n "${SSHD_AUTH:-}" ] && echo "SshdAuthPath $SSHD_AUTH"
  fi
} >"$stage/sshd_config"

if [ "$mode" = ci ]; then
  sudo mkdir -p /run/sshd
  sudo chmod 755 /run/sshd
fi
$as_root "$sshd" -t -f "$stage/sshd_config"

# `stop` kills the server and every session it holds — the network gone, as a dropped link
# looks to ssh — and `start` brings it back; the driver's dropped-connection check runs them
cat >"$stage/sshd-ctl" <<EOF
#!/usr/bin/env bash
set -u
case "\$1" in
  stop)
    pid="\$(cat "$stage/sshd.pid" 2>/dev/null || true)"
    if [ -n "\$pid" ]; then
      $as_root pkill -9 -P "\$pid" || true
      $as_root kill -9 "\$pid" || true
    fi
    # the sessions' unprivileged halves, which hold the client's socket too
    $as_root pkill -9 -f "^sshd(-session)?: ${me}" || true
    $as_root rm -f "$stage/sshd.pid"
    ;;
  start)
    $as_root "$sshd" -f "$stage/sshd_config" -E "$out/sshd.log"
    for _ in \$(seq 100); do
      if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then exit 0; fi
      sleep 0.1
    done
    echo "sshd did not come up on port $port" >&2
    exit 1
    ;;
esac
EOF
chmod 755 "$stage/sshd-ctl"

# what the run changed of the machine beyond the stage, undone by `cleanup`
sudo_placed=
doas_conf_made=
root_password_set=
ssh_config_touched=

cleanup() {
  if [ -n "$ssh_config_touched" ]; then
    if [ -e "$stage/ssh_config.before" ]; then cp "$stage/ssh_config.before" ~/.ssh/config; else rm -f ~/.ssh/config; fi
  fi
  if [ -n "$sudo_placed" ]; then "$as_root" rm -f /usr/local/bin/sudo || true; fi
  "$stage/sshd-ctl" stop >/dev/null 2>&1 || true
  if [ "$mode" = ci ]; then
    "$as_root" userdel -r bedittest >/dev/null 2>&1 || true
    "$as_root" rm -f /etc/sudoers.d/bedittest "$root_file" || true
    if [ -n "$doas_conf_made" ]; then "$as_root" rm -f /etc/doas.conf || true; fi
    if [ -n "$root_password_set" ]; then "$as_root" passwd -l root >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$stage"
}
trap cleanup EXIT

# made here, so a root sshd appends to a log the runner can read and upload
: >"$out/sshd.log"
"$stage/sshd-ctl" start

# ---- the client: known hosts and the aliases ---------------------------------------------
host_key_line="$(cut -d' ' -f1,2 "$stage/host_key.pub")"
{
  echo "[127.0.0.1]:$port $host_key_line"
  echo "[127.0.0.2]:$port $host_key_line"
} >"$stage/known_hosts"
: >"$stage/empty_known_hosts"

aliases() {
  local identity="IdentityFile $stage/client_key"
  cat <<EOF
# bedit ssh-real ($stage)
Host bedit-key
  HostName 127.0.0.1
  Port $port
  User $me
  $identity
  IdentitiesOnly yes
  PasswordAuthentication no
  UserKnownHostsFile $stage/known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
Host bedit-inner
  HostName 127.0.0.2
  Port $port
  User $me
  $identity
  IdentitiesOnly yes
  PasswordAuthentication no
  UserKnownHostsFile $stage/known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
  # never reached directly: only through a jump host
  ProxyCommand /bin/false
Host bedit-unknown
  HostName 127.0.0.3
  Port $port
  User $me
  $identity
  IdentitiesOnly yes
  UserKnownHostsFile $stage/empty_known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
Host bedit-pw
  HostName 127.0.0.1
  Port $port
  User bedittest
  PubkeyAuthentication no
  IdentitiesOnly yes
  UserKnownHostsFile $stage/known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
EOF
}

export BEDIT_SSH_KEY_HOST=bedit-key
export BEDIT_SSH_HOP_TARGET=bedit-inner
export BEDIT_SSH_UNKNOWN_HOST=bedit-unknown
export BEDIT_SSH_CTL="$stage/sshd-ctl"

if [ "$mode" = ci ]; then
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  # kept as it was, put back by `cleanup`: a second run in the same job must not find this
  # run's aliases (their keys gone with the stage) ahead of its own
  if [ -e ~/.ssh/config ]; then cp ~/.ssh/config "$stage/ssh_config.before"; fi
  ssh_config_touched=1
  aliases >>~/.ssh/config
  chmod 600 ~/.ssh/config
  # the password login's user, a password nobody else knows, a file in its home
  password="bedit-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sudo useradd -m -s /bin/sh bedittest
  echo "bedittest:$password" | sudo chpasswd
  sudo chmod 755 /home/bedittest
  echo "the password user's file" | sudo tee /home/bedittest/pw.txt >/dev/null
  sudo chown bedittest: /home/bedittest/pw.txt
  sudo chmod 644 /home/bedittest/pw.txt
  export BEDIT_SSH_PW_HOST=bedit-pw
  export BEDIT_SSH_PASSWORD="$password"
  export BEDIT_SSH_PW_FILE=/home/bedittest/pw.txt
  export BEDIT_SSH_OTHER_USER=bedittest
  export BEDIT_SSH_OTHER_FILE=pw.txt
  # the `|sudo:` hop: a file only root may read, reached through the runner's passwordless
  # sudo; and the password user may sudo with its password, which sudo -S is handed
  printf 'root only\n' | sudo tee "$root_file" >/dev/null
  sudo chown root:root "$root_file"
  sudo chmod 600 "$root_file"
  echo "bedittest ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/bedittest >/dev/null
  sudo chmod 440 /etc/sudoers.d/bedittest
  export BEDIT_SSH_ROOT_FILE="$root_file"
  export BEDIT_SSH_SUDO_PASSWORD=1
  # the `|su:` hop: root's password, set for this run and locked again by `cleanup`
  root_password="bedit-root-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo "root:$root_password" | sudo chpasswd
  root_password_set=1
  export BEDIT_SSH_ROOT_PASSWORD="$root_password"
  # the `|doas:` hop, where doas is installed and no doas.conf is there already: the key host's
  # user with `nopass`, the password user with its password
  if command -v doas >/dev/null 2>&1 && [ ! -e /etc/doas.conf ]; then
    printf 'permit nopass %s as root\npermit bedittest as root\n' "$me" | sudo tee /etc/doas.conf >/dev/null
    doas_conf_made=1
    sudo chown root:root /etc/doas.conf
    sudo chmod 0400 /etc/doas.conf
    export BEDIT_SSH_DOAS=1
  fi
  # another sudo as the host's (sudo-rs): installed setuid root first on PATH for this run — an
  # ssh session's PATH puts /usr/local/bin before /usr/bin — and removed by `cleanup`. The
  # driver checks the host's `sudo --version` names BEDIT_SSH_SUDO_EXPECT before the `|sudo:`
  # checks run.
  if [ -n "${BEDIT_SSH_SUDO:-}" ]; then
    if [ -e /usr/local/bin/sudo ]; then echo "ssh-real.sh: /usr/local/bin/sudo is there already" >&2; exit 2; fi
    sudo install -o root -g root -m 4755 "$BEDIT_SSH_SUDO" /usr/local/bin/sudo
    sudo_placed=1
    export BEDIT_SSH_SUDO_EXPECT="${BEDIT_SSH_SUDO_EXPECT:-sudo-rs}"
    echo "== the host's sudo for this run: $(/usr/local/bin/sudo --version 2>&1 | head -1)"
  fi
else
  aliases >"$stage/ssh_config"
  printf '#!/bin/sh\nexec ssh -F %s "$@"\n' "$stage/ssh_config" >"$stage/ssh"
  chmod 755 "$stage/ssh"
  export BEDIT_SSH_PROGRAM="$stage/ssh"
  # another user's home: your own, spelled `~you/…`
  echo "your own file" >"$stage/mine.txt"
  export BEDIT_SSH_OTHER_USER="$me"
  export BEDIT_SSH_OTHER_FILE="$(realpath --relative-to="$HOME" "$stage/mine.txt" 2>/dev/null || echo .profile)"
fi

echo "== ssh-real ($mode): sshd $("$sshd" -V 2>&1 | head -1 || true) on 127.0.0.1:$port; $(ssh -V 2>&1)"
set +e
"$nest" run tools/ci/ssh-real.blsp 2>&1 | tee "$out/driver.log"
code="${PIPESTATUS[0]}"
set -e
if [ "$code" != 0 ]; then
  echo "== ssh-real FAILED (exit $code): $out/driver.log, and the server's side in $out/sshd.log" >&2
  tail -n 60 "$out/sshd.log" >&2 || true
fi
exit "$code"
