#!/bin/bash
sudo apt -y install eatmydata
sudo eatmydata apt -y install git mmdebstrap depthcharge-tools build-essential bison flex libncurses-dev libssl-dev rsync rdfind
git clone --single-branch --depth=1 https://github.com/torvalds/linux.git
git clone --single-branch --depth=1 git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
