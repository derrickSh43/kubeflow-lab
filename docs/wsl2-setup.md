# Windows + WSL2 setup

Most of the pain in this lab on Windows comes from two things that fail
*silently*. Do both before your first `make up`.

## 1. Give WSL2 enough memory

WSL2 allocates a default share of RAM, not all of it, and Docker can only
use what WSL2 has. `docker info` will happily report a number far below
your physical RAM and nothing will warn you.

```powershell
# in PowerShell
notepad $env:USERPROFILE\.wslconfig
```

Paste the contents of [`examples/wslconfig.sample`](../examples/wslconfig.sample)
and adjust `memory=` for your machine. Then:

```powershell
wsl --shutdown
```

Restart Docker Desktop. Confirm it took:

```bash
docker info --format '{{.MemTotal}}' | awk '{print $1/1024/1024/1024 " GB"}'
```

`make doctor` checks this for you and will refuse to start a tier your
machine cannot hold.

## 2. Raise the inotify limits

Kubeflow runs a lot of controllers, and every controller watches files.
WSL2's defaults are low enough to break them - and the failure mode is
awful: the cluster comes up fine, then controllers start restart-looping
twenty minutes later with errors that do not mention inotify at all.

In your WSL distro:

```bash
sudo tee /etc/sysctl.d/99-kubeflow.conf >/dev/null <<'CONF'
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches   = 524288
CONF

sudo sysctl --system
```

This survives reboots. Verify:

```bash
cat /proc/sys/fs/inotify/max_user_instances   # want >= 512
cat /proc/sys/fs/inotify/max_user_watches     # want >= 524288
```

## 3. Keep the repo on the Linux filesystem

Working out of `/mnt/c/...` or `/mnt/d/...` goes through the 9p filesystem
bridge and is dramatically slower - enough to make `kustomize build` take
minutes. Clone into your WSL home instead:

```bash
cd ~
git clone <your-remote> kubeflow-lab
cd kubeflow-lab
```

If you keep the canonical copy on `D:`, clone *from* it into WSL and push
back; do not build from the mount.

## 4. Docker Desktop settings

- **Use the WSL2 based engine** - on, not Hyper-V.
- **Resource Saver** - turn it off. It pauses the engine when idle, which
  looks exactly like a dead cluster.
- Enable integration for the distro you actually work in.

## Known-good on this machine class

24GB RAM / 8GB VRAM laptop:

| Tier | Verdict |
|------|---------|
| 0 | comfortable, boots in minutes |
| 1 | comfortable with `memory=16GB` - this is the sweet spot |
| 2 | tight. Budget 18-20GB to WSL, expect swapping, close everything else |

The GPU is not used by any tier here. KServe and Katib will happily run
CPU-only, and wiring the WSL2 CUDA passthrough into kind is a rabbit hole
that teaches you about device plugins and very little about Kubeflow.
