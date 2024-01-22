/** @module : tb_ooo_core
 *  @author : Secure, Trusted, and Assured Microelectronics (STAM) Center

 *  Copyright (c) 2022 Trireme (STAM/SCAI/ASU)
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.

 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 */

module tb_ooo_core();

parameter XLEN                 = 64;
parameter REG_INDEX_WIDTH      = 5;
parameter ROB_INDEX_WIDTH      = 5;
parameter IQ_ADDR_WIDTH        = 5;
parameter RS_SLOTS_INDEX_WIDTH = 5;
parameter SB_INDEX_WIDTH       = 4;
parameter LB_INDEX_WIDTH       = 4;
parameter ASID_BITS            = XLEN == 32 ? 4  : 16;
parameter PPN_BITS             = XLEN == 32 ? 22 : 44;
parameter SATP_MODE_BITS       = XLEN == 32 ? 1  : 4;

reg clock;
reg reset;
// Fetch port to memory
reg                       fetch_request_ready;
wire                      fetch_request_valid;
wire [XLEN          -1:0] fetch_request_PC;
// Fetch port from memory
reg                       fetch_response_valid;
wire                      fetch_response_ready;
reg  [XLEN          -1:0] fetch_response_instruction;
reg  [XLEN          -1:0] fetch_response_PC;
// To the data memory interface
wire                      memory_read;
wire                      memory_write;
wire [XLEN/8        -1:0] memory_byte_en;
wire [XLEN          -1:0] memory_address_out;
wire [XLEN          -1:0] memory_data_out;
reg  [XLEN          -1:0] memory_data_in;
reg  [XLEN          -1:0] memory_address_in;
reg                       memory_valid;
reg                       memory_ready;
reg                       memory_SC_successful;
wire                      memory_atomic;
// Exception/Interrupt Trap Signals
reg                       m_ext_interrupt;
reg                       s_ext_interrupt;
reg                       software_interrupt;
reg                       timer_interrupt;
reg                       i_mem_page_fault;
reg                       i_mem_access_fault;
reg                       d_mem_page_fault;
reg                       d_mem_access_fault;
// Privilege CSRs for Virtual Memory
wire [PPN_BITS      -1:0] PT_base_PPN; // from satp register
wire [ASID_BITS     -1:0] ASID;        // from satp register
wire [1               :0] priv;        // current privilege level
wire [1               :0] MPP;         // from mstatus register
wire [SATP_MODE_BITS-1:0] MODE;        // paging mode
wire                      SUM;         // permit Supervisor User Memory access
wire                      MXR;         // Make eXecutable Readable
wire                      MPRV;        // Modify PRiVilege
// TLB invalidate signals from sfence.vma
wire                      tlb_invalidate;
wire [1:0]                tlb_invalidate_mode;
//scan signal
reg                       scan;

ooo_core #(
  .XLEN(XLEN),
  .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
  .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
  .IQ_ADDR_WIDTH(IQ_ADDR_WIDTH),
  .RS_SLOTS_INDEX_WIDTH(RS_SLOTS_INDEX_WIDTH),
  .SB_INDEX_WIDTH(SB_INDEX_WIDTH),
  .LB_INDEX_WIDTH(LB_INDEX_WIDTH),
  .ASID_BITS(ASID_BITS),
  .PPN_BITS(PPN_BITS),
  .SATP_MODE_BITS(SATP_MODE_BITS)
) DUT (
  .clock(clock),
  .reset(reset),
  // Fetch port to memory
  .fetch_request_ready(fetch_request_ready),
  .fetch_request_valid(fetch_request_valid),
  .fetch_request_PC(fetch_request_PC),
  // Fetch port from memory
  .fetch_response_valid(fetch_response_valid),
  .fetch_response_ready(fetch_response_ready),
  .fetch_response_instruction(fetch_response_instruction),
  .fetch_response_PC(fetch_response_PC),
  // To the data memory interface
  .memory_read(memory_read),
  .memory_write(memory_write),
  .memory_byte_en(memory_byte_en),
  .memory_address_out(memory_address_out),
  .memory_data_out(memory_data_out),
  .memory_data_in(memory_data_in),
  .memory_address_in(memory_address_in),
  .memory_valid(memory_valid),
  .memory_ready(memory_ready),
  .memory_SC_successful(memory_SC_successful),
  .memory_atomic(memory_atomic),
  // Exception/Interrupt Trap Signals
  .m_ext_interrupt(m_ext_interrupt),
  .s_ext_interrupt(s_ext_interrupt),
  .software_interrupt(software_interrupt),
  .timer_interrupt(timer_interrupt),
  .i_mem_page_fault(i_mem_page_fault),
  .i_mem_access_fault(i_mem_access_fault),
  .d_mem_page_fault(d_mem_page_fault),
  .d_mem_access_fault(d_mem_access_fault),
  // Privilege CSRs for Virtual Memory
  .PT_base_PPN(PT_base_PPN), // from satp register
  .ASID(ASID),        // from satp register
  .priv(priv),        // current privilege level
  .MPP(MPP),         // from mstatus register
  .MODE(MODE),        // paging mode
  .SUM(SUM),         // permit Supervisor User Memory access
  .MXR(MXR),         // Make eXecutable Readable
  .MPRV(MPRV),        // Modify PRiVilege
  // TLB invalidate signals from sfence.vma
  .tlb_invalidate(tlb_invalidate),
  .tlb_invalidate_mode(tlb_invalidate_mode),
  //scan signal
  .scan(scan)
);

always #5 clock = ~clock;

initial begin
  clock = 1'b1;
  reset = 1'b1;
  // Fetch port to memory
  fetch_request_ready = 1'b1;
  // Fetch port from memory
  fetch_response_valid = 1'b0;
  fetch_response_instruction = 64'h00000013_00000013;
  fetch_response_PC          = 0;
  // To the data memory interface
  memory_data_in    = 0;
  memory_address_in = 0;
  memory_valid      = 1'b0;
  memory_ready      = 1'b1;
  memory_SC_successful = 1'b0;
  // Exception/Interrupt Trap Signals
  m_ext_interrupt    = 1'b0;
  s_ext_interrupt    = 1'b0;
  software_interrupt = 1'b0;
  timer_interrupt    = 1'b0;
  i_mem_page_fault   = 1'b0;
  i_mem_access_fault = 1'b0;
  d_mem_page_fault   = 1'b0;
  d_mem_access_fault = 1'b0;

  //scan signal
  scan = 1'b0;

  repeat (10) @ (posedge clock);
  reset = 1'b0;

  repeat (1) @ (posedge clock);
  if(fetch_request_valid !== 1'b1 |
     fetch_request_PC    !== 32'd0) begin
    $display("\ntb_ooo_core --> Test Failed!\n\n");
    $stop;
  end

  repeat (1) @ (posedge clock);
  if(fetch_request_valid !== 1'b1 |
     fetch_request_PC    !== 32'd4) begin
    $display("\ntb_ooo_core --> Test Failed!\n\n");
    $stop;
  end

  repeat (1) @ (posedge clock);
  $display("\ntb_ooo_core --> Test Passed!\n\n");
  $stop;
end

endmodule
