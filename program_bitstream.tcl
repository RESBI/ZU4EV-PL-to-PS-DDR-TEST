set bit_file "./pl_ps_ddr_mem_test_proj/pl_ps_ddr_mem_test.runs/impl_1/system_wrapper.bit"

if {![file exists $bit_file]} {
    puts "ERROR: bitstream not found: $bit_file"
    exit 1
}

open_hw_manager
connect_hw_server
open_hw_target

set devs [get_hw_devices]
puts "Detected devices: $devs"

set fpga_dev ""
foreach dev $devs {
    set part [get_property PART $dev]
    if {[string match -nocase *xczu4ev* $part] || [string match -nocase *zu4ev* $dev]} {
        set fpga_dev $dev
        break
    }
}

if {$fpga_dev eq ""} {
    set fpga_dev [lindex $devs 0]
}

puts "Programming device: $fpga_dev"
puts "Bitstream: $bit_file"
current_hw_device $fpga_dev
refresh_hw_device -update_hw_probes false $fpga_dev
set_property PROGRAM.FILE $bit_file $fpga_dev
program_hw_devices $fpga_dev
refresh_hw_device $fpga_dev
puts "PROGRAM DONE"

close_hw_manager
