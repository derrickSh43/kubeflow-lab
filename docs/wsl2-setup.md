# Windows + WSL2 setup

Most of the pain in this lab on Windows comes from a handful of things
that fail *silently*, or fail loudly for the wrong reason. Work through
these before your first `make up`.

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

## 2. Enable cgroup v2

**Kubernetes 1.36 does not run on cgroup v1**, and WSL2 before v2.5.1
defaults to v1.

The failure is spectacular and completely misleading. `kind create
cluster` generates every certificate, writes all the static pod
manifests, starts the kubelet — and then the API server never comes up.
kubeadm retries for sixty seconds and dies with:

```
error execution phase wait-control-plane: cannot obtain client without
bootstrap: ... client rate limiter Wait returned an error: context
deadline exceeded
```

Several hundred lines of output, and the only real clue is a single line
printed at the very top, long since scrolled off your screen:

```
cgroup v1 is deprecated in Kubernetes and will not be supported in a
future kind release, please upgrade to cgroup v2
```

### Check what you have

```powershell
wsl --version
```

**2.5.1 or newer** — cgroup v2 is already the default and you can skip to
step 3. **Older, or the command fails** — update first, which may fix it
outright:

```powershell
wsl --update
```

### Set it explicitly

Whether or not the update helped, put this in `.wslconfig` (same file as
step 1). It is harmless on versions that are already v2:

```ini
[wsl2]
kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1
```

Then from PowerShell:

```powershell
wsl --shutdown
```

Wait ten seconds and let Docker Desktop restart.

### Verify

```bash
docker info --format '{{.CgroupVersion}}'
```

You want `2`. If it still says `1`, Docker Desktop did not pick up the
restart — quit it fully from the system tray and reopen it.

`make doctor` now checks this and refuses to continue on v1, so you
should never meet that wall of kubeadm output again.

## 3. Raise the inotify limits

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

## 4. Make WSL give memory back

WSL2 claims memory as it needs it and does **not** return it to Windows on
its own unless you tell it to. Stopping containers, or even `make down`,
frees memory *inside* the VM — Windows still sees `vmmemWSL` holding the
high-water mark.

Two things get this wrong by default.

### The setting is in a different section

`autoMemoryReclaim` and `sparseVhd` live under **`[experimental]`**, not
`[wsl2]`. Put them under `[wsl2]` and they are silently ignored, which
looks exactly like "nothing I do frees memory".

```ini
[wsl2]
memory=10GB
swap=8GB
kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1

[experimental]
autoMemoryReclaim=dropCache
sparseVhd=true
```

### `gradual` is not the one you want

The accepted values are `disabled`, `gradual` and `dropCache`. `gradual`
reclaims "slowly and automatically" — slowly enough that you will conclude
it is broken — and it has a known interaction with Docker Desktop's
Resource Saver that can wedge WSL entirely
([microsoft/WSL#11066](https://github.com/microsoft/WSL/issues/11066)).

Use `dropCache`, which reclaims immediately and is WSL's own default.

Apply it the usual way, from PowerShell:

```powershell
wsl --shutdown
```

### Getting memory back right now

After `make pause`, drop the page cache — instant and safe:

```bash
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
```

For all of it, from **PowerShell**, not from inside WSL:

```powershell
wsl --shutdown
```

Stopped containers survive a shutdown — they live in Docker's virtual disk.
Start Docker Desktop again later and `make resume` picks up where you left
off. This is the real "stopping for the day" sequence on Windows:

```
make pause          # in WSL
wsl --shutdown      # in PowerShell
```

### Size for the tier you actually run

WSL grows into whatever you allow it. If you are only doing tier 0, do not
give it 16GB — `memory=10GB` is plenty, and you can raise it when you move
to tier 1.

## 5. Keep the repo on the Linux filesystem

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

## 6. Docker Desktop settings

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
