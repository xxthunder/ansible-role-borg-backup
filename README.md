# Ansible Role: borg-backup

[![CI](https://github.com/xxthunder/ansible-role-borg-backup/actions/workflows/test.yml/badge.svg)](https://github.com/xxthunder/ansible-role-borg-backup/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ansible](https://img.shields.io/badge/Ansible-2.11%2B-blue.svg)](https://docs.ansible.com/)
[![ansible-lint](https://img.shields.io/badge/ansible--lint-passing-brightgreen.svg)](https://ansible.readthedocs.io/projects/lint/)

Daily encrypted offsite [borg](https://www.borgbackup.org/) backup for a Debian
host, driven by a hardened systemd timer. The role:

- Installs a pinned `borgbackup` apt package.
- Deploys an SSH private key plus a **pinned** `known_hosts` for the remote repo
  host (host-key auto-trust is refused).
- Deploys the borg keyfile and passphrase as root-only `0400` files.
- Templates two wrapper scripts under `/usr/local/sbin/`:
  - `borg-create` — run by the daily timer.
  - `borg-prune` — manual only (see [Pruning](#pruning)).
- Installs a systemd `oneshot` service + daily timer.
- *(Optional)* Wires [Healthchecks.io](https://healthchecks.io/) dead-man's-switch
  pings — a success ping at the end of each run and an `OnFailure=` fail ping —
  when `borg_backup_healthchecks_uuid` is set (see
  [Optional: Healthchecks](#optional-healthchecks)).

The role is deliberately decoupled from any specific provider: the repo URL, SSH
port, schedule, retention, sources, and pinned host keys are all caller-supplied.

## Requirements

- A Debian host (bullseye/bookworm) with `borgbackup` installable via apt and a
  working `systemd`.
- An **already-initialized** borg repository reachable over SSH. Create it once,
  out of band, from a trusted workstation — the role never runs `borg init`:

  ```sh
  borg init --encryption=keyfile-blake2 --append-only ssh://user@host:port/./repo
  ```

  `--append-only` lets the unattended host add archives but not delete history,
  so a compromised host cannot wipe the offsite copy. With an append-only repo,
  pruning is a deliberate manual operation — see [Pruning](#pruning).
- The repo's encryption **keyfile** (`borg key export`) and **passphrase**,
  supplied to the role as variables (see [secrets](#required-secrets)). In
  keyfile mode the keyfile *is* the master key — store it somewhere durable and
  separate from the host being backed up.
- *(Optional)* A free [Healthchecks.io](https://healthchecks.io/) check (daily
  schedule, grace period ≥ 2 h) for dead-man's-switch alerting. Supply its UUID
  to turn the integration on — see [Optional: Healthchecks](#optional-healthchecks).
- The remote host's pinned SSH host keys (see
  [`borg_backup_remote_known_hosts`](#required-operational-variables)). Generate the
  YAML block with the bundled helper, then cross-check the printed fingerprints
  against the provider's published list before trusting them:

  ```sh
  scripts/fetch_remote_host_keys.sh host:port
  ```

## Role Variables

### Required operational variables

These have **no default** by design — a wrong fallback on a backup role is
dangerous, so they fail loud when unset. Set them in your `group_vars`/playbook.

| Variable | Type | Description |
|---|---|---|
| `borg_backup_repo` | str | Repository URL, e.g. `ssh://user@host:port/./repo`. |
| `borg_backup_sources` | list[str] | Absolute paths on the host to back up. |
| `borg_backup_package_version` | str | Pinned apt version of `borgbackup` (e.g. `1.2.4-1`). 1.2.x and 1.4.x share the repo format; 2.0+ does not — do not cross that boundary on an existing repo. |
| `borg_backup_upload_ratelimit_mbit` | int | Upload cap in Mbit/s; converted to borg's `--upload-ratelimit` (KiB/s) in the wrapper. |
| `borg_backup_create_oncalendar` | str | systemd `OnCalendar` expression (e.g. `*-*-* 03:30:00`). |
| `borg_backup_create_timezone` | str | IANA timezone appended to `OnCalendar` (systemd ≥ 240), e.g. `Europe/Berlin`. |
| `borg_backup_prune_keep_daily` | int | `--keep-daily` for the manual prune wrapper. |
| `borg_backup_prune_keep_weekly` | int | `--keep-weekly` for the manual prune wrapper. |
| `borg_backup_prune_keep_monthly` | int | `--keep-monthly` for the manual prune wrapper. |
| `borg_backup_prune_keep_yearly` | int | `--keep-yearly` for the manual prune wrapper. |
| `borg_backup_remote_known_hosts` | list[str] | Pinned SSH host-key lines for the remote repo host. The role refuses to deploy when empty. Generate with `scripts/fetch_remote_host_keys.sh`. |

### Required secrets

Supply these via your vault layer (e.g. `ansible-vault`); all are `no_log`.

| Variable | Description |
|---|---|
| `borg_backup_passphrase` | Borg repo passphrase. |
| `borg_backup_keyfile` | Exported borg keyfile contents (`borg key export`). |
| `borg_backup_ssh_private_key` | SSH private key used to reach the remote repo host. |

### Optional: Healthchecks

Healthchecks.io dead-man's-switch pinging is **optional and presence-based** —
set `borg_backup_healthchecks_uuid` to enable it. When set, the role deploys the
UUID, sends a success ping at the end of each run, and wires the unit's
`OnFailure=` to a fail ping. When unset, all of it is skipped (no UUID file, no
`curl` dependency, no `OnFailure` unit).

| Variable | Default | Description |
|---|---|---|
| `borg_backup_healthchecks_uuid` | _(unset)_ | Healthchecks.io check UUID (`no_log`). Setting it enables the integration. |
| `borg_backup_healthchecks_base_url` | `https://hc-ping.com` | Base URL for pings; only used when the UUID is set. |

### Defaults (override only if needed)

Defined in `defaults/main.yml`; the values below are the defaults.

| Variable | Default | Description |
|---|---|---|
| `borg_backup_user` | `root` | Local user that owns the borg files and runs the units. |
| `borg_backup_user_home` | `/root` | Home of `borg_backup_user`; base for the path defaults. |
| `borg_backup_ssh_dir` | `{{ borg_backup_user_home }}/.ssh` | SSH directory for the key and known_hosts. |
| `borg_backup_ssh_private_key_path` | `{{ borg_backup_ssh_dir }}/borg_ed25519` | On-disk path of the SSH private key. |
| `borg_backup_known_hosts_path` | `{{ borg_backup_ssh_dir }}/known_hosts` | On-disk path of the pinned known_hosts. |
| `borg_backup_ssh_port` | `22` | SSH port for the remote repo. Override when the provider uses a non-standard port. |
| `borg_backup_keyfile_dir` | `{{ borg_backup_user_home }}/.config/borg/keys` | Directory for the repo-agnostic keyfile. |
| `borg_backup_keyfile_path` | `{{ borg_backup_keyfile_dir }}/repo.key` | Stable path pointed to by `BORG_KEY_FILE`. |
| `borg_backup_security_dir` | `{{ borg_backup_user_home }}/.config/borg/security` | Borg per-repo security/manifest dir (writable from the hardened unit). |
| `borg_backup_secrets_dir` | `/etc/borg` | Holds the `0400` passphrase and Healthchecks UUID files. |
| `borg_backup_create_script` | `/usr/local/sbin/borg-create` | Path of the create wrapper. |
| `borg_backup_prune_script` | `/usr/local/sbin/borg-prune` | Path of the prune wrapper. |
| `borg_backup_create_service` | `borg-create.service` | systemd oneshot service name. |
| `borg_backup_create_timer` | `borg-create.timer` | systemd timer name. |
| `borg_backup_failure_service` | `borg-failure@.service` | Templated OnFailure ping unit name. |

`meta/argument_specs.yml` is the authoritative, complete variable surface and is
validated at role start, so a missing or mistyped variable fails fast with a
clear message.

## Example Playbook

```yaml
- hosts: backup_hosts
  become: true
  vars:
    borg_backup_repo: "ssh://user@host:port/./repo"
    borg_backup_ssh_port: 22
    borg_backup_sources:
      - /srv/data
      - /etc
    borg_backup_package_version: "1.2.4-1"
    borg_backup_upload_ratelimit_mbit: 30
    borg_backup_create_oncalendar: "*-*-* 03:30:00"
    borg_backup_create_timezone: "Europe/Berlin"
    borg_backup_healthchecks_base_url: "https://hc-ping.com"
    borg_backup_prune_keep_daily: 7
    borg_backup_prune_keep_weekly: 4
    borg_backup_prune_keep_monthly: 6
    borg_backup_prune_keep_yearly: 2
    borg_backup_remote_known_hosts:
      - "[host]:port ssh-ed25519 AAAA..."
    # Supply these from your vault, never in plaintext:
    borg_backup_passphrase: "{{ vault_borg_backup_passphrase }}"
    borg_backup_keyfile: "{{ vault_borg_backup_keyfile }}"
    borg_backup_ssh_private_key: "{{ vault_borg_backup_ssh_private_key }}"
    borg_backup_healthchecks_uuid: "{{ vault_borg_backup_healthchecks_uuid }}"
  roles:
    - borg-backup
```

## Restore

Restoring requires **both** the passphrase and the keyfile — either alone is
insufficient. From any borg-equipped machine with network access:

```sh
export BORG_REPO="ssh://user@host:port/./repo"
export BORG_RSH="ssh -p port -i /path/to/borg_ed25519"
export BORG_PASSPHRASE="..."
export BORG_KEY_FILE="/path/to/exported/keyfile"

borg list                                  # archives, one per run
borg list "::<archive>"                    # files in an archive
borg extract --dry-run --list "::<archive>" path/prefix   # preview
borg extract "::<archive>" path/prefix     # restore (cwd-relative)
```

A clean `borg extract` exit is itself an integrity proof — borg verifies every
chunk hash on the way out. To browse interactively, `borg mount "::<archive>"
/mnt/point` (needs a FUSE binding the apt package only *recommends*; install
`python3-pyfuse3` if mount reports no FUSE support).

## Pruning

The daily timer only ever runs `borg create` — it never prunes. On an
append-only repo the unattended host cannot remove history (that is the point),
so pruning is a deliberate manual operation from a trusted workstation. The
shipped `/usr/local/sbin/borg-prune` wrapper runs `borg prune` + `borg compact`
with the configured retention, but against an append-only repo `compact`
reclaims nothing until append-only is lifted on the repo config:

```sh
REPO="ssh://user@host:port/./repo"
borg prune "$REPO" --dry-run --list \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --keep-yearly 2   # preview
borg config  "$REPO" append_only 0
borg prune   "$REPO" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --keep-yearly 2
borg compact "$REPO"
borg config  "$REPO" append_only 1
```

If interrupted between the two `borg config` calls, the repo is left
non-append-only — re-run `borg config "$REPO" append_only 1`.

## License

MIT
