# Hyptia-OpenSAND utility

The enclosed utility enables a realistic low Earth orbit (LEO) network delay emulation on the [OpenSAND](https://github.com/curtp67/quic-opensand-emulation) SATCOM emulation platform.

It does this by processing the round-trip time (RTT) values of a flow generated during the [Hypatia](https://github.com/snkas/hypatia/) LEO simulations and converting them to a format compatible with OpenSAND.

# Format

### Sample input from Hypatia

```
# flow_id, time_ns, rtt_ns
0,14692581,14000000
0,32676599,14500000
0,35014174,15312500
0,36212250,16148437
0,38506653,17129882
```

### Sample output for OpenSAND

```
# time_s delay_ms
0 24
1 27
2 28
3 29
4 30
```

# Considerations

1. Hypatia generates `RTT` values during a simulation. OpenSAND accepts `one-way delay` values.
2. In OpenSAND, the one-way delay values are set on both the satellite gateway (GW) and the satellite terminal (ST). The delay values are `halved`, considering symmetric delays at both ends.
3. Hypatia generates timing and RTT values in nanoseconds (ns). OpenSAND accepts time in seconds (s) and delays in milliseconds (ms).
4. OpenSAND emulates delays in a one-second interval. The utility reads all the delay values generated by Hypatia in one second and computes a `median` of those values.
5. OpenSAND accepts time and delays values as integers. The utility `truncates` the integral part of the floating-point number.

# Usage

1. Place the RTT files generated by Hypatia in the `input` directory.
2. Execute the following command to run the utility.
```
python3 process_rtt.py
``` 
3. The processed delay file is placed in the `output` directory.
4. Rename the processed file as `satdelay.csv` for use with OpenSAND.
5. Place one copy of the file, each in the folder `config/st/plugins/` and `config/gw/plugins/` respectively.
6. OpenSAND reads the delay values from the file and emulates the configured delay at specified time intervals.