# create_boot_image.tcl
# Run with: xsct create_boot_image.tcl
#
# Creates a BOOT.BIN for SD/QSPI boot, containing FSBL + bitstream.
# This is the non-volatile boot alternative to boot_jtag.tcl.
# Flash this to SD card or QSPI and set boot mode pins accordingly.
#
# Prerequisites:
#   - pl_ps_ddr_mem_test.xsa exists (from Vivado build)
#   - FSBL ELF exists (from tools/create_fsbl.tcl)
#   - Bitstream exists (from Vivado build)

set bit_file "./pl_ps_ddr_mem_test_proj/pl_ps_ddr_mem_test.runs/impl_1/system_wrapper.bit"
set fsbl_elf "./vitis_ws/fsbl_build/fsbl/executable.elf"
set bif_file "./boot.bif"
set boot_bin "./BOOT.BIN"

if {![file exists $bit_file]} { puts "ERROR: bitstream not found"; exit 1 }
if {![file exists $fsbl_elf]} { puts "ERROR: FSBL ELF not found"; exit 1 }

# Create BIF file
set fd [open $bif_file w]
puts $fd "the_ROM_image:"
puts $fd "{"
puts $fd "  \[bootloader\] [file normalize $fsbl_elf]"
puts $fd "  \[destination_device = pl\] [file normalize $bit_file]"
puts $fd "}"
close $fd

puts "BIF file: [file normalize $bif_file]"
puts "Creating BOOT.BIN..."

exec bootgen -image $bif_file -arch zynqmp -process_type fsbl -o $boot_bin -w on

if {[file exists $boot_bin]} {
    puts ""
    puts "========================================"
    puts " BOOT.BIN created: [file normalize $boot_bin]"
    puts " Size: [file size $boot_bin] bytes"
    puts "========================================"
    puts ""
    puts "To boot from SD card:"
    puts "  1. Copy BOOT.BIN to the root of a FAT-formatted SD card"
    puts "  2. Set board boot mode to SD (typically SW6 pins)"
    puts "  3. Power on - FSBL initializes PS DDR, then loads bitstream to PL"
    puts "  4. Run: python host/pl_ps_ddr_test.py --port COM6 --query-map"
} else {
    puts "ERROR: BOOT.BIN was not created"
    exit 1
}
