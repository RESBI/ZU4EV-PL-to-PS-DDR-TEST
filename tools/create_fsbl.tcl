# create_fsbl.tcl
# Run with: xsct create_fsbl.tcl
#
# Builds the ZynqMP FSBL (for psu_cortexa53_0) directly through HSI,
# bypassing the Vitis platform auto-boot-domain flow that fails on this
# Vitis install due to a MicroBlaze newlib libgcc path issue. HSI works
# per-processor, so only the A53 standalone BSP is generated (ARM toolchain),
# avoiding the PMU/MicroBlaze path entirely.

set xsa_file  "./pl_ps_ddr_mem_test.xsa"
set out_root  "./vitis_ws/fsbl_build"
set bsp_dir   "$out_root/bsp"
set app_dir   "$out_root/fsbl"
set proc_name "psu_cortexa53_0"
set os_name   "standalone"
set app_name  "fsbl"

if {![file exists $xsa_file]} {
    puts "ERROR: XSA not found: [file normalize $xsa_file]"
    exit 1
}

file delete -force $out_root
file mkdir $out_root

puts "=== Opening hardware design ==="
hsi open_hw_design $xsa_file

puts "=== Creating FSBL sw design on $proc_name ==="
hsi create_sw_design $app_name -proc $proc_name -os $os_name -app zynqmp_fsbl

puts "=== Generating + compiling BSP ==="
hsi generate_bsp -dir $bsp_dir -compile

puts "=== Generating FSBL app sources ==="
if {[catch {hsi generate_app -app zynqmp_fsbl -dir $app_dir} err]} {
    puts "NOTE: generate_app -app zynqmp_fsbl failed: $err"
    puts "      Trying generate_app without -app..."
    if {[catch {hsi generate_app -dir $app_dir} err2]} {
        puts "ERROR: generate_app failed both ways: $err2"
        exit 1
    }
}

puts "=== Compiling FSBL ==="
set orig [pwd]
cd $app_dir
if {[catch {exec make clean 2>@1} err]} { puts "make clean: $err" }
if {[catch {exec make all 2>@1} mk_out]} {
    puts "ERROR: make failed"
    puts $mk_out
    cd $orig
    exit 1
}
puts $mk_out
cd $orig

set fsbl_elf "$app_dir/fsbl.elf"
if {![file exists $fsbl_elf]} {
    # Some builds place it elsewhere
    set alts [glob -nocomplain -directory $app_dir *.elf]
    if {[llength $alts] > 0} { set fsbl_elf [lindex $alts 0] }
}

puts ""
puts "========================================"
if {[file exists $fsbl_elf]} {
    puts " FSBL ELF: [file normalize $fsbl_elf]"
} else {
    puts "ERROR: FSBL ELF not found in $app_dir"
    exit 1
}
puts "========================================"
