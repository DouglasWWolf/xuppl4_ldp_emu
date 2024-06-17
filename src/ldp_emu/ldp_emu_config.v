//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 07-Jun-24  DWW     1  Initial creation
//====================================================================================

/*
    This module provides configuration values for the ldp_mannager interface registers
*/

module ldp_emu_config
(
    input clk, resetn,

    output reg[ 31:0] FRAME_SIZE,

    output reg[ 31:0] BYTES_PER_USEC,

    output reg[ 63:0] FD0_RING_ADDR, FD1_RING_ADDR, FD_RING_SIZE,

    output reg[ 63:0] MD0_RING_ADDR, MD1_RING_ADDR, MD_RING_SIZE,

    output reg[ 63:0] FC_ADDR,

    output reg[511:0] METADATA,

    output    [ 31:0] sensor_hdr,
    output            sensor_hdr_enable,

    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[31:0]                             S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[31:0]                             S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
);  

// Sensor-chip header is a fixed value
assign sensor_hdr        = 32'h0FAAF0AA;
assign sensor_hdr_enable = 1;


//=========================  AXI Register Map  =============================
localparam REG_FRAME_SIZE     =  0;
localparam REG_BYTES_PER_USEC =  1;

localparam REG_FD0_RING_ADDRH =  2;
localparam REG_FD0_RING_ADDRL =  3;
localparam REG_FD1_RING_ADDRH =  4;
localparam REG_FD1_RING_ADDRL =  5;
localparam REG_FD_RING_SIZEH  =  6;
localparam REG_FD_RING_SIZEL  =  7;

localparam REG_MD0_RING_ADDRH =  8;
localparam REG_MD0_RING_ADDRL =  9;
localparam REG_MD1_RING_ADDRH = 10;
localparam REG_MD1_RING_ADDRL = 11;
localparam REG_MD_RING_SIZEH  = 12;
localparam REG_MD_RING_SIZEL  = 13;

localparam REG_FC_ADDRH       = 14;
localparam REG_FC_ADDRL       = 15;

localparam REG_METADATA_00    = 32;
localparam REG_METADATA_01    = 33;
localparam REG_METADATA_02    = 34;
localparam REG_METADATA_03    = 35;
localparam REG_METADATA_04    = 36;
localparam REG_METADATA_05    = 37;
localparam REG_METADATA_06    = 38;
localparam REG_METADATA_07    = 39;
localparam REG_METADATA_08    = 40;
localparam REG_METADATA_09    = 41;
localparam REG_METADATA_10    = 42;
localparam REG_METADATA_11    = 43;
localparam REG_METADATA_12    = 44;
localparam REG_METADATA_13    = 45;
localparam REG_METADATA_14    = 46;
localparam REG_METADATA_15    = 47;
//==========================================================================


//==========================================================================
// We'll communicate with the AXI4-Lite Slave core with these signals.
//==========================================================================
// AXI Slave Handler Interface for write requests
wire[31:0]  ashi_windx;     // Input   Write register-index
wire[31:0]  ashi_waddr;     // Input:  Write-address
wire[31:0]  ashi_wdata;     // Input:  Write-data
wire        ashi_write;     // Input:  1 = Handle a write request
reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
wire        ashi_widle;     // Output: 1 = Write state machine is idle

// AXI Slave Handler Interface for read requests
wire[31:0]  ashi_rindx;     // Input   Read register-index
wire[31:0]  ashi_raddr;     // Input:  Read-address
wire        ashi_read;      // Input:  1 = Handle a read request
reg[31:0]   ashi_rdata;     // Output: Read data
reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
wire        ashi_ridle;     // Output: 1 = Read state machine is idle
//==========================================================================

// The state of the state-machines that handle AXI4-Lite read and AXI4-Lite write
reg ashi_write_state, ashi_read_state;

// The AXI4 slave state machines are idle when in state 0 and their "start" signals are low
assign ashi_widle = (ashi_write == 0) && (ashi_write_state == 0);
assign ashi_ridle = (ashi_read  == 0) && (ashi_read_state  == 0);
   
// These are the valid values for ashi_rresp and ashi_wresp
localparam OKAY   = 0;
localparam SLVERR = 2;
localparam DECERR = 3;

// An AXI slave is gauranteed a minimum of 128 bytes of address space
// (128 bytes is 32 32-bit registers)
localparam ADDR_MASK = 8'hFF;

//==========================================================================
// This state machine handles AXI4-Lite write requests
//
// Drives:
//==========================================================================
always @(posedge clk) begin

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_write_state  <= 0;
        FRAME_SIZE        <= 32'h40_0000;
        BYTES_PER_USEC    <= 12288;

    // If we're not in reset, and a write-request has occured...        
    end else case (ashi_write_state)
        
        0:  if (ashi_write) begin
       
                // Assume for the moment that the result will be OKAY
                ashi_wresp <= OKAY;              
            
                // Select the register based on it's index
                case (ashi_windx)
               
                    REG_FRAME_SIZE    : FRAME_SIZE           <= ashi_wdata;
                    REG_BYTES_PER_USEC: BYTES_PER_USEC       <= ashi_wdata;

                    REG_FD0_RING_ADDRH: FD0_RING_ADDR[63:32] <= ashi_wdata;
                    REG_FD0_RING_ADDRL: FD0_RING_ADDR[31:00] <= ashi_wdata;
                    REG_FD1_RING_ADDRH: FD1_RING_ADDR[63:32] <= ashi_wdata;
                    REG_FD1_RING_ADDRL: FD1_RING_ADDR[31:00] <= ashi_wdata;
                    REG_FD_RING_SIZEH : FD_RING_SIZE [63:32] <= ashi_wdata;
                    REG_FD_RING_SIZEL : FD_RING_SIZE [31:00] <= ashi_wdata;

                    REG_MD0_RING_ADDRH: MD0_RING_ADDR[63:32] <= ashi_wdata;
                    REG_MD0_RING_ADDRL: MD0_RING_ADDR[31:00] <= ashi_wdata;
                    REG_MD1_RING_ADDRH: MD1_RING_ADDR[63:32] <= ashi_wdata;
                    REG_MD1_RING_ADDRL: MD1_RING_ADDR[31:00] <= ashi_wdata;
                    REG_MD_RING_SIZEH : MD_RING_SIZE [63:32] <= ashi_wdata;
                    REG_MD_RING_SIZEL : MD_RING_SIZE [31:00] <= ashi_wdata;

                    REG_FC_ADDRH      : FC_ADDR      [63:32] <= ashi_wdata;
                    REG_FC_ADDRL      : FC_ADDR      [31:00] <= ashi_wdata;

                    // Allow the user to store values into the "METADATA" field
                    REG_METADATA_00: METADATA[ 0 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_01: METADATA[ 1 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_02: METADATA[ 2 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_03: METADATA[ 3 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_04: METADATA[ 4 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_05: METADATA[ 5 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_06: METADATA[ 6 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_07: METADATA[ 7 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_08: METADATA[ 8 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_09: METADATA[ 9 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_10: METADATA[10 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_11: METADATA[11 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_12: METADATA[12 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_13: METADATA[13 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_14: METADATA[14 * 32 +: 32] <= ashi_wdata;
                    REG_METADATA_15: METADATA[15 * 32 +: 32] <= ashi_wdata;

                    // Writes to any other register are a decode-error
                    default: ashi_wresp <= DECERR;
                endcase
            end

        // Dummy state, doesn't do anything
        1: ashi_write_state <= 0;

    endcase
end
//==========================================================================





//==========================================================================
// World's simplest state machine for handling AXI4-Lite read requests
//==========================================================================
always @(posedge clk) begin
    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        ashi_read_state <= 0;
    
    // If we're not in reset, and a read-request has occured...        
    end else if (ashi_read) begin
   
        // Assume for the moment that the result will be OKAY
        ashi_rresp <= OKAY;              
        
        // Select the register based on it's index
        case (ashi_rindx)
            
            // Allow a read from any valid register                
            REG_FRAME_SIZE    : ashi_rdata <= FRAME_SIZE;
            REG_BYTES_PER_USEC: ashi_rdata <= BYTES_PER_USEC;

            REG_FD0_RING_ADDRH: ashi_rdata <= FD0_RING_ADDR[63:32];
            REG_FD0_RING_ADDRL: ashi_rdata <= FD0_RING_ADDR[31:00];
            REG_FD1_RING_ADDRH: ashi_rdata <= FD1_RING_ADDR[63:32];
            REG_FD1_RING_ADDRL: ashi_rdata <= FD1_RING_ADDR[31:00];
            REG_FD_RING_SIZEH : ashi_rdata <= FD_RING_SIZE [63:32];
            REG_FD_RING_SIZEL : ashi_rdata <= FD_RING_SIZE [31:00];

            REG_MD0_RING_ADDRH: ashi_rdata <= MD0_RING_ADDR[63:32];
            REG_MD0_RING_ADDRL: ashi_rdata <= MD0_RING_ADDR[31:00];
            REG_MD1_RING_ADDRH: ashi_rdata <= MD1_RING_ADDR[63:32];
            REG_MD1_RING_ADDRL: ashi_rdata <= MD1_RING_ADDR[31:00];
            REG_MD_RING_SIZEH : ashi_rdata <= MD_RING_SIZE [63:32];
            REG_MD_RING_SIZEL : ashi_rdata <= MD_RING_SIZE [31:00];

            REG_FC_ADDRH      : ashi_rdata <= FC_ADDR      [63:32];
            REG_FC_ADDRL      : ashi_rdata <= FC_ADDR      [31:00];

            REG_METADATA_00   : ashi_rdata <= METADATA[ 0 * 32 +: 32];
            REG_METADATA_01   : ashi_rdata <= METADATA[ 1 * 32 +: 32];
            REG_METADATA_02   : ashi_rdata <= METADATA[ 2 * 32 +: 32];
            REG_METADATA_03   : ashi_rdata <= METADATA[ 3 * 32 +: 32];
            REG_METADATA_04   : ashi_rdata <= METADATA[ 4 * 32 +: 32];
            REG_METADATA_05   : ashi_rdata <= METADATA[ 5 * 32 +: 32];
            REG_METADATA_06   : ashi_rdata <= METADATA[ 6 * 32 +: 32];
            REG_METADATA_07   : ashi_rdata <= METADATA[ 7 * 32 +: 32];
            REG_METADATA_08   : ashi_rdata <= METADATA[ 8 * 32 +: 32];
            REG_METADATA_09   : ashi_rdata <= METADATA[ 9 * 32 +: 32];
            REG_METADATA_10   : ashi_rdata <= METADATA[10 * 32 +: 32];
            REG_METADATA_11   : ashi_rdata <= METADATA[11 * 32 +: 32];
            REG_METADATA_12   : ashi_rdata <= METADATA[12 * 32 +: 32];
            REG_METADATA_13   : ashi_rdata <= METADATA[13 * 32 +: 32];
            REG_METADATA_14   : ashi_rdata <= METADATA[14 * 32 +: 32];
            REG_METADATA_15   : ashi_rdata <= METADATA[15 * 32 +: 32];


            // Reads of any other register are a decode-error
            default: ashi_rresp <= DECERR;
        endcase
    end
end
//==========================================================================



//==========================================================================
// This connects us to an AXI4-Lite slave core
//==========================================================================
axi4_lite_slave#(ADDR_MASK) axil_slave
(
    .clk            (clk),
    .resetn         (resetn),
    
    // AXI AW channel
    .AXI_AWADDR     (S_AXI_AWADDR),
    .AXI_AWVALID    (S_AXI_AWVALID),   
    .AXI_AWREADY    (S_AXI_AWREADY),
    
    // AXI W channel
    .AXI_WDATA      (S_AXI_WDATA),
    .AXI_WVALID     (S_AXI_WVALID),
    .AXI_WSTRB      (S_AXI_WSTRB),
    .AXI_WREADY     (S_AXI_WREADY),

    // AXI B channel
    .AXI_BRESP      (S_AXI_BRESP),
    .AXI_BVALID     (S_AXI_BVALID),
    .AXI_BREADY     (S_AXI_BREADY),

    // AXI AR channel
    .AXI_ARADDR     (S_AXI_ARADDR), 
    .AXI_ARVALID    (S_AXI_ARVALID),
    .AXI_ARREADY    (S_AXI_ARREADY),

    // AXI R channel
    .AXI_RDATA      (S_AXI_RDATA),
    .AXI_RVALID     (S_AXI_RVALID),
    .AXI_RRESP      (S_AXI_RRESP),
    .AXI_RREADY     (S_AXI_RREADY),

    // ASHI write-request registers
    .ASHI_WADDR     (ashi_waddr),
    .ASHI_WINDX     (ashi_windx),
    .ASHI_WDATA     (ashi_wdata),
    .ASHI_WRITE     (ashi_write),
    .ASHI_WRESP     (ashi_wresp),
    .ASHI_WIDLE     (ashi_widle),

    // ASHI read registers
    .ASHI_RADDR     (ashi_raddr),
    .ASHI_RINDX     (ashi_rindx),
    .ASHI_RDATA     (ashi_rdata),
    .ASHI_READ      (ashi_read ),
    .ASHI_RRESP     (ashi_rresp),
    .ASHI_RIDLE     (ashi_ridle)
);
//==========================================================================



endmodule
