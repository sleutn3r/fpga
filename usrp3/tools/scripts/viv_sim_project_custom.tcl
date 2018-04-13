#
# Copyright 2014 Ettus Research
#

# ---------------------------------------
# Gather all external parameters
# ---------------------------------------
set simulator       $::env(VIV_SIMULATOR)
set design_srcs     $::env(VIV_DESIGN_SRCS)
set sim_srcs        $::env(VIV_SIM_SRCS)
set inc_srcs        $::env(VIV_INC_SRCS)
set sim_top         $::env(VIV_SIM_TOP)
set part_name       $::env(VIV_PART_NAME)
set sim_runtime     $::env(VIV_SIM_RUNTIME)
set sim_fast        $::env(VIV_SIM_FAST)
set vivado_mode     $::env(VIV_MODE)
set working_dir     [pwd]

set sim_fileset "sim_1"
set project_name "[string tolower $simulator]_proj"

if [info exists ::env(VIV_SIM_COMPLIBDIR) ] {
    set sim_complibdir  $::env(VIV_SIM_COMPLIBDIR)
    if [expr [file isdirectory $sim_complibdir] == 0] {
        set sim_complibdir  ""
    }
} else {
    set sim_complibdir  ""
}
if [expr ([string equal $simulator "XSim"] == 0) && ([string length $sim_complibdir] == 0)] {
    puts "BUILDER: \[ERROR\]: Could not resolve the location for the compiled simulation libraries."
    puts "                  Please build libraries for chosen simulator and set the env or"
    puts "                  makefile variable SIM_COMPLIBDIR to point to the location."
    exit 1
}

# ---------------------------------------
# Vivado Commands
# ---------------------------------------
puts "BUILDER: Creating Vivado simulation project part $part_name"
create_project -part $part_name -force $project_name/$project_name

foreach src_file $design_srcs {
    set src_ext [file extension $src_file ]
    if [expr [lsearch {.vhd .vhdl} $src_ext] >= 0] {
        puts "BUILDER: Adding VHDL    : $src_file"
        read_vhdl $src_file
    } elseif [expr [lsearch {.v .vh} $src_ext] >= 0] {
        puts "BUILDER: Adding Verilog : $src_file"
        read_verilog $src_file
    } elseif [expr [lsearch {.sv} $src_ext] >= 0] {
        puts "BUILDER: Adding SVerilog: $src_file"
        read_verilog -sv $src_file
    } elseif [expr [lsearch {.xdc} $src_ext] >= 0] {
        puts "BUILDER: Adding XDC     : $src_file"
        read_xdc $src_file
    } elseif [expr [lsearch {.xci} $src_ext] >= 0] {
        puts "BUILDER: Adding IP      : $src_file"
        read_ip $src_file
    } elseif [expr [lsearch {.ngc .edif} $src_ext] >= 0] {
        puts "BUILDER: Adding Netlist : $src_file"
        read_edif $src_file
    } elseif [expr [lsearch {.bd} $src_ext] >= 0] {
            puts "BUILDER: Adding Block Diagram: $src_file"
            add_files -norecurse $src_file
    } elseif [expr [lsearch {.bxml} $src_ext] >= 0] {
            puts "BUILDER: Adding Block Diagram XML: $src_file"
            add_files -norecurse $src_file
    } else {
        puts "BUILDER: \[WARNING\] File ignored!!!: $src_file"
    }
}

foreach sim_src $sim_srcs {
    puts "BUILDER: Adding Sim Src : $sim_src"
    add_files -fileset $sim_fileset -norecurse $sim_src
}

foreach inc_src $inc_srcs {
    puts "BUILDER: Adding Inc Src : $inc_src"
    add_files -fileset $sim_fileset -norecurse $inc_src
}

# Simulator independent config
set_property top $sim_top [get_filesets $sim_fileset]
set_property default_lib xil_defaultlib [current_project]
update_compile_order -fileset sim_1 -quiet

# Select the simulator
# WARNING: Do this first before setting simulator specific properties!
set_property target_simulator $simulator [current_project]

# Vivado quirk when passing options to external simulators
if [expr [string equal $simulator "XSim"] == 1] {
    set_property verilog_define "WORKING_DIR=\"$working_dir\"" [get_filesets $sim_fileset]
} else {
    set_property verilog_define "WORKING_DIR=$working_dir" [get_filesets $sim_fileset]
}

# XSim specific settings
set_property xsim.simulate.runtime "${sim_runtime}us" -objects [get_filesets $sim_fileset]
set_property xsim.elaborate.debug_level "all" -objects [get_filesets $sim_fileset]
set_property xsim.elaborate.unifast $sim_fast -objects [get_filesets $sim_fileset]
# Set default timescale to prevent bogus warnings
set_property xsim.elaborate.xelab.more_options -value {-timescale 1ns/1ns} -objects [get_filesets $sim_fileset]

# Modelsim specific settings
if [expr [string equal $simulator "Modelsim"] == 1] {
    set sim_64bit       $::env(VIV_SIM_64BIT)

    set_property compxlib.compiled_library_dir $sim_complibdir [current_project]
    # Does not work yet (as of Vivado 2015.2), but will be useful for 32-bit support
    # See: http://www.xilinx.com/support/answers/62210.html
    set_property modelsim.64bit $sim_64bit -objects [get_filesets $sim_fileset]
    set_property modelsim.simulate.runtime "${sim_runtime}ns" -objects [get_filesets $sim_fileset]
    set_property modelsim.elaborate.acc "true" -objects [get_filesets $sim_fileset]
    set_property modelsim.simulate.log_all_signals "true" -objects [get_filesets $sim_fileset]
    set_property modelsim.simulate.vsim.more_options -value "-c" -objects [get_filesets $sim_fileset]
    set_property modelsim.elaborate.unifast $sim_fast -objects [get_filesets $sim_fileset]
    if [info exists ::env(VIV_SIM_USER_DO) ] {
        set_property modelsim.simulate.custom_udo -value "$::env(VIV_SIM_USER_DO)" -objects [get_filesets $sim_fileset]
    }
}

# Set testbench scenario (selects correct test data file) ...
set verilog_define_current [get_property verilog_define [get_filesets sim_1]]
if [info exists ::env(TB_DATA_FILE) ] {
    set TB_DATA_FILE $::env(TB_DATA_FILE)
} else {
    set TB_DATA_FILE ""
    puts "\x1b\[0;38;2;255;135;0m\[WARNING\]: No `TB_DATA_FILE` environment variable was specified. Set to `\"\"`.\x1b\[0m"
}

# ... and eventually more environment variables
if [info exists ::env(FFT_SIZE) ] {
    set FFT_SIZE $::env(FFT_SIZE)
} else {
    set FFT_SIZE 0
}
if [info exists ::env(NUM_SYMS) ] {
    set NUM_SYMS $::env(NUM_SYMS)
} else {
    set NUM_SYMS 0
}
if [info exists ::env(NUM_PACKETS) ] {
    set NUM_PACKETS $::env(NUM_PACKETS)
} else {
    set NUM_PACKETS 0
}
if [info exists ::env(MAX_FILE_LEN) ] {
    set MAX_FILE_LEN $::env(MAX_FILE_LEN)
} else {
    set MAX_FILE_LEN 0
}
if [info exists ::env(NUM_LP_SYMS) ] {
    set NUM_LP_SYMS $::env(NUM_LP_SYMS)
} else {
    set NUM_LP_SYMS 0
}

set_property verilog_define "$verilog_define_current TB_DATA_FILE=\"$TB_DATA_FILE\" FFT_SIZE=$FFT_SIZE NUM_SYMS=$NUM_SYMS NUM_PACKETS=$NUM_PACKETS MAX_FILE_LEN=$MAX_FILE_LEN NUM_LP_SYMS=$NUM_LP_SYMS" [get_filesets $sim_fileset]
puts "\x1b\[0;38;2;20;70;230mINFO: The following verilog defines were set for simulation: [get_property verilog_define [get_filesets $sim_fileset]]\x1b\[0m"

# Launch simulation
launch_simulation

if [string equal $vivado_mode "batch"] {
    puts "BUILDER: Closing project"
    close_project
} else {
    puts "BUILDER: In GUI mode. Leaving project open."
}
