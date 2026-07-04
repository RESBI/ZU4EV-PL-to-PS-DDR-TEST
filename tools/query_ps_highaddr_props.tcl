set part_name "xczu4ev-sfvc784-2-i"
create_project -force ps_prop_query ./ps_prop_query_proj -part $part_name
create_bd_design "q"
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0
set ps [get_bd_cells zynq_ultra_ps_e_0]
foreach {prop value} {
    CONFIG.PSU__HIGH_ADDRESS__ENABLE 1
    CONFIG.PSU__DDR_HIGH_ADDRESS_GUI_ENABLE 1
    CONFIG.PSU_DDR_RAM_HIGHADDR 0x7FFFFFFF
    CONFIG.PSU_DDR_RAM_HIGHADDR_OFFSET 0x00000002
    CONFIG.PSU_DDR_RAM_LOWADDR_OFFSET 0x80000000
} {
    if {[lsearch -exact [list_property $ps] $prop] >= 0} {
        if {[catch {set_property $prop $value $ps} err]} {
            puts "SET FAILED $prop=$value: $err"
        } else {
            puts "SET OK $prop=$value"
        }
    } else {
        puts "MISSING $prop"
    }
}
puts "Matching PS properties:"
foreach prop [lsort [list_property $ps]] {
    if {[regexp -nocase {DDR|HIGH|LOW|ADDR} $prop]} {
        set value "<unreadable>"
        catch {set value [get_property $prop $ps]}
        puts "$prop = $value"
    }
}
exit
