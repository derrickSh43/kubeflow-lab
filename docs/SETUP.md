# Setup — start to finish

Follow this top to bottom the first time. It assumes nothing and it tells
you what each command should print, so you can tell "working" from "broken"
without guessing.

Windows is covered in full detail because that is where the traps are.
macOS and Linux are at the bottom and are much shorter.

**Total time:** 30–60 minutes, most of it waiting on image pulls.

---

## What you are actually building

Nothing here gets installed on Windows. It is containers the whole way
down:

```
Windows
└─ WSL2 virtual machine
   ├─ Ubuntu distro  ........... your shell, and the git clone. That's all.
   └─ docker-desktop distro
      └─ Docker Engine
         ├─ toolbox container  .... kubectl, kustomize, kind, helm, k9s, kfp
         └─ kind node containers  ← these ARE the Kubernetes cluster
            └─ pods (Kubeflow)  ... containers inside those containers
```

`kind` means "Kubernetes IN Docker". Each cluster node is a Docker
container running a kubelet, so `docker ps` will show them sitting next to
each other. `make down` deletes all of it and leaves your machine as it
was.

The only things this adds to your system: `make` (414KB via apt), the repo
(~250KB), and one `.wslconfig` text file. Everything else lives inside
Docker and is thrown away with `make nuke`.

---

# Windows

## Step 1 — Check your prerequisites

Open **PowerShell** and run:

```powershell
docker --version
wsl -l -v
```

You want to see a Docker version, and a distro list containing **Ubuntu**
(or Debian, or similar). Example:

```
  NAME              STATE           VERSION
* docker-desktop    Running         2
  Ubuntu            Running         2
```

### If `docker --version` fails

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
During install, keep **"Use WSL 2 instead of Hyper-V"** checked.

### If only `docker-desktop` is listed, with no Ubuntu

`docker-desktop` is Docker's own internal distro. It is not a place to
work. Install a real one from an **administrator** PowerShell:

```powershell
wsl --install -d Ubuntu
```

Reboot. On first launch Ubuntu asks you to create a username and password
— **write the password down**, you will need it for `sudo`.

## Step 2 — Turn on Docker's WSL integration

This is what lets the `docker` command work from inside Ubuntu. Without
it, everything later fails with "cannot connect to the Docker daemon".

1. Open **Docker Desktop**
2. **Settings** → **Resources** → **WSL Integration**
3. Toggle **Ubuntu** on
4. **Apply & Restart**

While you are in Settings, also turn **off** *Resource Saver* (under
Settings → Resources → Advanced). It pauses the engine when idle, which
looks exactly like a dead cluster and will waste an hour of your life.

## Step 3 — Configure WSL2: memory and cgroup v2

**Do this before you create a cluster.** It requires `wsl --shutdown`,
which would destroy a running cluster. Doing it now costs nothing.

Two separate problems, one file, one restart.

**Memory.** WSL2 does not hand Docker your physical RAM — it takes a
default share, usually about half, and nothing warns you. On a 24GB
machine that leaves Docker around 11GB: fine for tier 0, not enough for
tier 1.

**cgroup v2.** Kubernetes 1.36 will not run on cgroup v1, and WSL2 before
v2.5.1 defaults to v1. This one does not fail quietly — `make up` dies at
`Starting control-plane` after emitting several hundred lines of kubeadm
retries ending in `context deadline exceeded`. The actual cause is a
single deprecation warning at the very top, scrolled away long before you
read the error.

First, check your WSL version:

```powershell
wsl --version
```

If it is older than 2.5.1, update — that alone may be enough:

```powershell
wsl --update
```

Then, in **PowerShell**, replacing `<you>` with your **Windows** username
(not your Linux one — they are usually different):

```powershell
notepad C:\Users\<you>\.wslconfig
```

Notepad will offer to create the file. Paste this, adjusting `memory` for
your machine:

```ini
[wsl2]
memory=16GB
swap=8GB
kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1
autoMemoryReclaim=gradual
sparseVhd=true
```

The `kernelCommandLine` line is harmless on WSL ≥ 2.5.1, which is already
on v2. Leave it in either way.

Sizing guide — leave Windows at least 6–8GB:

| Physical RAM | `memory=` | Tiers you can run |
|---|---|---|
| 16GB | `10GB` | tier 0 |
| 24GB | `16GB` | tier 0, tier 1 |
| 32GB+ | `24GB` | all three |

Deliberately **omit `processors=`** unless you want to limit CPU. Left
out, WSL gets all your cores. Setting it to a small number is a downgrade
you will forget you made.

Save, close Notepad, then:

```powershell
wsl --shutdown
```

Wait about ten seconds. Docker Desktop will restart itself.

**Verify both took**, from inside WSL:

```bash
docker info --format 'cgroup v{{.CgroupVersion}}  mem {{.MemTotal}}'
```

You want `cgroup v2` and a memory figure matching what you set. If cgroup
is still `v1`, quit Docker Desktop fully from the system tray and reopen
it — a restart that does not fully stop the engine will not pick up the
new kernel command line.

## Step 4 — Get into the right shell

**This is the step people get wrong.** You need a WSL shell, not Git Bash
and not PowerShell.

```powershell
wsl -d Ubuntu
```

The `-d Ubuntu` is not optional. Docker Desktop usually sets
`docker-desktop` as WSL's default distro, so a bare `wsl` drops you into
the wrong one.

**Check your prompt.** You are in the right place if it looks like this:

```
user@Derrick:/mnt/c/Users/you$
```

You are in the **wrong** place if it looks like either of these:

```
derri@Derrick MINGW64 ~          ← Git Bash. Wrong.
PS C:\Users\you>                 ← PowerShell. Wrong.
```

The giveaway is `MINGW64`. Git Bash looks Linux-ish but is not WSL: it has
no `make`, no Docker integration, and it spells your D: drive `/d` instead
of `/mnt/d`. Every path in this guide assumes WSL.

To make `wsl` land on Ubuntu from now on, run this once from PowerShell:

```powershell
wsl --set-default Ubuntu
```

## Step 5 — Install `make` and set your git identity

Everything from here runs inside Ubuntu.

```bash
sudo apt update && sudo apt install -y make
```

It will ask for the Ubuntu password you set in step 1.

Git needs to know who you are before it will let you commit:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## Step 6 — Get the repo

Clone it into your **Linux home**, not onto `/mnt/c` or `/mnt/d`:

```bash
cd ~
git clone <your-remote> kubeflow-lab
cd kubeflow-lab
```

If you were handed a `.bundle` file instead of a git remote:

```bash
cd ~
git clone /mnt/d/path/to/kubeflow-lab.bundle kubeflow-lab
cd kubeflow-lab
```

> **Why the Linux home and not the Windows drive?** Files under `/mnt/c`
> and `/mnt/d` are reached through a filesystem bridge that is
> dramatically slower — slow enough that `kustomize build` goes from
> seconds to minutes. Keep the working copy in `~`. If you want a copy on
> `D:` as a backup, push to it or keep a bundle there; do not build from
> it.

## Step 7 — Run the preflight

```bash
make doctor
```

This checks everything that has historically bitten someone. Healthy
output looks like:

```
kubeflow-lab doctor   tier 0 - Pipelines standalone

==> Docker
  ✔ daemon reachable - 27.4.0
  ✔ Docker memory: 16GB (tier 0 wants ~6GB)
  ✔ Docker CPUs: 16
  ✔ Docker storage free: 954GB

==> Platform
  ✔ running under WSL2
  ✔ .wslconfig found at /mnt/c/Users/you/.wslconfig
  ✔ fs.inotify.max_user_instances = 8192
  ✔ fs.inotify.max_user_watches = 1048576

...

Ready for tier 0 - Pipelines standalone. 1 advisory note(s).
```

**Green ✔ is fine. Yellow `!` is advisory — read it, then carry on. Red ✘
blocks the install and must be fixed.**

Common red lines and their fixes:

| Line | Fix |
|---|---|
| `docker CLI found but the daemon is not reachable` | Docker Desktop is not running, or step 2 was skipped |
| `cgroup v1 - kind WILL fail at 'Starting control-plane'` | Step 3's `kernelCommandLine` line, then `wsl --shutdown` |
| `Docker can use 11GB; tier 1 needs ~14GB` | Step 3, then `wsl --shutdown` |
| `fs.inotify.max_user_instances is 128` | See [wsl2-setup.md](wsl2-setup.md) §2 |
| `Docker storage has 12GB free` | `docker system prune -a`, or free disk |

Checking `make doctor` before every `make up` is a habit worth forming. It
takes two seconds and saves the twenty-minute version of the same
discovery.

## Step 8 — Boot it

Start at tier 0. It is the smallest, fastest, and least likely to
disappoint you on the first try.

```bash
make up TIER=0
```

What to expect, roughly:

| Phase | Time | What you see |
|---|---|---|
| Building the toolbox image | 3–5 min | `docker build` output |
| Creating the kind cluster | ~1 min | `Creating cluster "kubeflow-lab"` |
| Waiting for the control plane | 1–2 min | retry dots, then a node table |
| Installing Pipelines | 5–10 min | apply output, some retries |

**Retry lines are normal.** You will see things like:

```
  ! attempt 1/10 failed, retrying in 20s ...
```

This is not a bug and not a workaround. The manifests contain both custom
resource definitions and objects of those types in a single apply, so the
first attempts genuinely cannot succeed until the API server has
registered the CRDs. Upstream's own documented install is a retry loop.
The script gives up after 25 attempts; anything short of that is fine.

When it finishes you get:

```
==> Done

  Pipelines UI   http://localhost:8080
  No login on this tier.
```

## Step 9 — Check it works

Open <http://localhost:8080>. You should get the Kubeflow Pipelines UI
with no login prompt — tier 0 has no authentication at all, by design.

Then confirm the cluster from the shell:

```bash
make status
```

Healthy output ends with:

```
==> Pods that are NOT Running/Completed
  ✔ everything is Running or Completed
```

If some pods are still starting, give it another five minutes. `make up`
returning means the manifests converged, not that every container has
finished pulling.

**You are done.** Go to [`labs/README.md`](../labs/README.md) and start at
lab 01.

---

# macOS and Linux

Much shorter, because there is no WSL layer.

```bash
# Prerequisite: a running Docker engine.
#   macOS   - Docker Desktop, OrbStack, or colima
#   Linux   - docker-ce, and your user in the docker group

git clone <your-remote> kubeflow-lab
cd kubeflow-lab
make doctor
make up TIER=0
```

Notes:

- **macOS:** Docker Desktop's memory limit is in Settings → Resources. The
  default is usually too low for tier 1; raise it to 14GB or more.
- **Apple Silicon:** tier 0 is reliable. Some components in tiers 1 and 2
  have had gaps in `arm64` images historically — if a pod sits in
  `ImagePullBackOff` or crashes with `exec format error`, that is why.
- **Linux:** raise the inotify limits if `make doctor` flags them:
  ```bash
  sudo tee /etc/sysctl.d/99-kubeflow.conf >/dev/null <<'CONF'
  fs.inotify.max_user_instances = 512
  fs.inotify.max_user_watches   = 524288
  CONF
  sudo sysctl --system
  ```

---

# Day-to-day

```bash
make doctor          # preflight — run before make up
make up TIER=0       # boot the cluster and install
make status          # what is running, and what is stuck
make sh              # shell into the toolbox: kubectl, kustomize, k9s, kfp
make forward         # port-forward the UI if the NodePort path is broken
make creds           # print the login (tier 1+)
make labs            # list the labs
make down            # delete the cluster, keep the image cache
make nuke            # delete the cluster AND the images
make freeze          # pin tool versions into VERSIONS.lock before sharing
```

`make up` is **idempotent**. Re-running it after a failure is the normal
recovery path, not a last resort.

Two rules worth internalising:

- **`make` runs in your host shell, never inside the toolbox.** The toolbox
  is where `kubectl`, `kustomize` and `kfp` live; the Makefile is what
  drives the toolbox. Run `make` in there and it spawns a nested container
  whose volume paths are resolved on the host, `/state` mounts empty, and
  kubectl fails over to `localhost:8080` — which looks exactly like a dead
  cluster and isn't. `make sh` puts you in; `exit` gets you out.
- **`docker ps` is your ground truth.** The cluster nodes are containers.
  If something is confusing, look at them.

### Stopping for the day, and coming back

You have two ways to stop, and they are not the same.

```bash
make pause     # stop the containers, keep everything
make resume    # back in under a minute, exactly as you left it
```

```bash
make down      # delete the cluster
make up TIER=0 # 3-5 minutes, fresh cluster
```

What survives each:

| | `make pause` | `make down` | `make nuke` |
|---|---|---|---|
| Your `ANSWERS.md`, repo edits | yes | yes | yes |
| Docker image cache (~25GB) | yes | yes | **no** |
| Toolbox image | yes | yes | **no** |
| Pipeline runs, Workflows, MySQL, artifacts | **yes** | no | no |
| Time to get back | <1 min | 3–5 min | 15 min |

**Use `make pause` between sessions.** It frees the memory back to Windows
and keeps your cluster state, which matters more than it sounds: several
labs build on work you did earlier in the same cluster. Lab 02's caching
question is the clearest case — the KFP cache lives in MySQL inside the
cluster, so a `make down` between submitting a pipeline and re-running it
erases the very thing the question asks about.

Use `make down` when you want a clean slate, when a resume comes back
unhealthy, or when you are moving between tiers.

A resume can fail if the cluster sat for several days — certificates and
leases have timing assumptions a long pause breaks. `make resume` tells you
if that happened. It is not worth debugging in a lab; `make down && make up`
and carry on. Your notes are files on disk and are never at risk.

### Starting a new lab later

Labs are independent unless a lab says otherwise. You can finish lab 01,
`make pause`, come back a week later, `make resume`, and go straight into
lab 02. Nothing carries between them except what you learned.

### Moving up a tier

```bash
make down
make doctor TIER=1    # confirm you have the memory
make up TIER=1
```

Tier 1 takes 20–30 minutes on a cold cache and adds a login screen —
`user@example.com` / `12341234`. That credential is upstream's public lab
default; lab 06 is about replacing it.

### Using Lens or k9s from Windows

`make up` writes a second kubeconfig pointing at `127.0.0.1` for tools
running outside the toolbox:

```bash
export KUBECONFIG=~/kubeflow-lab/.state/kubeconfig.host
```

For Lens on the Windows side, point it at the same file through the WSL
share: `\\wsl$\Ubuntu\home\<you>\kubeflow-lab\.state\kubeconfig.host`

---

# When it goes wrong

[`troubleshooting.md`](troubleshooting.md) has the full list. The four
that account for most of it:

**`make up` dies at "Starting control-plane" with a wall of kubeadm
retries and `context deadline exceeded`** — cgroup v1. Step 3. The
hundreds of lines are a red herring; the real message is the deprecation
warning on the first line.

**"make: command not found"** — step 5, or you are in Git Bash. Check your
prompt for `MINGW64`.

**"/mnt/d does not exist" or a path like `C:/Program Files/Git/mnt/d/...`**
— you are in Git Bash. Step 4.

**Pods stuck `Pending`, events mention insufficient memory** — step 3, then
`wsl --shutdown`.

**Everything is slow and the laptop is unusable** — expected at tier 1+.
Raise `memory=`, run `make down` between sessions, or work at tier 0.

### Starting completely over

```bash
make nuke
make up TIER=0
```

Nothing in `.state/` is precious — it is all regenerated.

### Removing every trace

```bash
make nuke
docker system prune -a      # reclaim the image cache
rm -rf ~/kubeflow-lab
```

Then delete `C:\Users\<you>\.wslconfig` if you want WSL back on defaults.
