#!/usr/bin/env bash

# Special thanks to:
# https://github.com/Leoyzen/KVM-Opencore
# https://github.com/thenickdude/KVM-Opencore/
# https://github.com/qemu/qemu/blob/master/docs/usb2.txt
#
# qemu-img create -f qcow2 mac_hdd_ng.img 128G
#
# echo 1 > /sys/module/kvm/parameters/ignore_msrs (this is required)

############################################################################
# NOTE: Tweak the "MY_OPTIONS" line in case you are having booting problems!
############################################################################

#!/bin/bash
# Helpful to read output when debugging
set -x

# Stop display manager
systemctl stop slim.service

# Unbind VTconsoles
for i in /sys/class/vtconsole/*/bind
do
	echo 0 >$i
done

# stop sound
echo 1 > /sys/module/snd_hda_intel/drivers/pci:snd_hda_intel/0000:00:1f.3/remove 

# Avoid a Race condition by waiting 2 seconds. This can be calibrated to be shorter or longer if required for your system
sleep 2

# Unload all Nvidia drivers
modprobe -r kvmgt
modprobe -r snd_hda_intel
modprobe -r i915

# Load VFIO Kernel Module  
devicestring="$(lspci -nn | grep "VGA compatible")"
pciid="$(echo "$devicestring" | grep -o "8086:....")"
pciaddr="$(echo "$devicestring" | cut -f 1 -d " ")"
modprobe vfio-pci ids=$pciid


MY_OPTIONS="+pcid,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"

# This script works for Big Sur, Catalina, Mojave, and High Sierra. Tested with
# macOS 10.15.6, macOS 10.14.6, and macOS 10.13.6

ALLOCATED_RAM="8000" # MiB
CPU_SOCKETS="1"
CPU_CORES="2"
CPU_THREADS="4"

REPO_PATH="./"
OVMF_DIR="."
i915_DIR="../i915-development/i915_simple/"

# Note: This script assumes that you are doing CPU + GPU passthrough. This
# script will need to be modified for your specific needs!
#
# We recommend doing the initial macOS installation without using passthrough
# stuff. In other words, don't use this script for the initial macOS
# installation.

# shellcheck disable=SC2054
args=(
  -chardev stdio,id=char0,logfile=/tmp/serial.log,signal=off
  -serial chardev:char0
  -enable-kvm -m "$ALLOCATED_RAM" -cpu host,vendor=GenuineIntel,kvm=on,vmware-cpuid-freq=on,+invtsc,+hypervisor
  -machine pc-q35-4.2
  -smp "$CPU_THREADS",cores="$CPU_CORES",sockets="$CPU_SOCKETS"
  -usb
  -vga none
  -device usb-ehci,id=ehci
  -device vfio-pci,host=0000:00:02.0,romfile="$i915_DIR/i915ovmf.rom"
  -device usb-kbd,bus=ehci.0
  -device usb-mouse,bus=ehci.0
  -device nec-usb-xhci,id=xhci
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
  -drive if=pflash,format=raw,readonly,file="$REPO_PATH/$OVMF_DIR/OVMF_CODE.fd"
  -drive if=pflash,format=raw,file="$REPO_PATH/$OVMF_DIR/OVMF_VARS-1024x768.fd"
  -smbios type=2
  -device ich9-ahci,id=sata
  -drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file="$REPO_PATH/OpenCore-Catalina/OpenCore.qcow2"
  -device ide-hd,bus=sata.2,drive=OpenCoreBoot
  -drive id=MacHDD,if=none,file=./osx.qcow2
  -device ide-hd,bus=sata.4,drive=MacHDD
  -netdev user,id=network0 -device vmxnet3,netdev=network0,mac=52:54:00:12:34:56
  -display none
  -fw_cfg name=etc/igd-opregion,file="$i915_DIR/opregion.bin"
  -fw_cfg name=etc/igd-bdsm-size,file="$i915_DIR/bdsmSize.bin"
  -object input-linux,id=mouse2,evdev=/dev/input/by-path/pci-0000:00:14.0-usb-0:4:1.1-event-mouse
 # -object input-linux,id=mouse2,evdev=/dev/input/by-path/pci-0000:00:1f.4-event-mouse
  -object input-linux,id=kbd1,evdev=/dev/input/by-path/platform-i8042-serio-0-event-kbd,grab_all=on,repeat=on
)

qemu-system-x86_64 "${args[@]}" || true

# Unload VFIO-PCI Kernel Driver
modprobe -r vfio-pci
modprobe -r vfio_iommu_type1
modprobe -r vfio
  
# Rebind VT consoles
echo 1 > /sys/class/vtconsole/vtcon0/bind
echo 1 > /sys/class/vtconsole/vtcon1/bind

modprobe i915 
modprobe snd_hda_intel

# Restart Display Manager
systemctl start slim.service
