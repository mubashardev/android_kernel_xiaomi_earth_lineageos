#!/bin/bash
sed -i.bak '/#ifdef CONFIG_KSU_SUSFS/,/^#endif.*CONFIG_KSU_SUSFS/d' KernelSU-Next/kernel/supercalls.c
