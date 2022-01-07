#!/bin/bash
# MoonGen LTE emulator configuration
# Source: moongen-lte-emulator/examples/lte-emulator-handover.lua

# Forward traffic between interfaces with moongen rate control
# device args:    dev1=eNodeB     dev2=UE Handset

# Devices to use, specify the same device twice to echo packets.
DEV_0="0"
DEV_1="1"

# Forwarding rates in Mbps (two values for two links)
RATE_DL="38"
RATE_UL="40"

# Fixed emulated latency (in ms) on the link.
LATENCY_DL="10"
LATENCY_UL="30"

# Maximum number of packets to hold in the delay line
QDEPTH_DL="1000"
QDEPTH_UL="350"

# After a concealed loss, this rate will apply to the backed-up frames.
CATCHUP_RATE_DL="1000"
CATCHUP_RATE_UL="1000"

# Rate of concealed packet drops
CONCEALED_LOSS_DL="0.005"
CONCEALED_LOSS_UL="0.005"

# Rate of packet drops
LOSS_DL="0.001"
LOSS_UL="0.001"

# The number of people/cell/minute, used for calculating the handover interruption time (HIT)
HO_PCM="2.5"

# Handovers per second: mean and variance
HO_FREQ_MEAN="0"
HO_FREQ_VARIANCE="0"
