/** @module : tb_store_buffer
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


module tb_store_buffer;


    localparam SB_INDEX_WIDTH  = 3,
               ROB_INDEX_WIDTH = 10,
               XLEN  = 32,
               DECODED_INSTR_WIDTH = 6;

    reg                        clock;
    reg                        reset;
    reg                        flush;
    // Issue queue port
    wire                       issue_SB_ready;         // SB ready to receive
    reg                        issue_SB_valid;         // IQ issuing a store
    reg  [XLEN               -1:0] issue_SB_PC;               // PC of the store
    reg  [DECODED_INSTR_WIDTH-1:0] issue_decoded_instruction; // Bottom 2 bits determine whether a store is SD, SW, SH or SB
    wire [SB_INDEX_WIDTH-1 :0] issue_SB_tail;          // SB tail
    reg  [ROB_INDEX_WIDTH-1:0] ROB_tail;               // Current ROB tail. When ROB head > store ROB; it is safe to commit a store to memory
    // Store execute port
    reg                        execute_valid;          // Store execute valid
    wire                       execute_ready;          // Ready for a new store
    reg  [SB_INDEX_WIDTH-1 :0] execute_SB_tail;        // SB tail
    reg  [XLEN-1 :0] execute_value;          // Value to be stored
    reg  [XLEN-1 :0] execute_address;        // Address where to store the value
    // ROB commit port
    reg                             store_commit_valid;   // The instruction at the head of the ROB is a store
    wire                            store_commit_ready;   // Ready to mark head as commitable
    wire   [XLEN              -1:0] store_commit_address; // Address of the store being committed
    // Commit / Memory port
    reg  [ROB_INDEX_WIDTH-1:0] ROB_head;               // Current head of the ROB
    reg                        store_request_ready;    // High if the memory is ready to accept a store
    wire                       store_request_valid;    // High if the store request is valid
    wire [XLEN-1 :0] store_request_address;  // Address to which we are storing
    wire [XLEN-1 :0] store_request_value;    // Value being stored
    wire [XLEN/8-1:0] store_request_byte_en; // Specifies which bytes should be written

    store_buffer #(
        .SB_INDEX_WIDTH(SB_INDEX_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .XLEN(XLEN),
        .DECODED_INSTR_WIDTH(DECODED_INSTR_WIDTH)
    ) DUT (
        .clock                (clock                ),
        .reset                (reset                ),
        .flush                (flush                ),
        .issue_SB_ready       (issue_SB_ready       ),
        .issue_SB_valid       (issue_SB_valid       ),
        .issue_SB_PC          (issue_SB_PC          ),
        .issue_decoded_instruction(issue_decoded_instruction),
        .issue_SB_tail        (issue_SB_tail        ),
        //.ROB_tail             (ROB_tail             ),
        .execute_valid        (execute_valid        ),
        .execute_ready        (execute_ready        ),
        .execute_SB_tail      (execute_SB_tail      ),
        .execute_value        (execute_value        ),
        .execute_address      (execute_address      ),
        // ROB commit port
        .store_commit_valid(store_commit_valid),        // The instruction at the head of the ROB is a store
        .store_commit_ready(store_commit_ready),        // Ready to mark head as commitable
        .store_commit_address(store_commit_address),      // Address of the store being committed

        .ROB_head             (ROB_head             ),
        .store_request_ready  (store_request_ready  ),
        .store_request_valid  (store_request_valid  ),
        .store_request_address(store_request_address),
        .store_request_value  (store_request_value  ),
        .store_request_byte_en(store_request_byte_en)
    );


always #1 clock = ~clock;


integer idx;

initial begin
  clock               <= 1;

  reset               <= 1;
  issue_SB_valid      <= 0;
  execute_valid       <= 0;
  store_request_ready <= 0;
  ROB_head            <= 0;
  flush               <= 0;
  // Not really needed, but let's clean up the waveform
  execute_SB_tail     <= 0;
  execute_address     <= 0;
  execute_value       <= 0;

  issue_SB_PC         <= 0;
  issue_decoded_instruction <= 0;
  store_commit_valid  <= 1'b0;

  #10 reset <= 0;

  repeat (1) @ (posedge clock);

  if(issue_SB_ready !== 1'b1 |
     execute_ready  !== 1'b1 |
     store_request_valid !== 1'b0 ) begin
    $display("\ntb_store_buffer --> Test Failed!\n\n");
    $stop;
  end

  #10 // Issue a couple of stores with ROBs: [101, 102, 105, 108]
  issue_SB_valid <= 1;
  ROB_tail       <= 101;
  #2
  issue_SB_valid <= 1;
  ROB_tail       <= 102;
  #2
  issue_SB_valid <= 0;
  #6
  issue_SB_valid <= 1;
  ROB_tail       <= 105;
  #2
  issue_SB_valid <= 0;
  #6
  issue_SB_valid <= 1;
  ROB_tail       <= 108;
  #2
  issue_SB_valid <= 0;
  ROB_tail       <= 120;


  #20 // Let's execute all stores except the third one
  execute_valid   <= 1;
  execute_SB_tail <= 0;
  execute_value   <= 1001;
  execute_address <= 10001;
  #2
  execute_valid   <= 0;
  #10
  execute_valid   <= 1;
  execute_SB_tail <= 3;
  execute_value   <= 1004;
  execute_address <= 10004;
  #2
  execute_valid   <= 1;
  execute_SB_tail <= 1;
  execute_value   <= 1002;
  execute_address <= 10002;
  #2
  execute_valid   <= 0;

  #30 // let's move the ROB head up by one, wait, then move it all the way up
  store_request_ready <= 1;
  ROB_head            <= 0;

  #10
  ROB_head            <= 102;
  #10
  ROB_head            <= 110;


  #20 // let's finally execute the third store
  execute_valid   <= 1;
  execute_SB_tail <= 2;
  execute_value   <= 1003;
  execute_address <= 10003;
  #2
  execute_valid   <= 0;

  repeat (1) @ (posedge clock);
  $display("\ntb_store_buffer --> Test Passed!\n\n");
  $stop;
end



endmodule
