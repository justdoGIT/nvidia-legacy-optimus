#!/bin/bash
# Force PCIe link re-train before nvidia modprobe
echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
echo OFF > /proc/acpi/bbswitch
sleep 1
echo ON  > /proc/acpi/bbswitch
sleep 1
echo 1 > /sys/bus/pci/rescan
sleep 1
