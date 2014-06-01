`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    12:01:50 05/22/2014 
// Design Name: 
// Module Name:    pci 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module PCI(
    input [31:0] AD_I,
    output reg [31:0] AD_O,
    output reg OE_AD_N,
    input [3:0] CBE_I_N,
    output [3:0] CBE_O_N,
    output OE_CBE_N,
    input PAR_I,
    output reg PAR_O,
    output reg OE_PAR_N,
    input FRAME_I_N,
    output FRAME_O_N,
    output OE_FRAME_N,
    input TRDY_I_N,
    output reg TRDY_O_N,
    output reg OE_TRDY_N,
    input IRDY_I_N,
    output IRDY_O_N,
    output OE_IRDY_N,
    input STOP_I_N,
    output reg STOP_O_N,
    output reg OE_STOP_N,
    input DEVSEL_I_N,
    output reg DEVSEL_O_N,
    output reg OE_DEVSEL_N,
    input IDSEL_I,
    input PERR_I_N,
    output PERR_O_N,     
    output OE_PERR_N,
    input SERR_I_N,
    output OE_SERR_N,
    output OE_REQ_N,     
    input GNT_I_N,
    input CLK,
    output OE_INTA_N,
    output reg PING_DONE,
    input RST
    );

parameter BAR0_WINDOW_BITS = 3;
parameter BAR1_WINDOW_BITS = 3;
parameter IO_SIZE = (BAR0_WINDOW_BITS-2);
parameter MEM_SIZE =(BAR1_WINDOW_BITS-2);
// Device ID and Vendor ID
parameter [31:0] CFG_VENDOR = 32'h0301_10ee;
// Class Code and Revision ID
parameter [31:0] CFG_CC_REVISION = 32'h0b40_0000 ;

reg [31:0] io[0:IO_SIZE];
reg [31:0] mem[0:MEM_SIZE];     
reg [31:BAR0_WINDOW_BITS+1] BAR0_ADDR;   // we respond to an "IO write" at this address
reg [31:BAR1_WINDOW_BITS+1] BAR1_ADDR;   // we respond to an "MEM write" at this address
reg IsWrite;
reg IsConfig;
reg Transaction;
reg [3:0] CurrentAddr;
reg [31:0] CurrentOutput;

reg [15:0]PCICommand; // PCI Command register
parameter IOENABLED_BIT = 0;
parameter MEMENABLED_BIT = 1;
parameter BUSMASTER_BIT = 2;

reg PCIIntStatusBit3; // PCI Status
wire [15:0]PCIStatus = {
/*Detected Parity Error*/1'b0,
/*Signaled system Error*/1'b0,
/*Received Master Abort*/1'b0,
/*Received Target Abort*/1'b0,
/*Signaled Target Abort*/1'b0,
/*DEVSEL timing=MED*/2'b01,
/*Master Data Parity Error*/1'b0,
/*Fast Back-to-Back Capable*/1'b0,
/*reserved*/1'b0,
/*66MHZ*/1'b0,
/*CapabilitiesList*/1'b0,
PCIIntStatusBit3,
/*Reserved*/1'b0,
/*Reserved*/1'b0,
/*Reserved*/1'b0};

wire [8:0] PCIMaxLat = 8'b0;
wire [8:0] PCIMinGnt = 8'b0;
wire [8:0] PCIInterruptPin = 8'b00000001; // #INTA
reg [8:0] PCIInterruptLine;
reg LastParity;
reg BAR0Matches;
reg CFGMatches;
reg TransactionStart;
reg TransactionStarted;
reg DataTransfer;
reg DataTransferNotReady;
reg LastDataTransfer;

assign CBE_O_N = 4'b0;
assign OE_CBE_N = 1'b1;     
assign OE_FRAME_N = 1'b1;
assign OE_IRDY_N = 1'b1;
assign OE_PERR_N = 1'b1;
assign OE_SERR_N = 1'b1;
assign OE_REQ_N = 1'b1;     
assign OE_INTA_N = 1'b1;

// This is only way how to force not removing flip flops on equivalent signals
//reg TRDY_O_FF_N;
//FDPE XPCI_TRDYOQ (.Q(TRDY_O_N),.D(TRDY_O_FF_N),.C(~CLK),.CE(1'b1),.PRE(RST));                                      
//reg OE_TRDY_FF_N;
//FDPE XPCI_OETRDYOQ (.Q(OE_TRDY_N),.D(OE_TRDY_FF_N),.C(~CLK),.CE(1'b1),.PRE(RST));                                      

//reg DEVSEL_O_FF_N;
//FDPE XPCI_DEVSELOQ (.Q(DEVSEL_O_N),.D(DEVSEL_O_FF_N),.C(~CLK),.CE(1'b1),.PRE(RST));                                      
//reg OE_DEVSEL_FF_N;
//FDPE XPCI_OEDEVSELOQ (.Q(OE_DEVSEL_N),.D(OE_DEVSEL_FF_N),.C(~CLK),.CE(1'b1),.PRE(RST));                                      


integer k;
initial
begin 
    BAR0_ADDR[31:BAR0_WINDOW_BITS+1] = {(31 - BAR0_WINDOW_BITS){1'b0}};
    BAR1_ADDR[31:BAR1_WINDOW_BITS+1] = {(31 - BAR1_WINDOW_BITS){1'b0}};
    BAR0Matches = 1'b0;
    CFGMatches =  1'b0;
    Transaction = 1'b0;
    CurrentAddr = 32'b0;
    CurrentOutput = 32'b0;
    IsWrite = 1'b0;
    IsConfig = 1'b0;
    LastParity = 1'b0;
    Transaction = 1'b0;
    TransactionStart = 1'b0;    
    TransactionStarted = 1'b0;
    DataTransfer = 1'b0;
    DataTransferNotReady = 1'b0;
    LastDataTransfer = 1'b0;
    
    for (k = 0; k <= IO_SIZE; k = k + 1)
    begin
        io[k] = 32'b0;
    end
    for (k = 0; k <= MEM_SIZE; k = k + 1)
    begin
        mem[k] = 32'b0;
    end    

    PCICommand = 16'b0;
    PCIIntStatusBit3 = 1'b0;
    PCIInterruptLine = 8'b0;
                
    AD_O = 32'b0;
    OE_AD_N = 1'b1;
    
    TRDY_O_N = 1'b1;
    OE_TRDY_N = 1'b1;

    STOP_O_N = 1'b1;
    OE_STOP_N = 1'b1;


    DEVSEL_O_N = 1'b1;     
    OE_DEVSEL_N = 1'b1;
    
    PAR_O = 1'b0;
    OE_PAR_N = 1'b1;
    
    PING_DONE  = 1'b0;
end

always @(posedge CLK)
begin
   TransactionStart = ~Transaction & ~FRAME_I_N;
   DataTransfer = Transaction & ~IRDY_I_N;
   LastDataTransfer = FRAME_I_N;
   DataTransferNotReady = Transaction & ~FRAME_I_N & IRDY_I_N;   
   BAR0Matches = ((AD_I[31:BAR0_WINDOW_BITS+1]==BAR0_ADDR[31:BAR0_WINDOW_BITS+1]) & (AD_I[1:0] == 2'b00)) ? 1'b1 : 1'b0;
   CFGMatches = ((AD_I[1:0] == 2'b00) & (AD_I[10:8] == 3'b000)) ? 1'b1 : 1'b0;   

   if (TransactionStart)
   begin
       IsConfig = IDSEL_I;
       IsWrite = CBE_I_N[0];
       if (PCICommand[IOENABLED_BIT] & BAR0Matches)
       begin
           CurrentAddr = {{(5-BAR0_WINDOW_BITS){1'b0}}, AD_I[BAR0_WINDOW_BITS:2]};
           TransactionStarted = 1'b1;
       end
       else if (IsConfig & CFGMatches)
       begin
           CurrentAddr = AD_I[5:2];
           TransactionStarted = 1'b1;           
       end
       else
       begin
           TransactionStarted = 1'b0;       
       end
   end
   else
   begin
       TransactionStarted = 1'b0;
   end
   // Parity calculation
   LastParity = ^{CurrentOutput, CBE_I_N};   
end

// output encode
always @(negedge CLK)
begin
   if (TransactionStart)
   begin
       if (TransactionStarted)
       begin
           Transaction = 1'b1;
           DEVSEL_O_N = 1'b0;// this is our transaction
           OE_DEVSEL_N = 1'b0;// this is our transaction
           OE_TRDY_N = 1'b0;// we are always ready
           TRDY_O_N = 1'b0; // we are always ready
           STOP_O_N  = 1'b0; // Always use "Disconnect with data"
           OE_STOP_N = 1'b0;// Always use "Disconnect with data"
           if(~IsWrite)
           begin
               OE_AD_N = 1'b0;
               OE_PAR_N = 1'b0;
           end       
       end
   end
   else if (DataTransfer)
   begin
       if (LastDataTransfer)
       begin
           Transaction = 1'b0;
           // Signal High for now
           DEVSEL_O_N = 1'b1;           
           TRDY_O_N = 1'b1;
           STOP_O_N = 1'b1;
           // Turn off immediately
           OE_AD_N = 1'b1;                      
       end
       //CurrentAddr = CurrentAddr + 1; bursts not supported
   end
   else if (DataTransferNotReady)
   begin
       // WAIT cycle
   end
   else
   begin
       // Turn off after 1 clock
       OE_DEVSEL_N = 1'b1;
       OE_TRDY_N = 1'b1;
       OE_STOP_N = 1'b1;       
       OE_PAR_N = 1'b1;
       // Turn off again for extra resilience
       OE_AD_N = 1'b1;
       Transaction = 1'b0;
   end
   // Output parity with 1 clock skew
   PAR_O = LastParity;
end

// Transfer handling
always @(negedge CLK)
begin
   if ((TransactionStart | DataTransfer) & ~IsWrite) // Read transaction?
   begin
       if (IsConfig)
       begin
           case(CurrentAddr)
               0: CurrentOutput = CFG_VENDOR;
               1: CurrentOutput = {PCIStatus, PCICommand};
               2: CurrentOutput = CFG_CC_REVISION;
               4: CurrentOutput = {BAR0_ADDR[31:BAR0_WINDOW_BITS+1], {(BAR0_WINDOW_BITS){1'b0}}, /* IO space */1'b1}; 
               15: CurrentOutput = {PCIMaxLat, PCIMinGnt, PCIInterruptPin, PCIInterruptLine};
               default: CurrentOutput = 32'b0;
           endcase
       end
       else
       begin
           CurrentOutput = io[CurrentAddr];
       end
       AD_O = CurrentOutput;
   end
end



always @(posedge CLK)
begin
    if (DataTransfer & IsWrite) // Write transaction?
    begin
        if (IsConfig)
        begin
            case(CurrentAddr)
                1: begin
                   if (~CBE_I_N[2])
                       PCIIntStatusBit3 = PCIIntStatusBit3 & ~AD_I[19];
                   if (~CBE_I_N[1])
                       PCICommand[15:8] = AD_I[15:8];
                   if (~CBE_I_N[0])
                       PCICommand[7:0] = AD_I[7:0];
                   end
                4: begin
                   BAR0_ADDR[31:BAR0_WINDOW_BITS+1] = AD_I[31:BAR0_WINDOW_BITS+1];
                   end
                15:begin
                   if (~CBE_I_N[0])
                       PCIInterruptLine = AD_I[7:0];
                   end
                default: begin end // do nothing
            endcase
        end
        else
        begin
            PING_DONE = 1'b1;
            io[CurrentAddr] = AD_I;
        end
    end
end

endmodule

//assign    PCI_CE    = I2 | (!(I3 | TRDY)) | (!(I1 | IRDY));
//PCILOGIC PCILOGIC (
//                .IRDY(IRDY_IN),
//                .TRDY(TRDY_IN),
//                .I1(1'b0),
//                .I2(1'b0),
//                .I3(1'b1),
//                .PCI_CE(PCI_CE)
//                );


