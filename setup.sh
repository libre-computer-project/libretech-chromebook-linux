#!/bin/bash
sudo apt install mmdebstrap depthcharge-tools build-essentials bison flex libncurses-dev rsync rdfind
git clone --single-branch --depth=1 https://github.com/torvalds/linux.git
git clone --single-branch --depth=1 git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
