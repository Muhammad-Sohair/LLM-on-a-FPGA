# scripts/auto_add_sources.tcl

# Automatically find and open the project file in the root directory
set proj_file [lindex [glob -nocomplain *.xpr] 0]
open_project $proj_file

# Add Design Sources (Assuming Claude saves them in a /src folder)
set rtl_files [glob -nocomplain src/*.v src/*.sv]
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
}

# Add Simulation Sources (Assuming Claude saves testbenches in a /sim folder)
set tb_files [glob -nocomplain sim/*_tb.v sim/*_tb.sv]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
}

# Update hierarchy
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "SUCCESS: Added new Claude generated files."
close_project