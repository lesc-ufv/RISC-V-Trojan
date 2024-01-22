/** @module : tb_seven_stage_priv_control_unit
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

module tb_seven_stage_priv_control_unit();

//define the log2 function
function integer log2;
input integer value;
begin
  value = value-1;
  for (log2=0; value>0; log2=log2+1)
    value = value >> 1;
end
endfunction

parameter  [6:0]R_TYPE  = 7'b0110011,
                I_TYPE  = 7'b0010011,
                STORE   = 7'b0100011,
                LOAD    = 7'b0000011,
                BRANCH  = 7'b1100011,
                JALR    = 7'b1100111,
                JAL     = 7'b1101111,
                AUIPC   = 7'b0010111,
                LUI     = 7'b0110111,
                FENCES  = 7'b0001111,
                SYSTEM  = 7'b1110011,
                AMO     = 7'b0101111;

parameter CORE            = 0;
parameter DATA_WIDTH      = 32;
parameter ADDRESS_BITS    = 20;
parameter NUM_BYTES       = 32/8;
parameter M_EXTENSION     = "True";
parameter LOG2_NUM_BYTES  = log2(NUM_BYTES);
parameter SCAN_CYCLES_MIN = 0;
parameter SCAN_CYCLES_MAX = 1000;

// Base Control Unit Ports
reg clock;
reg reset;
reg [6:0] opcode_decode;
reg [6:0] opcode_execute;
reg [6:0] opcode_memory_issue;
reg [6:0] opcode_memory_receive;
reg [2:0] funct3; // decode
reg [6:0] funct7; // decode

reg [ADDRESS_BITS-1:0] JALR_target_execute;
reg [ADDRESS_BITS-1:0] branch_target_execute;
reg [ADDRESS_BITS-1:0] JAL_target_decode;
reg branch_execute;

wire branch_op;
wire memRead;
wire [5:0] ALU_operation;
wire memWrite;
wire [LOG2_NUM_BYTES-1:0] log2_bytes;
wire unsigned_load;
wire [1:0] next_PC_sel;
wire [1:0] operand_A_sel;
wire operand_B_sel;
wire [1:0] extend_sel;
wire regWrite;

wire [ADDRESS_BITS-1:0] target_PC;
wire i_mem_read;

// Base Hazard Detection Unit Ports
reg fetch_valid;
reg fetch_ready;
reg [ADDRESS_BITS-1:0] issue_PC;
reg [ADDRESS_BITS-1:0] fetch_address_in;
reg memory_valid;
reg memory_ready;

reg load_memory_receive; // memRead_memory_receive
reg store_memory_issue;  // memWrite_memory_issue
reg store_memory_receive; // memWrite_memory_receive
reg [ADDRESS_BITS-1:0] load_address_receive;
reg [ADDRESS_BITS-1:0] memory_address_in;

// Seven Stage Stall Unit Ports
wire stall_fetch_receive;
wire stall_decode;
wire stall_execute;
wire stall_memory_issue;
wire stall_memory_receive;

wire flush_fetch_receive;
wire flush_decode;
wire flush_execute;
wire flush_memory_issue;
wire flush_memory_receive;
wire flush_writeback;

// Seven Stage Bypass Unit Ports
wire [2:0] rs1_data_bypass;
wire [2:0] rs2_data_bypass;

// CSR & Privilege Control Ports
reg [1:0] priv;
reg       intr_branch;
reg       trap_branch;

reg  [ADDRESS_BITS-1:0] inst_PC_fetch_receive;
reg  [ADDRESS_BITS-1:0] inst_PC_decode;
reg  [ADDRESS_BITS-1:0] inst_PC_execute;
reg  [ADDRESS_BITS-1:0] inst_PC_memory_issue;
reg  [ADDRESS_BITS-1:0] inst_PC_memory_receive;

reg  m_ret_memory_receive;
reg  s_ret_memory_receive;
reg  u_ret_memory_receive;

reg i_mem_page_fault;
reg i_mem_access_fault;
reg d_mem_page_fault;
reg d_mem_access_fault;

reg exception;

wire exception_fetch_receive;
wire exception_decode;
wire exception_execute;
wire exception_memory_issue;
wire exception_memory_receive;

wire [3:0] exception_code_fetch_receive;
wire [3:0] exception_code_decode;
wire [3:0] exception_code_execute;
wire [3:0] exception_code_memory_issue;
wire [3:0] exception_code_memory_receive;

wire m_ret_decode;
wire s_ret_decode;
wire u_ret_decode;

wire [ADDRESS_BITS-1:0] trap_PC;

wire CSR_read_en;
wire CSR_write_en;
wire CSR_set_en;
wire CSR_clear_en;

wire solo_instr_decode; // generated here
reg  solo_instr_execute;
reg  solo_instr_memory_issue;
reg  solo_instr_memory_receive;
reg  solo_instr_writeback;

// TLB invalidate signals from sfence.vma
wire       tlb_invalidate;
wire [1:0] tlb_invalidate_mode;

// Atomic Control Signals
reg  atomic_memory_receive;
reg  memory_SC_successful;
wire atomic;
wire wb_op_sel;

// Multi-Cycle Execute Unit Control Signals
reg execute_valid_result;

// New Ports
reg [4:0] rs1;
reg [4:0] rs2;
reg [4:0] rd;
reg [4:0] rd_execute;
reg [4:0] rd_memory_issue;
reg [4:0] rd_memory_receive;
reg [4:0] rd_writeback;
reg regWrite_execute;
reg regWrite_memory_issue;
reg regWrite_memory_receive;
reg regWrite_writeback;
reg issue_request;

wire store_memory_issue_allowed;

reg scan;

seven_stage_priv_control_unit #(
  .CORE(CORE),
  .DATA_WIDTH(DATA_WIDTH),
  .ADDRESS_BITS(ADDRESS_BITS),
  .M_EXTENSION(M_EXTENSION),
  .SCAN_CYCLES_MIN(SCAN_CYCLES_MIN),
  .SCAN_CYCLES_MAX(SCAN_CYCLES_MAX)
) DUT (
  .clock(clock),
  .reset(reset),
  .opcode_decode(opcode_decode),
  .opcode_execute(opcode_execute),
  .opcode_memory_issue(opcode_memory_issue),
  .opcode_memory_receive(opcode_memory_receive),
  .funct3(funct3),
  .funct7(funct7),

  .JALR_target_execute(JALR_target_execute),
  .branch_target_execute(branch_target_execute),
  .JAL_target_decode(JAL_target_decode),
  .branch_execute(branch_execute),

  .branch_op(branch_op),
  .memRead(memRead),
  .ALU_operation(ALU_operation),
  .memWrite(memWrite),
  .log2_bytes(log2_bytes),
  .unsigned_load(unsigned_load),
  .next_PC_sel(next_PC_sel),
  .operand_A_sel(operand_A_sel),
  .operand_B_sel(operand_B_sel),
  .extend_sel(extend_sel),
  .regWrite(regWrite),

  .target_PC(target_PC),
  .i_mem_read(i_mem_read),

  // Base Hazard Detection Unit Ports
  .fetch_valid(fetch_valid),
  .fetch_ready(fetch_ready),
  .issue_PC(issue_PC),
  .fetch_address_in(fetch_address_in),
  .memory_valid(memory_valid),
  .memory_ready(memory_ready),

  .load_memory_receive(load_memory_receive), // memRead_memory_receive
  .store_memory_issue(store_memory_issue),
  .store_memory_receive(store_memory_receive), // memWrite_memory_receive
  .load_address_receive(load_address_receive),
  .memory_address_in(memory_address_in),

  // Seven Stage Stall Unit Ports
  .stall_fetch_receive(stall_fetch_receive),
  .stall_decode(stall_decode),
  .stall_execute(stall_execute),
  .stall_memory_issue(stall_memory_issue),
  .stall_memory_receive(stall_memory_receive),

  .flush_fetch_receive(flush_fetch_receive),
  .flush_decode(flush_decode),
  .flush_execute(flush_execute),
  .flush_memory_issue(flush_memory_issue),
  .flush_memory_receive(flush_memory_receive),
  .flush_writeback(flush_writeback),

  // Seven Stage Bypass Unit Ports
  .rs1_data_bypass(rs1_data_bypass),
  .rs2_data_bypass(rs2_data_bypass),

  // CSR & Privilege Control Ports
  .priv(priv),
  .intr_branch(intr_branch),
  .trap_branch(trap_branch),

  .inst_PC_fetch_receive(inst_PC_fetch_receive),
  .inst_PC_decode(inst_PC_decode),
  .inst_PC_execute(inst_PC_execute),
  .inst_PC_memory_issue(inst_PC_memory_issue),
  .inst_PC_memory_receive(inst_PC_memory_receive),

  .m_ret_memory_receive(m_ret_memory_receive),
  .s_ret_memory_receive(s_ret_memory_receive),
  .u_ret_memory_receive(u_ret_memory_receive),

  .i_mem_page_fault(i_mem_page_fault),
  .i_mem_access_fault(i_mem_access_fault),
  .d_mem_page_fault(d_mem_page_fault),
  .d_mem_access_fault(d_mem_access_fault),

  .exception(exception),

  .exception_fetch_receive(exception_fetch_receive),
  .exception_decode(exception_decode),
  .exception_execute(exception_execute),
  .exception_memory_issue(exception_memory_issue),
  .exception_memory_receive(exception_memory_receive),

  .exception_code_fetch_receive(exception_code_fetch_receive),
  .exception_code_decode(exception_code_decode),
  .exception_code_execute(exception_code_execute),
  .exception_code_memory_issue(exception_code_memory_issue),
  .exception_code_memory_receive(exception_code_memory_receive),

  .m_ret_decode(m_ret_decode),
  .s_ret_decode(s_ret_decode),
  .u_ret_decode(u_ret_decode),

  .trap_PC(trap_PC),

  .CSR_read_en(CSR_read_en),
  .CSR_write_en(CSR_write_en),
  .CSR_set_en(CSR_set_en),
  .CSR_clear_en(CSR_clear_en),

  .solo_instr_decode(solo_instr_decode), // generated here
  .solo_instr_execute(solo_instr_execute),
  .solo_instr_memory_issue(solo_instr_memory_issue),
  .solo_instr_memory_receive(solo_instr_memory_receive),
  .solo_instr_writeback(solo_instr_writeback),

  // TLB invalidate signals from sfence.vma
  .tlb_invalidate(tlb_invalidate),
  .tlb_invalidate_mode(tlb_invalidate_mode),

  // Atomic Control Signals
  .atomic_memory_receive(atomic_memory_receive),
  .memory_SC_successful(memory_SC_successful),

  .atomic(atomic),
  .wb_op_sel(wb_op_sel),

  // Multi-Cycle Execute Unit Control Signals
  .execute_valid_result(execute_valid_result),

  // New Ports
  .rs1(rs1),
  .rs2(rs2),
  .rd(rd),
  .rd_execute(rd_execute),
  .rd_memory_issue(rd_memory_issue),
  .rd_memory_receive(rd_memory_receive),
  .rd_writeback(rd_writeback),
  .regWrite_execute(regWrite_execute),
  .regWrite_memory_issue(regWrite_memory_issue),
  .regWrite_memory_receive(regWrite_memory_receive),
  .regWrite_writeback(regWrite_writeback),
  .issue_request(issue_request),

  .store_memory_issue_allowed(store_memory_issue_allowed),

  .scan(scan)
);

always #5 clock = ~clock;

initial begin
  // Base Control Unit Ports
  clock = 1'b1;
  reset = 1'b1;
  opcode_decode = R_TYPE;
  opcode_execute = R_TYPE;
  opcode_memory_issue = R_TYPE;
  opcode_memory_receive = R_TYPE;

  JALR_target_execute   = 4;
  branch_target_execute = 8;
  JAL_target_decode     = 12;
  branch_execute        = 1'b0;

  // Base Hazard Detection Unit Ports
  fetch_valid      = 1'b1;
  fetch_ready      = 1'b1;
  issue_PC         = 0;
  fetch_address_in = 0;
  memory_valid     = 1'b1;
  memory_ready     = 1'b1;
  load_memory_receive = 1'b0;
  store_memory_issue   = 1'b0;
  store_memory_receive = 1'b0;
  load_address_receive = 0;
  memory_address_in = 0;

  // CSR & Privilege Control Ports
  priv = 2'b11;
  intr_branch = 1'b0;
  trap_branch = 1'b0;

  inst_PC_fetch_receive = 0;
  inst_PC_decode = 0;
  inst_PC_execute = 0;
  inst_PC_memory_issue = 0;
  inst_PC_memory_receive = 0;

  m_ret_memory_receive = 1'b0;
  s_ret_memory_receive = 1'b0;
  u_ret_memory_receive = 1'b0;

  solo_instr_execute        = 1'b0;
  solo_instr_memory_issue   = 1'b0;
  solo_instr_memory_receive = 1'b0;
  solo_instr_writeback      = 1'b0;

  i_mem_page_fault   = 1'b0;
  i_mem_access_fault = 1'b0;
  d_mem_page_fault   = 1'b0;
  d_mem_access_fault = 1'b0;

  exception = 1'b0;

  atomic_memory_receive = 1'b0;
  memory_SC_successful  = 1'b0;

  execute_valid_result = 1'b1;

  // New Ports
  opcode_memory_issue = R_TYPE;
  opcode_memory_receive = R_TYPE;
  rs1          = 0;
  rs2          = 0;
  rd           = 0;
  rd_execute   = 0;
  rd_memory_receive = 0;
  rd_memory_issue   = 0;
  rd_writeback = 0;
  regWrite_execute   = 1'b0;
  regWrite_memory_issue   = 1'b0;
  regWrite_memory_receive = 1'b0;
  regWrite_writeback = 1'b0;
  issue_request = 1'b1;

  scan = 1'b0;

  repeat (1) @ (posedge clock);
  reset = 1'b0;

  repeat (1) @ (posedge clock);

  // Execute data hazard
  rs1 = 5'd1;
  rd_execute = 5'd1;
  regWrite_execute = 1'b1;
  opcode_decode  = R_TYPE;
  opcode_execute = LOAD;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b1 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b1 |
      flush_decode         !== 1'b0 |
      flush_execute        !== 1'b1 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected output for true data hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  rs1 = 5'd0;
  rd_execute = 5'd0;
  regWrite_execute = 1'b0;
  opcode_execute = 7'd0;

  // Instruction memory hazard
  fetch_valid = 1'b0;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b1 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b0 |
      flush_decode         !== 1'b1 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected output for instruction memory hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end


  fetch_valid  = 1'b1;
  // Data memory hazard
  memory_ready = 1'b0;
  store_memory_issue = 1'b1;


  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b1 |
      stall_execute        !== 1'b1 |
      stall_memory_issue   !== 1'b1 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b1 |
      flush_decode         !== 1'b0 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b1 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected output for data memory hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  memory_ready = 1'b1;
  load_memory_receive = 1'b0;
  // JALR hazard
  opcode_memory_issue = JALR;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b0 |
      flush_decode         !== 1'b0 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: JALR in memory should not cause a hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  opcode_memory_issue = 7'd0;
  // JALR hazard
  opcode_execute = JALR;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b1 |
      flush_decode         !== 1'b1 |
      flush_execute        !== 1'b1 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected output for JALR/branch hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end


  // JAL hazard
  opcode_execute = JAL;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b0 |
      flush_decode         !== 1'b0 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: JAL in execute should not cause a hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  opcode_execute = 7'd0;
  // JAL hazard
  opcode_decode  = JAL;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b1 |
      flush_decode         !== 1'b1 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected output for JAL hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  opcode_decode  = R_TYPE;
  opcode_execute = R_TYPE;
  // Make sure that JALs in memory do not cause hazards
  opcode_memory_issue = JAL;

  repeat (1) @ (posedge clock);

  if( stall_fetch_receive  !== 1'b0 |
      stall_decode         !== 1'b0 |
      stall_execute        !== 1'b0 |
      stall_memory_issue   !== 1'b0 |
      stall_memory_receive !== 1'b0 |
      flush_fetch_receive  !== 1'b0 |
      flush_decode         !== 1'b0 |
      flush_execute        !== 1'b0 |
      flush_memory_issue   !== 1'b0 |
      flush_memory_receive !== 1'b0 |
      flush_writeback      !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: JALs in memory issue should not cause a hazard!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end


  opcode_execute = 7'd0;
  opcode_memory_issue = 7'd0;
  // Test Bypass output
  rs1 = 5'd0;
  rs2 = 5'd0;
  rd_execute = 5'd0;
  regWrite_execute = 1'b0;
  opcode_execute = 7'd0;

  repeat (1) @ (posedge clock);

  if( rs1_data_bypass !== 3'b000 |
      rs2_data_bypass !== 3'b000 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Bypassing should not be active!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  rs1 = 5'd1;
  rs2 = 5'd0;
  opcode_decode = R_TYPE; // READ RS1
  rd_execute = 5'd1;
  regWrite_execute = 1'b1;
  opcode_execute = I_TYPE;

  repeat (1) @ (posedge clock);

  if( rs1_data_bypass !== 3'b001 |
      rs2_data_bypass !== 3'b000 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Execute data should be forwarded to RS1!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  rd_execute = 5'd0;
  regWrite_execute = 1'b0;
  opcode_execute = 7'd0;

  rs1 = 5'd0;
  rs2 = 5'd1;
  rd_memory_receive = 5'd1;
  regWrite_memory_receive = 1'b1;
  opcode_memory_receive = R_TYPE;

  repeat (1) @ (posedge clock);

  if( rs1_data_bypass !== 3'b000 |
      rs2_data_bypass !== 3'b011 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Memory Receive data should be forwarded to RS2!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  rs1 = 5'd1;
  rs2 = 5'd2;
  rd_memory_issue = 5'd1;
  regWrite_memory_issue = 1'b1;
  rd_writeback = 5'd2;
  regWrite_writeback= 1'b1;
  opcode_memory_issue = R_TYPE;


  repeat (1) @ (posedge clock);

  if( rs1_data_bypass !== 3'b010 |
      rs2_data_bypass !== 3'b100 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Memory Issue  data should be forwarded to RS1 and");
    $display("       writeback data should be forwarded to RS2!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  rs1 = 5'd1;
  rs2 = 5'd2;
  rd_execute = 5'd1;
  regWrite_execute = 1'b1;
  rd_memory_issue = 5'd2;
  regWrite_memory_issue = 1'b1;
  opcode_execute = LOAD;
  opcode_memory_issue = LOAD;

  repeat (1) @ (posedge clock);

  if( rs1_data_bypass !== 3'b000 |
      rs2_data_bypass !== 3'b000 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Bypassing should not be active during true data hazards!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // ECALL
  opcode_decode = SYSTEM;
  rs1          = 0;
  rs2          = 0;
  rd           = 0;
  funct3       = 0;
  funct7       = 0;
  priv         = 2'd0; // USER

  repeat (1) @ (posedge clock);

  if( exception_decode      !== 1'b1 |
      exception_code_decode !== 4'h8 |
      regWrite              !== 1'b0 ) begin

    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during ECALL in user mode!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // MRET
  opcode_decode = SYSTEM;
  rs1          = 0;
  rs2          = 2;
  rd           = 0;
  funct3       = 0;
  funct7       = 7'b0011000;
  priv         = 2'd3; // MACHINE

  repeat (1) @ (posedge clock);
  #1
  if( m_ret_decode !== 1'b1 |
      regWrite     !== 1'b0 ) begin

    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during MRET !");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // Valid CSRRW
  opcode_decode = SYSTEM;
  rs1          = 1;
  rs2          = 0;
  rd           = 1;
  funct3       = 1;
  funct7       = 7'b0011000;
  priv         = 2'd3; // MACHINE

  repeat (1) @ (posedge clock);
  #1
  if( CSR_read_en  !== 1'b1 |
      CSR_write_en !== 1'b1 |
      CSR_set_en   !== 1'b0 |
      CSR_clear_en !== 1'b0 |
      regWrite     !== 1'b1 ) begin

    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during valid CSRRW!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // Illegal CSRRW
  priv         = 2'd1; // SUPERVISOR

  repeat (1) @ (posedge clock);
  #1
  if( CSR_read_en  !== 1'b0 |
      CSR_write_en !== 1'b0 |
      CSR_set_en   !== 1'b0 |
      CSR_clear_en !== 1'b0 |
      regWrite     !== 1'b0 ) begin

    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during illegal CSRRW!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // Load Reserve
  opcode_decode = AMO;
  rs1          = 0;
  rs2          = 0;
  rd           = 0;
  funct3       = 3'b010;
  funct7       = 7'b0001000;
  priv         = 2'd3; // MACHINE

  repeat (1) @ (posedge clock);
  #1
  if( branch_op     !== 1'b0 |
      memRead       !== 1'b1 |
      ALU_operation !== 6'd1 |
      memWrite      !== 1'b0 |
      log2_bytes    !== 2'd2 |
      unsigned_load !== 1'b0 |
      next_PC_sel   !== 2'd0 |
      operand_A_sel !== 2'd0 |
      operand_B_sel !== 1'b0 |
      extend_sel    !== 2'd0 |
      regWrite      !== 1'b1 |
      atomic        !== 1'b1 |
      DUT.is_emulated_instruction !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during Load Reserve!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // AMOADD.w
  opcode_decode = AMO;
  rs1          = 0;
  rs2          = 0;
  rd           = 0;
  funct3       = 3'b010;
  funct7       = 7'b0000000;
  priv         = 2'd3; // MACHINE

  repeat (1) @ (posedge clock);
  #1
  if( branch_op     !== 1'b0 |
      memRead       !== 1'b0 |
      ALU_operation !== 6'd1 |
      memWrite      !== 1'b0 |
      log2_bytes    !== 2'd2 |
      unsigned_load !== 1'b0 |
      next_PC_sel   !== 2'd0 |
      operand_A_sel !== 2'd0 |
      operand_B_sel !== 1'b0 |
      extend_sel    !== 2'd0 |
      regWrite      !== 1'b1 |
      atomic        !== 1'b0 |
      DUT.is_emulated_instruction !== 1'b1 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during AMOADD.w!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  // MUL
  opcode_decode = R_TYPE;
  rs1          = 0;
  rs2          = 0;
  rd           = 0;
  funct3       = 3'b000;
  funct7       = 7'b0000001;

  repeat (1) @ (posedge clock);
  #1
  if( branch_op     !== 1'b0 |
      memRead       !== 1'b0 |
      ALU_operation !== 6'd20 |
      memWrite      !== 1'b0 |
      log2_bytes    !== 2'd0 |
      unsigned_load !== 1'b0 |
      next_PC_sel   !== 2'd0 |
      operand_A_sel !== 2'd0 |
      operand_B_sel !== 1'b0 |
      extend_sel    !== 2'd0 |
      regWrite      !== 1'b1 |
      atomic        !== 1'b0 |
      DUT.is_emulated_instruction !== 1'b0 ) begin
    scan = 1'b1;
    repeat (1) @ (posedge clock);
    $display("\nError: Unexpected control signals during MUL!");
    $display("\ntb_seven_stage_priv_control_unit --> Test Failed!\n\n");
    $stop();
  end

  repeat (1) @ (posedge clock);
  $display("\ntb_seven_stage_priv_control_unit --> Test Passed!\n\n");
  $stop();


end

endmodule
