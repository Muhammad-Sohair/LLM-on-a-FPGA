# Read all our SystemVerilog source files
read_verilog -sv [glob src/*.sv]

# Run Out-Of-Context Synthesis for the Vector Array
# We are using the Zynq UltraScale+ part recommended in your documentation (ZCU104)
synth_design -top ternary_accelerator_top -part xczu7ev-ffvc1156-2-e -mode out_of_context

# Generate the resource report
report_utilization -file synth_utilization_report.txt
puts "SUCCESS: Synthesis complete. Check synth_utilization_report.txt"