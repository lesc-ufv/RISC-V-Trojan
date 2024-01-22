/** @module : tb_reservation_station
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

module tb_reservation_station();

    parameter XLEN                    = 64;  // Register value size
    parameter RS_SLOTS_INDEX_WIDTH    = 3;   // log2(Number of RS slots)
    parameter FORWARD_BUSSES          = 2;   // Just use ROB for now
    parameter ROB_INDEX_WIDTH         = 8;   // Number of ROB address bits
    parameter DECODED_INSTR_WIDTH     = 32;  // Size of the decoded instruction - probably should be smaller than 32 since

    reg clock;
    reg reset;

    // Issue port
    wire                          issue_ready;               // high if all $SLOTS slots are full
    reg                           issue_valid;               // if high, RS adds an instruction, ROB index, and register info to the FIFO
    reg [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction; // decoded instruction. RS should not care about it's internals
    reg [ROB_INDEX_WIDTH-1:0]     issue_rd_ROB_index;        // index in the ROB where the result of this instructions should be stored
    // First register / ROB
    reg [XLEN-1:0]                issue_rs1_data_or_ROB;     // The value of the first register or ROB if renamed
    reg                           issue_rs1_is_renamed;      // High if ROB index is set
    // Second register / ROB
    reg [XLEN-1:0]                issue_rs2_data_or_ROB;     // The value of the second register or ROB if renamed
    reg                           issue_rs2_is_renamed;      // High if ROB index is set
    reg [XLEN-1:0]                issue_address;             // Input address
`ifdef TEST
    reg [XLEN               -1:0] issue_PC_i;
`endif
    // Forwards ports: consists of n execution lane ports and one ROB port.
    // ROB forward port: in order not to read ROB from regfile and read line from ROB in the same cycle,
    // at the same time an instruction is moved from instruction queue to the reservation station, the ROB
    // is asynchronously queried if the (valid) ROB indexes of the instruction's input registers are done yet.
    // If so, the ROB will broadcast these values on a bus of it's own.
    // Ideally, there should be  2 * #_of_issues such busses so no instructions have to stall.
    reg [FORWARD_BUSSES                -1:0] forward_valids;  // valid flag of all forward ports
    reg [FORWARD_BUSSES*ROB_INDEX_WIDTH-1:0] forward_indexes; // forward port index lines
    reg [FORWARD_BUSSES*XLEN           -1:0] forward_values;  // forward port register lines

    // Dispatch port: when a slot is occupied and has both Qj and Qk values, sends out the decoded instruction,
    // ROB destination, and the operands
    reg                            dispatch_ready;
    wire                           dispatch_valid;
    wire [XLEN-1:0]                dispatch_1st_reg;
    wire [XLEN-1:0]                dispatch_2nd_reg;
    wire [XLEN-1:0]                dispatch_address;
    wire [DECODED_INSTR_WIDTH-1:0] dispatch_decoded_instruction;
    wire [ROB_INDEX_WIDTH-1:0]     dispatch_ROB_destination;

`ifdef TEST
    wire [XLEN               -1:0] dispatch_PC_o;
`endif

    reg flush;


    reservation_station #(
        .XLEN                   (XLEN                ),
        .RS_SLOTS_INDEX_WIDTH   (RS_SLOTS_INDEX_WIDTH),
        .FORWARD_BUSSES         (FORWARD_BUSSES      ),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH     ),
        .DECODED_INSTR_WIDTH    (DECODED_INSTR_WIDTH )
    ) DUT (
        .clock_i                     (clock                       ),
        .reset_i                     (reset                       ),
        .issue_ready_o               (issue_ready                 ),
        .issue_valid_i               (issue_valid                 ),
        .issue_decoded_instruction_i (issue_decoded_instruction   ),
        .issue_rd_ROB_index_i        (issue_rd_ROB_index          ),
        .issue_rs1_data_or_ROB_i     (issue_rs1_data_or_ROB       ),
        .issue_rs1_is_renamed_i      (issue_rs1_is_renamed        ),
        .issue_rs2_data_or_ROB_i     (issue_rs2_data_or_ROB       ),
        .issue_rs2_is_renamed_i      (issue_rs2_is_renamed        ),
        .issue_address_i             (issue_address               ),
`ifdef TEST
        .issue_PC_i                  (issue_PC_i                  ),
`endif
        .forward_valids_i            (forward_valids              ),
        .forward_indexes_i           (forward_indexes             ),
        .forward_values_i            (forward_values              ),
        .dispatch_ready_i            (dispatch_ready              ),
        .dispatch_valid_o            (dispatch_valid              ),
        .dispatch_1st_reg_o          (dispatch_1st_reg            ),
        .dispatch_2nd_reg_o          (dispatch_2nd_reg            ),
        .dispatch_address_o          (dispatch_address            ),
        .dispatch_decoded_instruction_o(dispatch_decoded_instruction),
        .dispatch_ROB_destination_o    (dispatch_ROB_destination    ),
`ifdef TEST
        .dispatch_PC_o                 (dispatch_PC_o               ),
`endif
        .flush_i                       (flush                       )
    );


always #1
    clock <= ~clock;

integer idx;

initial begin

  clock <= 0;
  reset <= 0;
  flush <= 0;

  issue_valid               <= 0;
  issue_decoded_instruction <= 32'h89abcdef;
  issue_rd_ROB_index        <= 0;
  issue_rs1_data_or_ROB     <= 0;
  issue_rs1_is_renamed      <= 0;
  issue_rs2_data_or_ROB     <= 0;
  issue_rs2_is_renamed      <= 0;
  issue_address             <= 0;
  forward_valids            <= 0;
  forward_indexes           <= 0;
  forward_values            <= 0;
  dispatch_ready            <= 0;


  # 10 reset <= 1;
  # 10 reset <= 0;

  if(issue_ready    !== 1'b1 |
     dispatch_valid !== 1'b0 |
     flush          !== 1'b0 ) begin
    $display("\ntb_reservation_station --> Test Failed!\n\n");
    $stop;
  end

  # 10 // First, let's say that the execution lane never accepts instructions
  dispatch_ready <= 0;

  // Now, lets insert some instructions
  #2 // First instruction has 2 renamed registers
  issue_valid           <= 1;
  issue_rd_ROB_index    <= 1;
  issue_rs1_data_or_ROB <= 3;  // Waiting for ROB 3
  issue_rs1_is_renamed  <= 1;
  issue_rs2_data_or_ROB <= 4;  // Waiting for ROB 4
  issue_rs2_is_renamed  <= 1;

  #2 // Second instruction has 1 renamed register
  issue_valid           <= 1;
  issue_rd_ROB_index    <= 2;
  issue_rs1_data_or_ROB <= 5;  // Waiting for ROB 5
  issue_rs1_is_renamed  <= 1;
  issue_rs2_data_or_ROB <= 22;
  issue_rs2_is_renamed  <= 0;

  #2 // Third instruction has no renamed registers
  issue_valid           <= 1;
  issue_rd_ROB_index    <= 3;
  issue_rs1_data_or_ROB <= 31;
  issue_rs1_is_renamed  <= 0;
  issue_rs2_data_or_ROB <= 32;
  issue_rs2_is_renamed  <= 0;

  #2 issue_valid    <= 0;

  # 10 // Dispatch opens
  dispatch_ready <= 1;

  #20 // Now, lets update some values

  // First, let's update some garbage ROB indexes
  forward_valids  <= 1;  // Forwarding ROB 6
  forward_indexes <= 6;
  #2
  forward_valids  <= 1;  // Forwarding ROB 7
  forward_indexes <= 7;
  #2
  forward_valids  <= 1;  // Forwarding ROB 8
  forward_indexes <= 8;

  // Next, let's update second instruction's Qj is 5
  forward_valids  <= 1;  // Forwarding ROB 5
  forward_indexes <= 5;
  forward_values  <= 21;

  #2 forward_valids <= 0;

  #10 // wait a bit, see if anything comes out?
      // We should see operands 21 and 22.

  // Now let's update first instruction's registers
  forward_valids  <= 1;
  forward_indexes <= 3;  // Forwarding ROB 5
  forward_values  <= 11;

  #2
  forward_valids  <= 1;
  forward_indexes <= 4;  // Forwarding ROB 5
  forward_values  <= 12;

  #2 forward_valids <= 0;
      // We should see operands 11 and 12.

  repeat (1) @ (posedge clock);
  $display("\ntb_reservation_station --> Test Passed!\n\n");
  $stop;
end



always @ (posedge clock)  begin
  if (issue_valid && issue_ready)
    $display("Issued instruction %d at %d", issue_rd_ROB_index, $time);

  if (dispatch_valid && dispatch_ready)
    $display("Dispatched instruction %d at %d", dispatch_ROB_destination, $time);
end


endmodule
