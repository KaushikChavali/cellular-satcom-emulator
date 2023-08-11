#!/bin/bash

# cellular-satcom-emulator : Multipath Cellular and Satellite Emulation Testbed
# Copyright (C) 2023 Kaushik Chavali
# 
# This file is part of the cellular-satcom-emulator.
#
# cellular-satcom-emulator is free software: you can redistribute it 
# and/or modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation, either version 3 of 
# the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# MoonGen LTE emulator configuration
# Source: moongen-lte-emulator/examples/lte-emulator-handover.lua

# Forward traffic between interfaces with moongen rate control
# device args:    dev1=eNodeB     dev2=UE Handset

# Devices to use, specify the same device twice to echo packets.
DEV_0=0
DEV_1=1

# Forwarding rates in Mbps (two values for two links)
RATE_DL=25
RATE_UL=43

# Fixed emulated latency (in ms) on the link.
LATENCY_DL=45
LATENCY_UL=42

# Variable bitrate file path (set it empty if fixed rate is employed)
VAR_RATE_DL="$HOME/lte-satcom-emulator/config/bitrate_dl.csv"
VAR_RATE_UL="$HOME/lte-satcom-emulator/config/bitrate_ul.csv"

# Variable emulated latency file path (set it empty if fixed latency is employed)
VAR_LATENCY_DL="\"\""
VAR_LATENCY_UL="$HOME/lte-satcom-emulator/config/latency_ul.csv"

# Maximum number of packets to hold in the delay line
QDEPTH_DL=1000
QDEPTH_UL=350

# After a concealed loss, this rate will apply to the backed-up frames.
CATCHUP_RATE_DL=1000
CATCHUP_RATE_UL=1000

# Rate of concealed packet drops
CONCEALED_LOSS_DL=0.005
CONCEALED_LOSS_UL=0.005

# Rate of packet drops
LOSS_DL=0.00006
LOSS_UL=0.00006

# The number of people/cell/minute, used for calculating the handover interruption time (HIT)
HO_PCM=2.5

# Handovers per second: mean and variance
HO_FREQ_MEAN=20.04
HO_FREQ_VARIANCE=23.74
