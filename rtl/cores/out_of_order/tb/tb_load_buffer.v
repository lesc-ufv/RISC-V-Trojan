/** @module : tb_load_buffer
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

/*
 * This testbench should test several things:
 * 1. that the tail cannot overwrite uncommitted instructions
 * 2. that the responses always find the correct ROB
 * 3. that only committing load instructions frees up the slots
 *
 */
module tb_load_buffer;

    localparam REG_DATA_WIDTH  = 32;
    localparam REG_ADDR_WIDTH  = 32;
    localparam ROB_INDEX_WIDTH = 8;
    localparam LB_INDEX_WIDTH  = 3;
    localparam DECODED_INSTR_WIDTH = 6;

    reg                        clock;
    reg                        reset;
    reg                        flush;
    wire                       issue_ready;
    reg                        issue_valid;
    reg [ROB_INDEX_WIDTH-1 :0] issue_ROB_index;
    reg [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction;
    wire                       address_receive_ready;
    reg                        address_receive_valid;
    reg [ROB_INDEX_WIDTH-1 :0] address_receive_ROB_index;
    reg [REG_ADDR_WIDTH-1  :0] address_receive_address;
    reg                        load_request_ready;
    wire                       load_request_valid;
    wire [REG_ADDR_WIDTH-1 :0] load_request_address;
    wire                       load_response_ready;
    reg                        load_response_valid;
    reg [REG_DATA_WIDTH-1  :0] load_response_value;
    reg [REG_ADDR_WIDTH-1  :0] load_response_address;
    reg                        ROB_accept_ready;
    wire                       ROB_accept_valid;
    wire [REG_DATA_WIDTH-1:0]  ROB_accept_value;
    wire [ROB_INDEX_WIDTH-1:0] ROB_accept_ROB_index;
    wire                       commit_ready;
    reg                        commit_valid;
    reg [ROB_INDEX_WIDTH-1 :0] commit_ROB_index;
    reg                        store_commit_valid;
    reg [REG_ADDR_WIDTH-1  :0] store_commit_address;
    wire                       store_commit_hazard;


    load_buffer #(
        .XLEN           (REG_ADDR_WIDTH ),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .LB_INDEX_WIDTH (LB_INDEX_WIDTH ),
        .DECODED_INSTR_WIDTH(DECODED_INSTR_WIDTH)
    ) DUT (
        .clock                    (clock                    ),
        .reset                    (reset                    ),
        .flush                    (flush                    ),
        .issue_ready              (issue_ready              ),
        .issue_valid              (issue_valid              ),
        .issue_ROB_index          (issue_ROB_index          ),
        .address_receive_ready    (address_receive_ready    ),
        .address_receive_valid    (address_receive_valid    ),
        .address_receive_ROB_index(address_receive_ROB_index),
        .issue_decoded_instruction(issue_decoded_instruction),
        .address_receive_address  (address_receive_address  ),
        .load_request_ready       (load_request_ready       ),
        .load_request_valid       (load_request_valid       ),
        .load_request_address     (load_request_address     ),
        .load_response_ready      (load_response_ready      ),
        .load_response_valid      (load_response_valid      ),
        .load_response_value      (load_response_value      ),
        .load_response_address    (load_response_address    ),
        .ROB_accept_ready         (ROB_accept_ready         ),
        .ROB_accept_valid         (ROB_accept_valid         ),
        .ROB_accept_value         (ROB_accept_value         ),
        .ROB_accept_ROB_index     (ROB_accept_ROB_index     ),
        .commit_ready             (commit_ready             ),
        .commit_valid             (commit_valid             ),
        .commit_ROB_index         (commit_ROB_index         ),
        .store_commit_valid       (store_commit_valid       ),
        .store_commit_address     (store_commit_address     ),
        .store_commit_hazard      (store_commit_hazard      )
    );

integer idx;

always #1 clock = ~clock;

initial begin

  clock                     <= 0;
  reset                     <= 1;
  flush                     <= 0;

  issue_valid               <= 0;
  issue_ROB_index           <= 0;
  issue_decoded_instruction <= 0;

  address_receive_valid     <= 0;
  address_receive_ROB_index <= 0;
  address_receive_address   <= 0;

  load_request_ready        <= 1;

  load_response_valid       <= 0;
  load_response_value       <= 0;
  load_response_address     <= 0;

  ROB_accept_ready          <= 1;

  commit_valid              <= 0;
  commit_ROB_index          <= 0;

  store_commit_valid        <= 0;
  store_commit_address      <= 0;

  #10 reset <= 0;

  repeat (1) @ (posedge clock);

  if(issue_ready !== 1'b1 |
     address_receive_ready !== 1'b1 |
     load_request_valid    !== 1'b0 |
     load_response_ready   !== 1'b1 |
     ROB_accept_valid      !== 1'b0 |
     store_commit_hazard   !== 1'b0 ) begin
    $display("\ntb_load_buffer --> Test Failed!\n\n");
    $stop;
  end



  /* Here's a table of the loads we will test, in order of dispatch
   * _____________________________________________
   * |load index          |  0  |  1  |  2  |  3  |
   * |____________________|_____|_____|_____|_____|
   * |address             | 501 | 503 | 507 | 501 |
   * |____________________|_____|_____|_____|_____|
   * |value               |  8  | 13  | 21  | 34  |
   * |____________________|_____|_____|_____|_____|
   * |ROB_index           | 101 | 102 | 106 | 108 |
   * |____________________|_____|_____|_____|_____|
   * |response order      |  2  |  1  |  x  |  3  |
   * |____________________|_____|_____|_____|_____|
   *
   * Note that we purposely make sure to test whether responses are matched with the right ROBs
   */
  #10
  issue_valid     <= 1;
  issue_ROB_index <= 101;
  #2
  issue_valid     <= 0;

  #4
  issue_valid     <= 1;
  issue_ROB_index <= 102;
  #2
  issue_valid     <= 0;

  #6
  issue_valid     <= 1;
  issue_ROB_index <= 106;

  #2
  issue_valid     <= 1;
  issue_ROB_index <= 108;
  #2
  issue_valid     <= 0;

  /*
   * Second, let's dispatch a couple of instructions, some with the same address
   */
  #6
  address_receive_valid     <= 1;
  address_receive_ROB_index <= 106;
  address_receive_address   <= 507;
  #2 address_receive_valid  <= 0;

  #8
  address_receive_valid     <= 1;
  address_receive_ROB_index <= 102;
  address_receive_address   <= 503;
  #2 address_receive_valid  <= 0;

  #6
  address_receive_valid     <= 1;
  address_receive_ROB_index <= 108;
  address_receive_address   <= 501;
  #2 address_receive_valid  <= 0;

  #20
  address_receive_valid     <= 1;
  address_receive_ROB_index <= 101;
  address_receive_address   <= 501;
  #2 address_receive_valid  <= 0;


  /*
   * Next, let's start receiveing loads from memory
   *
   * We will return responses out of order:
   * Order sent in:   1,   0,   3
   * Order returned:  0,   3,   1
   * Orig. addresses: 501, 501, 503
   */
  #20  // Expect response ROB to be 102
  load_response_valid    <= 1;
  load_response_address  <= 503;
  load_response_value    <= 13;
  #2 load_response_valid <= 0;

  #20  // Expect response ROB to be 102
  load_response_valid    <= 1;
  load_response_address  <= 507;
  load_response_value    <= 21;
  #2 load_response_valid <= 0;

  #6 // Expect response ROB to be 101
  load_response_valid    <= 1;
  load_response_address  <= 501;
  load_response_value    <= 8;
  #2 load_response_valid <= 0;

  #8 // Expect response ROB to be 108
  load_response_valid    <= 1;
  load_response_address  <= 501;
  load_response_value    <= 34;
  #2 load_response_valid <= 0;

  /*
   * Next, let's commit some instructions
   * ROB_index:   101, 102, 106, 108
   */
  #20
     commit_valid     <= 1;
     commit_ROB_index <= 101;
  #4 commit_ROB_index <= 102;

  // Let's cause a hazard
  #20
  store_commit_address     <= 501;
  store_commit_valid       <= 1;


  #4 commit_valid     <= 1;
  #10
     commit_ROB_index <= 106;
  #4 commit_ROB_index <= 108;

  repeat (1) @ (posedge clock);
  $display("\ntb_load_buffer --> Test Passed!\n\n");
  $stop;
end

endmodule
