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
#          login. The aliases go into ~/.ssh/config, which the driver's plain `ssh` reads, as a
#          user's would. Nothing else of the machine is changed: the system's own sshd, if any,
#          keeps its port and config.
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

case "$mode" in
  ci) as_root=sudo ;;
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

cleanup() {
  "$stage/sshd-ctl" stop >/dev/null 2>&1 || true
  if [ "$mode" = ci ]; then sudo userdel -r bedittest >/dev/null 2>&1 || true; fi
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
