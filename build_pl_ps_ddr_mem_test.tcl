set part_name "xczu4ev-sfvc784-2-i"
set proj_name "pl_ps_ddr_mem_test"
set proj_dir  "./pl_ps_ddr_mem_test_proj"
set rtl_dir   "./rtl"
set xdc_file  "./constraints/uart_zu4ev.xdc"
set ref_bd_file "./reference/design_1.bd"

set test_base_addr "0x0000000010000000"
set test_bytes     "0x01000000"
set pl_clk_mhz     "200.000000"
set pl_clk_hz      "200000000"
set uart_baud      "8000000"

proc set_ps_property_if_exists {cell prop value} {
    if {[lsearch -exact [list_property $cell] $prop] >= 0} {
        set_property $prop $value $cell
    }
}

proc apply_ps_config_from_bd {cell bd_file} {
    if {![file exists $bd_file]} {
        puts "WARNING: Reference BD not found: $bd_file"
        return
    }

    set fd [open $bd_file r]
    set bd_text [read $fd]
    close $fd

    set applied 0
    set matches [regexp -all -inline {"([A-Za-z0-9_]+)"[ \t\r\n]*:[ \t\r\n]*\{[ \t\r\n]*"value"[ \t\r\n]*:[ \t\r\n]*"([^"]*)"[ \t\r\n]*\}} $bd_text]
    foreach {full key value} $matches {
        if {[regexp {ACT_FREQ|HIGHADDR|LOWADDR|FREQMHZ$} $key]} {
            continue
        }
        set prop CONFIG.$key
        if {[lsearch -exact [list_property $cell] $prop] >= 0} {
            if {[catch {set_property $prop $value $cell} err]} {
                puts "WARNING: Skipped PS property $prop=$value: $err"
            } else {
                incr applied
            }
        }
    }

    puts "Applied $applied PS properties from reference BD: $bd_file"
}

proc connect_bd_pin_if_exists {src dst} {
    set src_pin [get_bd_pins -quiet $src]
    if {![llength $src_pin]} {
        set src_pin [get_bd_ports -quiet $src]
    }
    set dst_pin [get_bd_pins -quiet $dst]
    if {![llength $dst_pin]} {
        set dst_pin [get_bd_ports -quiet $dst]
    }
    if {[llength $src_pin] && [llength $dst_pin]} {
        connect_bd_net $src_pin $dst_pin
        return 1
    }
    return 0
}

puts "========================================"
puts " PL to PS DDR Memory Test Build"
puts " Part: $part_name"
puts " Reference PS BD: $ref_bd_file"
puts " PL external clock: ${pl_clk_mhz} MHz on E12"
puts " UART baud: $uart_baud"
puts " Test base: $test_base_addr"
puts " Test bytes: $test_bytes"
puts "========================================"

create_project -force $proj_name $proj_dir -part $part_name
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [list \
    $rtl_dir/config.vh \
    $rtl_dir/uart_rx.v \
    $rtl_dir/uart_tx.v \
    $rtl_dir/pl_ps_ddr_mem_test_top.v \
]
set_property include_dirs $rtl_dir [current_fileset]
add_files -fileset constrs_1 $xdc_file

create_bd_design "system"

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0
set ps [get_bd_cells zynq_ultra_ps_e_0]

apply_ps_config_from_bd $ps $ref_bd_file
set_ps_property_if_exists $ps CONFIG.PSU__FPGA_PL0_ENABLE 1
set_ps_property_if_exists $ps CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ $pl_clk_mhz
set_ps_property_if_exists $ps CONFIG.PSU__USE__FABRIC__RST 1
set_ps_property_if_exists $ps CONFIG.PSU__USE__S_AXI_GP0 1
set_ps_property_if_exists $ps CONFIG.PSU__SAXIGP0__DATA_WIDTH 64
set_ps_property_if_exists $ps CONFIG.PSU__USE__S_AXI_GP2 1
set_ps_property_if_exists $ps CONFIG.PSU__SAXIGP2__DATA_WIDTH 64

create_bd_cell -type module -reference pl_ps_ddr_mem_test_top ddr_tester_0
set tester [get_bd_cells ddr_tester_0]
set_property -dict [list \
    CONFIG.CLK_HZ $pl_clk_hz \
    CONFIG.UART_BAUD $uart_baud \
    CONFIG.TEST_BASE_ADDR $test_base_addr \
    CONFIG.TEST_BYTES $test_bytes \
] $tester

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_smc_0
set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells axi_smc_0]

create_bd_port -dir I -type clk sys_clk
set_property CONFIG.FREQ_HZ $pl_clk_hz [get_bd_ports sys_clk]

connect_bd_net [get_bd_ports sys_clk] [get_bd_pins ddr_tester_0/aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins ddr_tester_0/aresetn]
connect_bd_net [get_bd_ports sys_clk] [get_bd_pins axi_smc_0/aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins axi_smc_0/aresetn]

set hp_clock_connected 0
foreach pin_name {saxihp0_fpd_aclk saxigp0_aclk saxihpc0_fpd_aclk maxihpm0_lpd_aclk maxihpm0_fpd_aclk} {
    if {[connect_bd_pin_if_exists sys_clk zynq_ultra_ps_e_0/$pin_name]} {
        set hp_clock_connected 1
    }
}
if {$hp_clock_connected == 0} {
    puts "WARNING: Could not find an HP0/HPC0 AXI clock pin by known names. Validate the PS AXI clock connection in the block design."
}

set axi_connected 0
foreach ps_intf {S_AXI_HP0_FPD S_AXI_HPC0_FPD S_AXI_HP0} {
    if {[llength [get_bd_intf_pins -quiet axi_smc_0/M00_AXI]] && [llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/$ps_intf]]} {
        connect_bd_intf_net [get_bd_intf_pins ddr_tester_0/M_AXI] [get_bd_intf_pins axi_smc_0/S00_AXI]
        connect_bd_intf_net [get_bd_intf_pins axi_smc_0/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/$ps_intf]
        set axi_connected 1
        puts "Connected tester M_AXI through axi_smc_0 to zynq_ultra_ps_e_0/$ps_intf"
        break
    }
}
if {$axi_connected == 0} {
    puts "ERROR: Could not find a usable PS S_AXI HP/HPC interface for PL DDR access."
    exit 1
}

make_bd_pins_external [get_bd_pins ddr_tester_0/uart_rx]
make_bd_pins_external [get_bd_pins ddr_tester_0/uart_tx]
set_property name uart_rx [get_bd_ports uart_rx_0]
set_property name uart_tx [get_bd_ports uart_tx_0]

if {[llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/DDR]]} {
    make_bd_intf_pins_external [get_bd_intf_pins zynq_ultra_ps_e_0/DDR]
}
if {[llength [get_bd_intf_pins -quiet zynq_ultra_ps_e_0/FIXED_IO]]} {
    make_bd_intf_pins_external [get_bd_intf_pins zynq_ultra_ps_e_0/FIXED_IO]
}

assign_bd_address
validate_bd_design
save_bd_design

make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "--- Running Synthesis ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

puts ""
puts "--- Running Implementation + Bitstream ---"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

set bit_files [glob -nocomplain $proj_dir/$proj_name.runs/impl_1/*.bit]
if {[llength $bit_files] > 0} {
    puts ""
    puts "========================================"
    puts " BUILD SUCCESSFUL"
    puts " Bitstream: [lindex $bit_files 0]"
    puts "========================================"
} else {
    puts "ERROR: Bitstream not found"
    exit 1
}
