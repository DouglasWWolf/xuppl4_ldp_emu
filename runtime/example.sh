#
# This is an example script that drives the bright-cycle emulator.   
# This script and "bc_emu_api.sh" was written by Doug Wolf
#

# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><> You can create your own scripts by using this one as a   <><><><>
# <><><><> template.  The upper portion of this script will largely <><><><>
# <><><><> be common between all scripts, and the lower portion can <><><><>
# <><><><> be customized to your particular application             <><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>


# Load our API into our current shell instance
source ldp_emu_api.sh

# By default, we won't load the bitstream
need_bitstream=0;

# Parse the command line
while (( "$#" )); do
    if [ $1 == "-force" ]; then
        need_bitstream=1
        shift
   else
      echo "Invalid command line switch: $1"
      exit 1
   fi
done

# Is the bitstream not yet loaded?
test $(confirm_rtl) -eq 0 && need_bitstream=1

# If we need to load the bitstream into the FPGA, make it so
if [ $need_bitstream -eq 1 ]; then
    echo "Loading bitstream..."
    ./load_bitstream.sh
    test $? -eq 0 || exit 1
    echo "Bitstream loaded"
fi


# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><>  If you are using this script as a template, everything  <><><><>
# <><><><>  below this line is a good place to customize it for     <><><><>
# <><><><>  your particular application                             <><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
# <><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

# Tell the world which version we are
echo "ldp_emu RTL version" $(get_rtl_version)

# Make sure the system is idle
idle_system

# This should be "set_continuous_mode" or "set_nshot_mode"
set_nshot_mode 1000

# Set the output data rate in bytes-per-microsecond. 
set_rate_limit 20000

# A frame is 4M bytes
set_frame_size 0x40_0000

# Define the location and size of the frame-data ring buffers
set_fd0_ring_addr 0x1_0000_0000
set_fd1_ring_addr 0x1_1000_0000
set_fd_ring_size  0x0_0080_0000

# Define the location and size of the meta-data ring buffers
set_md0_ring_addr 0x1_2000_0000
set_md1_ring_addr 0x1_3000_0000
set_md_ring_size  512

# Define the address where the frame counters live in host-RAM
set_frame_counter_addresses 0x1_4000_0000 0x01_4100_0000

# Set the 64-byte fixed portion of the metacommand
set_metadata  0 0x01020304
set_metadata  1 0x05060708
set_metadata  2 0x09101112
set_metadata  3 0x13141516
set_metadata  4 0x17181920
set_metadata  5 0x21222324
set_metadata  6 0x25262728
set_metadata  7 0x29303132
set_metadata  8 0x33343536
set_metadata  9 0x37383940
set_metadata 10 0x41424344
set_metadata 11 0x45464748
set_metadata 12 0x49505152
set_metadata 13 0x53545556
set_metadata 14 0x57585960
set_metadata 15 0x61626364

# Make sure both input FIFOs start out empty
clear_fifo both

# Load frame data into the first FIFO
load_fifo_imm 1 0x11111111
load_fifo_imm 1 0x22222222
load_fifo_imm 1 0x33333333
load_fifo_imm 1 0x44444444
load_fifo_imm 1 0x55555555


# Start generating frames from the data we just loaded
start_fifo 1
echo "Generating bright cycle frames from FIFO #1"

# Wait for the job to finish
wait_active_fifo 0

# That's the end of our demo!
idle_system
echo "All done!"
