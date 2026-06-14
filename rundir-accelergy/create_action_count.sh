#!/bin/bash

python3 create_action_count.py --saved_folder /tmp/mxr_16x16pe_4mac_ws_scsim --run_name mxr_16x16pe_4mac_ws --arch_name systolic_array --SRAM_row_size 2 --DRAM_row_size 2 --config /home/xinting/Desktop/scale-sim-v3-mx/configs/scale_accel.cfg

cp /tmp/mxr_16x16pe_4mac_ws_scsim/mxr_16x16pe_4mac_ws/action_count.yaml ./accelergy_input/action_count.yaml

mv /tmp/mxr_16x16pe_4mac_ws_scsim/mxr_16x16pe_4mac_ws  /tmp/mxr_16x16pe_4mac_ws_out/scale_sim_output_mxr_16x16pe_4mac_ws

