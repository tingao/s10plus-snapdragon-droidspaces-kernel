# A Droidspaces kernel for the Galaxy S10+ (SM-G9750, beyond2qlte)

A ready-to-flash kernel for the Snapdragon Galaxy S10+ that has what
[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) needs to run a Linux container, with
KernelSU root, and with Docker working inside that container.

A phone with a broken screen can still run a Debian server you reach over SSH. You do not have to
build anything: download the release, flash it with Odin, install one app.

## Which phone this is for

Samsung Galaxy S10+ 5G with the Snapdragon chip: model SM-G9750, codename `beyond2qlte`, the
China/Hong Kong variant, which its bootloader calls `BEYOND2Q CHNHK`. It also turns up written as
G9750, S10 Plus, or S10+ SD855.

Do not flash this on any other S10:

| Phone | Codename | Why not |
|---|---|---|
| Galaxy S10+ Exynos | `beyond2`, `beyond2lte` | Different SoC |
| Galaxy S10+ US Snapdragon (SM-G975U) | `beyond2q`, `beyond2qltesq` | Different board |
| Galaxy S10, S10e, S10 5G | `beyond0`, `beyond1`, `beyondx` | Different devices |

The device tree here is built for `beyond2qlte`, so a wrong-model flash either refuses to boot or
stops on the Samsung logo. Check the model number on the phone under Settings, About phone before
you start. It has to say SM-G9750.

## What you need

The phone, with Developer options enabled and OEM unlocking switched on.

Windows with [Odin](https://odindownload.com/) and the Samsung USB drivers. Version 3.14.1 is what
this was tested with.

Stock Android 12 on the phone. `G9750ZHU8HZE1` is the version this kernel was built and tested
against.

The [KernelSU-Next v3.1.0](https://github.com/KernelSU-Next/KernelSU-Next/releases) manager and
[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS/releases).

Install manager v3.1.0 rather than the newest release. This kernel reports KernelSU version 33129,
and the manager has to match that version and the UAPI. A newer manager reports the kernel as
unsupported, or complains that the UAPI does not match, which is the most common way to get stuck.

## Step 1: unlock the bootloader

Turn on OEM unlocking in Developer options. Power the phone off, then hold Volume Down and Bixby
while you plug in a USB cable to reach Download Mode, and confirm with a long press on Volume Up.

The phone wipes itself when it reboots. That is expected.

Two bootloader settings will stop you later, and both are on the Download Mode screen. Step 2 covers
them.

## Step 2: check the two bootloader gates

Re-enter Download Mode and read the small text in the top-left corner:

```
ODIN MODE (HIGH SPEED)
PRODUCT NAME: SM-G9750
CURRENT BINARY: Samsung Official
KG STATE : Checking
OEM LOCK : OFF
FRP LOCK : OFF
Secure Download : Enabled
```

`KG STATE` has to read `Checking`. If it reads `Prenormal`, the bootloader rejects anything you
flash and Odin stops with `FAIL! (Auth)` before writing a byte. To clear it, boot Android, open
Settings, then Software update, and run Download and install. It may say the software is already up
to date, which is fine. The check itself is what clears the state. Re-enter Download Mode and
confirm it reads `Checking`.

`OEM LOCK` has to read `OFF`. `ON (U)` is the one to watch for, because Odin reports `RES OK`, and
the phone then refuses to run the kernel and drops back to Download Mode. If you see it, open
Developer options and turn OEM unlocking off and on again. A factory reset can set it back, so check
it every time you flash.

[FLASHING.md](FLASHING.md) covers both gates in more detail, with the Odin log of a successful flash
and what each failure means.

## Step 3: flash

1. Download `AP-boot-beyond2qlte-droidspaces.tar.md5` from the Releases page, on the right-hand side
   of this repository.
2. Check the file before flashing. This catches the most common reason Odin refuses one:

   ```sh
   python3 build/verify-tarmd5.py AP-boot-beyond2qlte-droidspaces.tar.md5
   # ... VERDICT : ODIN WILL ACCEPT THIS

   sha256sum AP-boot-beyond2qlte-droidspaces.tar.md5
   # ... 51f04c2ba4f9e60f5b72dae7cedf8ee434c25cd68c02e315b4c5b90dc590bb78
   ```

   That digest is for the v1.0.0 asset, 67,123,270 bytes. The `.tar.md5` trailer covers the tar body
   only, so it cannot tell you the file itself arrived intact; the sha256 can.

3. In Odin, load it in the AP slot and leave BL, CP and CSC empty.
4. In the Options tab, tick Auto Reboot and F.Reset Time, and untick everything else. In particular,
   leave Nand Erase and Re-Partition alone.
5. Press Start and wait for `PASS!`. The phone reboots on its own.

## Step 4: root

Install the KernelSU-Next v3.1.0 manager and open it. It should report `Working`, `Kernel: 4.14.190`,
and `Hook mode: Manual`.

Then grant root where you need it. Open the manager, go to Superuser, and allow Shell and
Droidspaces. Root does not work until you tap allow. When you test it from a shell, use the full
path, because `which su` does not find it:

```sh
/system/bin/su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0
```

## Step 5: Droidspaces

Install the Droidspaces app, open it, and run Settings, then Requirements, then Check Requirements.
Everything under must have should pass, because this kernel has the options it asks for:

```
CONFIG_NAMESPACES  CONFIG_PID_NS  CONFIG_UTS_NS  CONFIG_IPC_NS  CONFIG_NET_NS
CONFIG_SECCOMP  CONFIG_SECCOMP_FILTER  CONFIG_DEVTMPFS  CONFIG_CGROUPS
CONFIG_CGROUP_DEVICE  CONFIG_VETH  CONFIG_BRIDGE  CONFIG_OVERLAY_FS
CONFIG_USER_NS  CONFIG_SYSVIPC  CONFIG_POSIX_MQUEUE  CONFIG_MEMCG
```

Create a container from one of the app's Debian or Ubuntu templates, give it a few GB, and start it.
Reach it with `droidspaces --name=<container> run <command>`, or turn on its SSH server.

## Docker inside the container

On most 4.14 Android kernels `docker run` fails inside a container. This kernel carries the fix, so
here is what goes wrong and what to set.

Android mounts cgroup v1 with the `noprefix` option, which names the cpuset files `cpus` and `mems`.
`runc` asks the kernel for `cpuset.cpus` and `cpuset.mems`, does not find them, and every `docker run`
dies with:

```
error setting cgroup config for procHooks process:
bpf_prog_query(BPF_CGROUP_DEVICE) failed: invalid argument
```

or, after forcing cgroup v1:

```
open /sys/fs/cgroup/cpuset/docker/cpuset.cpus: No such file or directory
```

This kernel includes the Droidspaces project's fix, `02.fix_restore cgroup file prefix handling.patch`,
which makes `cgroup_add_file()` publish the controller-prefixed name as a link as well. Both names
exist after flashing:

```
$ cat /sys/fs/cgroup/cpuset/cpuset.cpus
0-7
$ cat /sys/fs/cgroup/cpuset/cpus
0-7
```

Two settings are still needed inside the container, and both are container configuration rather than
kernel work:

* Force cgroup v1 for the container. On cgroup v2 the failure is the `bpf_prog_query` one, because
  that query needs a kernel newer than 4.14.
* Leave the runtime set to `runc`. `crun` gets past the cpuset problem and then fails creating a
  cgroup under Samsung's `schedtune` controller, which cannot be unmounted.

Then `docker run --rm alpine echo hello` works.

## Building it yourself

[SOURCE.md](SOURCE.md) and the `build/` directory have everything needed to reproduce the image: the
device tree, the exact config, the patches, and the toolchain.

## Credits

Most of this is other people's work. [CREDITS.md](CREDITS.md) names each project and what it
contributed, in particular the Droidspaces author, whose cgroup patch is the reason Docker works
here.
