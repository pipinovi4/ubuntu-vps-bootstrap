# Ubuntu VPS Bootstrap

A reusable, idempotent Bash toolkit for preparing an Ubuntu VPS and deploying a generic Docker Compose application. Ubuntu Server 24.04 LTS is the primary target; 22.04 is supported where practical.

## Features

- Safe root/sudo bootstrap with dry-run and structured error reporting
- Docker Engine and Compose plugin from Docker's official apt repository
- Configurable non-root deployment user and `/opt/apps/<app>` directory
- UFW rules that allow SSH before activation, plus HTTP and HTTPS
- Conservative fail2ban, unattended security upgrades, optional swap, sysctl, and log rotation
- Opt-in SSH hardening gated on a valid deployment-user public key
- Locked, fast-forward-only Git and Docker Compose deployment with health checking
- Restricted configuration parser that never evaluates `.env` as shell code
- Conservative uninstall that preserves applications, users, keys, Docker data, and firewall rules

## Supported systems

Run bootstrap on Ubuntu Server 24.04 LTS (`amd64` or `arm64`). Ubuntu 22.04 LTS is also accepted. Other releases emit a warning; non-Ubuntu systems and unsupported architectures are rejected. The scripts expect systemd on a real VPS.

## Quick start

```bash
git clone https://github.com/pipinovi4/ubuntu-vps-bootstrap /opt/ubuntu-vps-bootstrap
cd /opt/ubuntu-vps-bootstrap
cp .env.example .env
editor .env
sudo ./bootstrap.sh --dry-run
sudo ./bootstrap.sh
sudo -iu deploy
cd /opt/ubuntu-vps-bootstrap
./deploy.sh
```

Never commit `.env`; it is ignored. The parser permits comments, blank lines, and known `KEY=value` entries. Values may be unquoted or wrapped in matching single/double quotes. Shell substitutions and unknown keys are rejected; interpolation is not supported.

## Safe first run

Keep the current SSH session open throughout bootstrap. Review `.env`, confirm `SSH_PORT` matches the listening port, and run `sudo ./bootstrap.sh --dry-run` first. After bootstrap, open and verify a second SSH connection before closing the original session.

Do not enable SSH hardening on the first run unless the deployment user already has a tested public key. Before `--harden-ssh`, open a second SSH connection as that user. The script refuses password disabling unless `authorized_keys`, ownership, permissions, and `sshd -t` are safe.

## Configuration

| Key | Default | Meaning |
| --- | --- | --- |
| `APP_NAME` | `my-app` | Safe application directory name |
| `DEPLOY_USER` | `deploy` | Non-root deployment account |
| `APP_ROOT` | `/opt/apps` | Absolute application root |
| `SSH_PORT` | `22` | Existing SSH TCP port; bootstrap does not change it unless hardening is requested |
| `ENABLE_SYSTEM_UPGRADE` | `false` | Run `apt-get upgrade` |
| `ENABLE_SWAP` | `true` | Create `/swapfile` only when no swap is active |
| `SWAP_SIZE_GB` | `2` | Positive integer swap size |
| `ENABLE_UFW` | `true` | Configure and enable UFW |
| `ENABLE_FAIL2BAN` | `true` | Install conservative SSH jail |
| `ENABLE_UNATTENDED_UPGRADES` | `true` | Enable automatic security upgrades |
| `ENABLE_SSH_HARDENING` | `false` | Request guarded SSH hardening |
| `GIT_REPOSITORY` | empty | Application Git clone URL/path |
| `GIT_BRANCH` | `main` | Deployment branch |
| `HEALTHCHECK_URL` | `http://127.0.0.1/health` | Successful HTTP endpoint; empty skips |
| `HEALTHCHECK_ATTEMPTS` | `30` | Number of attempts |
| `HEALTHCHECK_INTERVAL_SECONDS` | `2` | Delay between attempts |

Booleans must be exactly `true` or `false`. Usernames, names, ports, paths, and integers are strictly validated.

## Bootstrap

```bash
sudo ./bootstrap.sh --help
sudo ./bootstrap.sh --dry-run --verbose
sudo ./bootstrap.sh --config /secure/path/server.env
sudo ./bootstrap.sh --skip-upgrade
sudo ./bootstrap.sh --harden-ssh
```

Reruns avoid duplicate managed configuration and reuse existing users, swap, directories, repository keys, and identical files. Changed managed files receive timestamped backups.

## Deploy

Deploy as `DEPLOY_USER`, never root:

```bash
./deploy.sh --dry-run
./deploy.sh
./deploy.sh --no-build
./deploy.sh --config /secure/path/deploy.env --verbose
```

The deploy lock prevents concurrent runs. Existing repositories use fetch, branch checkout, and `pull --ff-only`; new repositories are cloned only into an empty directory. The application `.env` is never created or overwritten. Compose is validated before pull/build/up. After a passing health check, `deploy-metadata.json` records the commit, branch, and UTC time. Failed health checks print the last 100 Compose log lines and return non-zero.

Rollback is not implemented. Restore a known-good Git commit or image tag explicitly, validate Compose, and redeploy. Automated rollback is a roadmap item only after it can be tested end to end.

## Security model and limitations

The toolkit reduces common setup mistakes but does not replace monitoring, backups, vulnerability management, secret storage, or application-specific security. Docker group membership is root-equivalent. UFW and Docker-published ports require careful review because Docker networking can bypass some UFW policy expectations. No password, token, private key, or production environment file belongs in Git.

Bootstrap does not change the SSH port, disable root SSH, or disable passwords by default. SSH hardening uses a drop-in and only proceeds after key checks. It does not terminate the current SSH session.

## Verification on the VPS

```bash
# First, open a second terminal and verify SSH:
ssh -p 22 deploy@server

sudo ufw status verbose
docker --version
docker compose version
sudo fail2ban-client status sshd
systemctl status unattended-upgrades --no-pager
swapon --show
systemctl is-active docker fail2ban
```

Keep the original connection open until all checks and the second SSH login succeed.

## Recovery

The error trap prints the failing command, line, and status. Correct the reported issue and rerun; operations are designed to be idempotent. Managed configuration backups use `.bak.<UTC timestamp>` beside the original. If an SSH reload fails, keep the active session open, inspect `sshd -t`, remove or restore the managed drop-in, validate again, and reload SSH. Never reboot merely to test uncertain SSH changes.

`sudo ./uninstall.sh` prints its exact scope and requires a typed phrase. `--dry-run` previews it; `--yes` is intended for deliberate automation. It removes only four toolkit-named configuration files. It deliberately preserves users, homes, SSH keys, repositories, application data, Docker, containers, images, volumes, packages, UFW rules, and swap.

## Testing

Install the development tools on Ubuntu or WSL:

```bash
make setup-dev
```

Then run the local checks:

```bash
make format
make lint
make test
make check
```

The container smoke test additionally requires a working Docker daemon:

```bash
docker version
make integration-test
```

With Docker Desktop on Windows, enable **Settings -> Resources -> WSL integration** for the current Ubuntu distribution.

Unit tests cover validators, restricted parsing, dry-run construction, idempotent installation, guarded SSH hardening, deployment locking, and required defaults. The Ubuntu container smoke test covers script loading/help and configuration validation.

Containers do **not** prove systemd service activation, UFW behavior, SSH reload safety, fail2ban integration, swap creation, or Docker-in-Docker. Those require a disposable real Ubuntu VPS followed by the verification checklist above.

## Troubleshooting

- **Docker permission denied:** sign out and back in after bootstrap so new group membership applies.
- **Deploy refuses root:** switch with `sudo -iu <DEPLOY_USER>`.
- **Repository is non-empty:** move the application elsewhere or initialize it correctly; deploy refuses destructive cleanup.
- **Health check fails:** inspect the printed logs and test the URL locally with `curl -v`.
- **UFW concern:** keep the session open, confirm the active and configured SSH ports are allowed, then test a second login.
- **SSH hardening skipped:** repair the deployment user's `~/.ssh` ownership, directory mode (`700`), and `authorized_keys` mode (`600`), then retry from a verified second session.

## Roadmap

- Tested rollback based on immutable release metadata
- Application-specific backup hooks
- Ansible role and Terraform modules for larger fleets

## License

MIT © 2026 Mykyta Bozhenko.
