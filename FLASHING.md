# Flashing, step by step

Two bootloader gates stop most attempts, and both are visible on the Download Mode screen. Step 2
covers them. Both failures look like a bad file and are not.

## Before you touch anything

1. Download your phone's stock firmware for your exact model and CSC. For an SM-G9750 that means
   the files named `AP_...`, `BL_...`, `CP_...` and `CSC_...` from SamMobile or Frija. It is a 7 GB
   download and it is your way back, so get it now rather than after something goes wrong.
2. Back up anything on the phone you care about. Unlocking the bootloader wipes it.
3. On the computer, install the Samsung USB drivers and Odin. Odin 3.14.1 is what this was tested
   with.
4. On the phone, open Settings, then About phone, then Software information, and tap Build number
   seven times to enable Developer options.

## Step 1: unlock the bootloader

1. In Settings, open Developer options and turn on OEM unlocking. If the toggle is greyed out,
   connect to the internet and try again, because it often needs a network check first.
2. Power the phone off.
3. Hold Volume Down and Bixby, and while holding them, plug in the USB cable. A warning screen
   appears.
4. Long-press Volume Up to confirm. The phone wipes itself and reboots, which is expected.

Do step 2 before flashing anything. The bootloader refuses otherwise.

## Step 2: read the two gates on the Download Mode screen

This is also how you enter Download Mode to flash:

1. Power the phone off.
2. Hold Volume Down and Bixby and plug in the USB cable.
3. Press Volume Up once to accept.

You are now on a mostly black screen with small text in the top-left corner. It looks like this:

```
ODIN MODE (HIGH SPEED)
PRODUCT NAME: SM-G9750
CURRENT BINARY: Samsung Official
KG STATE : Checking
OEM LOCK : OFF
FRP LOCK : OFF
Secure Download : Enabled
```

### Gate 1: KG STATE

| What you see | What it means | What to do |
|---|---|---|
| `KG STATE : Checking` | Ready. Odin accepts the file | Go to step 3 |
| `KG STATE : Prenormal` | The bootloader rejects anything you flash | See below |

KG STATE is a Samsung anti-rollback guard. In Prenormal the flash does not start at all. Odin
reports `FAIL! (Auth)` and writes nothing, so the file is not at fault.

To clear it:

1. Leave Download Mode by holding Power and Volume Down for about ten seconds. The phone reboots.
2. Let Android boot and connect to the internet.
3. Open Settings, then Software update, and run Download and install. Let it finish. It may tell you
   the software is already up to date, which is fine. The check itself is what changes the state.
4. Power off, re-enter Download Mode, and confirm it reads `KG STATE : Checking`.

### Gate 2: OEM LOCK

| What you see | What it means | What to do |
|---|---|---|
| `OEM LOCK : OFF` | Ready | Go to step 3 |
| `OEM LOCK : ON (U)` | Odin reports `RES OK`, and the phone then refuses to boot the kernel and drops back to Download Mode. The `(U)` makes it look harmless and it is not | See below |

To clear it, boot Android, open Developer options, and turn OEM unlocking off and then on again.
Confirm the toggle is on and not greyed out, then check the Download Mode screen again. A factory
reset or a data wipe can set it back, so check it every time you flash.

Both gates have to read `Checking` and `OFF` before you continue.

## Step 3: flash

You should still be in Download Mode with Odin open.

1. In Odin, click AP and select:

   ```
   AP-boot-beyond2qlte-droidspaces.tar.md5
   ```

   Load it only in AP. Leave BL, CP and CSC empty.

2. In the Options tab, tick Auto Reboot and F.Reset Time and untick everything else, in particular
   Nand Erase and Re-Partition. Nand Erase destroys your data.

3. Odin checks the file and logs this:

   ```
   <ID:0/020> Added!!
   <OSM> Enter CS for MD5..
   <OSM> Check MD5.. Do not unplug the cable..
   <OSM> Please wait..
   <OSM> Checking MD5 finished Sucessfully..
   <OSM> Leave CS..
   ```

4. Click Start.

## Step 4: what success looks like

```
<ID:0/020> Odin engine v(ID:3.1401)..
<ID:0/020> File analysis..
<ID:0/020> SetupConnection..
<ID:0/020> Initialzation..
<ID:0/020> Get PIT for mapping..
<ID:0/020> Firmware update start..
<ID:0/020> NAND Write Start!!
<ID:0/020> SingleDownload.
<ID:0/020> boot.img
<ID:0/020> vbmeta.img
<ID:0/020> RQT_CLOSE !!
<ID:0/020> RES OK !!
<ID:0/020> Removed!!
<OSM> All threads completed. (succeed 1 / failed 0)
```

The phone reboots into Android on its own. Do not unplug the cable until it says `All threads
completed`.

One flash per Download Mode session. To flash again, power off and re-enter Download Mode.

## Step 5: check it worked

With USB debugging on and the phone booted:

```sh
adb shell uname -a
# Linux localhost 4.14.190-... #5 SMP PREEMPT ... aarch64

adb shell /system/bin/su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0

adb shell /system/bin/su -c "zcat /proc/config.gz | grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK)='"
# CONFIG_KSU=y
# CONFIG_KSU_MANUAL_HOOK=y
```

If `uname -a` still shows the old build date, the flash did not take, so check gate 2 again.

Then install the KernelSU-Next v3.1.0 manager and open it. It should report `Working` and
`Hook mode: Manual`. The README explains why that exact version.

## When it goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `FAIL! (Auth)` before anything is written | KG STATE is not `Checking` | Run the software update check, then retry |
| `RES OK`, then it boots back to Download Mode | OEM LOCK is `ON (U)` | Toggle OEM unlocking off and on, then retry |
| `MD5 hash value is invalid`, or the file is named as invalid | The file was renamed or downloaded incomplete. The name inside the `.tar.md5` has to match the file name | Download it again. Do not rename it |
| Odin never shows `Added!!` | Cable, port or driver | Try another cable and a rear USB port, and reinstall the Samsung drivers |
| The manager says `Unsupported` or `Not integrated` | Wrong KernelSU-Next manager version | Use v3.1.0. Uninstall the newer one first with `adb uninstall me.weishu.kernelsu` |
| `su` reports "inaccessible or not found" | Root has not been granted, or you used `which su` | Grant it in the manager's Superuser list, and always call `/system/bin/su` |
| It stops on the Samsung logo | Wrong kernel for the model | This is for the SM-G9750 only. Restore your stock firmware |

## Going back to stock

Power off, enter Download Mode, and load your own firmware into Odin: `BL` into BL, `AP` into AP,
`CP` into CP, and `CSC` into CSC. Use `CSC` rather than `HOME_CSC` if you want a clean wipe. Press
Start. This restores the phone completely, including the bootloader's opinion of your kernel.
