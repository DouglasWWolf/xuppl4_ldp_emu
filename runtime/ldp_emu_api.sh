#==============================================================================
#  Date      Vers   Who  Description
# -----------------------------------------------------------------------------
# 16-Jun-24  1.0.0  DWW  Initial Creation
#==============================================================================
LDP_EMU_API_VERSION=1.0.0

#==============================================================================
# AXI register definitions
#==============================================================================
          REG_CTRL=0x1004
        REG_STATUS=0x1004
       REG_LOAD_F0=0x1008
        REG_COUNT0=0x1008
       REG_LOAD_F1=0x100C
        REG_COUNT1=0x100C
         REG_START=0x1010
     REG_CONT_MODE=0x1014
   REG_NSHOT_LIMIT=0x1018
         REG_VALUE=0x1040

MC_BASE=0x2000
       REG_FRAME_SIZE=$((MC_BASE +  0 *4))       
   REG_BYTES_PER_USEC=$((MC_BASE +  1 *4))       

   REG_FD0_RING_ADDRH=$((MC_BASE +  2 *4))
   REG_FD0_RING_ADDRL=$((MC_BASE +  3 *4))
   REG_FD1_RING_ADDRH=$((MC_BASE +  4 *4))
   REG_FD1_RING_ADDRL=$((MC_BASE +  5 *4))
    REG_FD_RING_SIZEH=$((MC_BASE +  6 *4))
    REG_FD_RING_SIZEL=$((MC_BASE +  7 *4))

   REG_MD0_RING_ADDRH=$((MC_BASE +  8 *4))
   REG_MD0_RING_ADDRL=$((MC_BASE +  9 *4))
   REG_MD1_RING_ADDRH=$((MC_BASE + 10 *4))
   REG_MD1_RING_ADDRL=$((MC_BASE + 11 *4))
    REG_MD_RING_SIZEH=$((MC_BASE + 12 *4))
    REG_MD_RING_SIZEL=$((MC_BASE + 13 *4))

         REG_FC_ADDRH=$((MC_BASE + 14 *4))
         REG_FC_ADDRL=$((MC_BASE + 15 *4))
         REG_METADATA=$((MC_BASE + 16 *4))

#==============================================================================



#==============================================================================
# This reads a PCI register and displays its value in decimal
#==============================================================================
read_reg()
{
    pcireg -dec $1
}
#==============================================================================



#==============================================================================
# This confirms that we have the correct RTL loaded into the FPGA
#==============================================================================
confirm_rtl()
{
    local REG_RTL_TYPE=20

    # Read the RTL_TYPE register
    local rtl_type=$(read_reg $REG_RTL_TYPE)

    # If it's 0xFFFF_FFFF, we need to re-enumerate the PCI bus
    if [ $rtl_type -eq $((0xFFFFFFFF)) ]; then
        echo "Re-enumerating PCI bus..." 1>&2
        hot_reset 1>/dev/null 2>/dev/null
        rtl_type=$(read_reg $REG_RTL_TYPE)
    fi

    # echo a "1" for pass or a "0" for fail
    test $rtl_type -eq 6172024 && echo "1" || echo "0"
}
#==============================================================================



#==============================================================================
# Sets the size of an output frame, in bytes
#
# Must be a power of 2
#==============================================================================
set_frame_size()
{
    pcireg $REG_FRAME_SIZE $1
}
#==============================================================================


#==============================================================================
# Set the maximum output bandwidth in bytes per microsecond
#
# The rate should be evenly divisible by 64
#==============================================================================
set_rate_limit()
{
    pcireg $REG_BYTES_PER_USEC $1
}
#==============================================================================


#==============================================================================
# Gets and displays the maximum output bandwidth in bytes per microsecond
#==============================================================================
get_rate_limit()
{
    read_reg $REG_BYTES_PER_USEC
}
#==============================================================================


#==============================================================================
# Set the Host-RAM address and size of frame-data buffers
#==============================================================================
set_fd0_ring_addr()
{
    pcireg -wide $REG_FD0_RING_ADDRH $1
}
set_fd1_ring_addr()
{
    pcireg -wide $REG_FD1_RING_ADDRH $1
}
set_fd_ring_size()
{
    pcireg -wide $REG_FD_RING_SIZEH $1    
}
#==============================================================================


#==============================================================================
# Set the Host-RAM address and size of meta-data buffers
#==============================================================================
set_md0_ring_addr()
{
    pcireg -wide $REG_MD0_RING_ADDRH $1
}
set_md1_ring_addr()
{
    pcireg -wide $REG_MD1_RING_ADDRH $1
}
set_md_ring_size()
{
    pcireg -wide $REG_MD_RING_SIZEH $1    
}
#==============================================================================


#==============================================================================
# This configures the address where the frame counter is stored
#==============================================================================
set_frame_counter_addr()
{
    pcireg -wide $REG_FC_ADDRH $1
}
#==============================================================================



#==============================================================================
# This displays the number of the active FIFO, or "0" if neither is active
#==============================================================================
get_active_fifo()
{
    read_reg $REG_START
}
#==============================================================================


#==============================================================================
# This waits for the specified FIFO to become active
#
# $1 should be 0, 1, or 2
#==============================================================================
wait_active_fifo()
{
    local which_fifo=$1

    # Validate the input parameter    
    if [ -z $which_fifo ]; then
        echo "Missing parameter on wait_active_fifo()" 1>&2
        return 
    elif [ $which_fifo -lt 0 ] || [ $which_fifo -gt 2 ]; then
        echo "Bad parameter [$which_fifo] on wait_active_fifo()" 1>&2
        return 
    fi

    # Wait for the specified FIFO to become active
    while [ $(read_reg $REG_START) -ne $which_fifo ]; do
        sleep .1
    done
}
#==============================================================================




#==============================================================================
# This stops all data output and causes the system to go idle
#==============================================================================
idle_system()
{
    # Make the system go idle when the current bright-cycle has been emitted
    pcireg $REG_START 0

    # Wait for the current bright-cycle to finish being sent
    wait_active_fifo 0
}
#==============================================================================


#==============================================================================
# This stores 32-bit words to the 64-byte meta-command buffer
#
# $1 = Index (0 thru 15)
# $2 = Value to store
#==============================================================================
set_metadata()
{
    local index=$1
    local value=$2

    if [ -z $index ] || [ -z $value ]; then
        echo "Missing parameter on set_metacommand()" 2>&1
        return
    fi

    if [ $index -lt 0 ] || [ $index -gt 15 ]; then
        echo "Bad index [$index] on set_metacommand()" 2>&1
        return
    fi

    # Compute the address of the register where we'll store this value
    local register=$((REG_METADATA + (15 - $index)*4))

    # Store the specified value into the metacommand register
    pcireg $register $value
}
#==============================================================================



#==============================================================================
# This clears one or both frame-data input FIFOs
#
# $1 should be 1, 2, or "both"
#==============================================================================
clear_fifo()
{
    local which_fifo=$1
    
    # A missing parameter or the word "both" means "clear them both"
    test "$which_fifo" == "both" && which_fifo=3
    test "$which_fifo" == ""     && which_fifo=3

 
    if [ $which_fifo -ge 1 ] && [ $which_fifo -le 3 ]; then
        pcireg $REG_CTRL $which_fifo
    else
        echo "Bad parameter [$1] on clear_fifo()" 1>&2
    fi
}
#==============================================================================


#==============================================================================
# This returns the number of entries in the specified FIFO
#==============================================================================
get_fifo_count()
{
    local which_fifo=$1
    
    if [ -z $which_fifo ]; then
        echo "Missing parameter on get_fifo_count()" 1>&2
        echo 0
    elif [ $which_fifo -eq 1 ]; then
        read_reg $REG_COUNT0
    elif [ $which_fifo -eq 2 ]; then
        read_reg $REG_COUNT1
    else
        echo "Bad parameter [$1] on get_fifo_count()" 1>&2
        echo 0
    fi
}
#==============================================================================


#==============================================================================
# This loads data info one of the FIFOS
#==============================================================================
load_fifo()
{
    local which_fifo=$1
    local filename=$2

    # Validate the fifo #
    if [ -z $which_fifo ]; then
        echo "Missing parameter on load_fifo()" 1>&2
        return 
    elif [ $which_fifo -lt 1 ] || [ $which_fifo -gt 2 ]; then
        echo "Bad parameter [$which_fifo] on load_fifo()" 1>&2
        return 
    fi

    # Make sure the caller gave us a filename
    if [ -z $filename ]; then
        echo "Missing filename on load_fifo()" 1>&2
        return
    fi

    # Make sure the file actually exists
    if [ ! -f $filename ]; then
        echo "not found: $filename" 1>&2
        return
    fi

    # And load the data
    ./load_bc_emu $which_fifo $filename 1>&2
}
#==============================================================================


#==============================================================================
# This stores an immediate value into one of the FIFOS
#==============================================================================
load_fifo_imm()
{
    local which_fifo=$1
    local value=$2

    # Make sure the caller gave us a value
    if [ -z $value ]; then
        echo "Missing value on load_fifo_imm()" 1>&2
        return
    fi

    # Validate the fifo #
    if [ "$which_fifo" == "1" ]; then
        pcireg $REG_LOAD_F0 $value
    elif [ "$which_fifo" == "2" ]; then
        pcireg $REG_LOAD_F1 $value
    else
        echo "Bad parameter [$which_fifo] on load_fifo_imm()" 1>&2
    fi

}
#==============================================================================



#==============================================================================
# This will start generating data-frames from the specified FIFO
#==============================================================================
start_fifo()
{
    local which_fifo=$1

    # Validate the fifo #
    if [ -z $which_fifo ]; then
        echo "Missing parameter on start_fifo()" 1>&2
        return 
    elif [ $which_fifo -lt 1 ] || [ $which_fifo -gt 2 ]; then
        echo "Bad parameter [$which_fifo] on start_fifo()" 1>&2
        return 
    fi

    # And tell the FPGA to start generating frames from this FIFO
    pcireg $REG_START $which_fifo
}
#==============================================================================



#==============================================================================
# Displays the version of the RTL bitstream
#==============================================================================
get_rtl_version()
{
    local major=$(read_reg 0)
    local minor=$(read_reg 4)
    local revis=$(read_reg 8)
    echo ${major}.${minor}.${revis}
}
#==============================================================================



#==============================================================================
# When a FIFO becomes active, this will cause frames to be generated 
# continuously until they are stopped via "idle_system"
#==============================================================================
set_continuous_mode()
{
    pcireg $REG_CONT_MODE 1
}
#==============================================================================


#==============================================================================
# When a FIFO becomes active, this will cause frames to be generated 
# until all entries from the FIFO have been used, then frame generation stops
#==============================================================================
set_oneshot_mode()
{
    pcireg $REG_CONT_MODE 0
    pcireg $REG_NSHOT_LIMIT 1
}
#==============================================================================


#==============================================================================
# When a FIFO becomes active, this will cause frames to be generated 
# until all entries from the FIFO have been used N times, then frame 
# generation stops
#==============================================================================
set_nshot_mode()
{
    local nshot_limit=1
    
    if [ -z $1 ]; then
        nshot_limit=1
    else
        nshot_limit=$1
    fi

    pcireg $REG_CONT_MODE 0
    pcireg $REG_NSHOT_LIMIT $nshot_limit
}
#==============================================================================

