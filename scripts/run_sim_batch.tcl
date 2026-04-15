# ==============================================================================
# Script: run_sim_batch.tcl
# Purpose: Headless Vivado simulation runner. Automatically detects the most 
#          recently modified testbench and forces Vivado to simulate it.
# ==============================================================================

# 1. Find and open the Vivado project in the root directory
set proj_file [lindex [glob -nocomplain *.xpr] 0]
open_project $proj_file

# 2. --- DYNAMIC TOP MODULE SCRIPT ---
# Find all Verilog/SystemVerilog testbenches in the sim folder
set tb_files [glob -nocomplain sim/*_tb.v sim/*_tb.sv]
set latest_time 0
set top_module ""

# Scan for the most recently modified file (the one Claude just wrote/updated)
foreach f $tb_files {
    set mtime [file mtime $f]
    if {$mtime > $latest_time} {
        set latest_time $mtime
        set top_module [file rootname [file tail $f]]
    }
}

# Force Vivado to set this newest file as the active simulation top
if {$top_module != ""} {
    set_property top $top_module [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
    update_compile_order -fileset sim_1
    puts "SUCCESS: Set simulation top module to $top_module"
} else {
    puts "WARNING: No testbench files found in the sim/ directory."
}
# -------------------------------------

# 3. Execute the simulation
puts "Launching Simulation..."
launch_simulation

# Note: No manual 'run Xns' command is needed here. 
# launch_simulation automatically runs until it hits the $finish block in your testbench.

# 4. Cleanup
puts "Simulation Complete."
close_sim
close_project