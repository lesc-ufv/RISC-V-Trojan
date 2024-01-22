/** @module : tb_fetch_issue_ooo
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

module tb_fetch_issue_ooo;

parameter XLEN       = 64;
parameter NLP_UPDATE = 71;

reg clock;
reg reset;
// Fetch request port
reg                  fetch_request_ready;
wire                 fetch_request_valid;
wire [XLEN-1:0]      fetch_request_PC;
// Fetch request to fetch receive port
wire                 fetch_issue_valid;        // High if FI wants to send out a request to I-cache
reg                  fetch_issue_ready;        // High if FR has slots to accept a new PC
wire [XLEN-1:0]      fetch_issue_PC;           // PC of the I-cache request
wire                 fetch_issue_NLP_BTB_hit;  // high if valid entry already found in BTB
// PC update port
reg                  fetch_update_valid;
wire                 fetch_update_ready;
reg [NLP_UPDATE-1:0] fetch_update_data;

fetch_issue_ooo #(
    .XLEN(XLEN),
    .NLP_UPDATE(NLP_UPDATE)
) DUT (
    .clock(clock),
    .reset(reset),
    // Fetch request port
    .fetch_request_ready(fetch_request_ready),
    .fetch_request_valid(fetch_request_valid),
    .fetch_request_PC(fetch_request_PC),
    // Fetch request to fetch receive port
    .fetch_issue_valid(fetch_issue_valid),        // High if FI wants to send out a request to I-cache
    .fetch_issue_ready(fetch_issue_ready),        // High if FR has slots to accept a new PC
    .fetch_issue_PC(fetch_issue_PC),           // PC of the I-cache request
    .fetch_issue_NLP_BTB_hit(fetch_issue_NLP_BTB_hit),  // high if valid entry already found in BTB
    // PC update port
    .fetch_update_valid(fetch_update_valid),
    .fetch_update_ready(fetch_update_ready),
    .fetch_update_data(fetch_update_data)
);

  always #5 clock = ~clock;

initial begin

  clock = 1'b1;
  reset = 1'b1;

  fetch_request_ready = 1'b1;
  fetch_issue_ready = 1'b1;
  fetch_update_valid = 1'b0;
  fetch_update_data = 0;

  repeat (1) @ (posedge clock);
  reset = 1'b0;

  repeat (1) @ (posedge clock);

  if(fetch_request_valid !== 1'b1 |
     fetch_request_PC    !== 32'd0 ) begin
    $display("Test 1: fetch_request_valid: %b, fetch_request_PC: %h", fetch_request_valid, fetch_request_PC);
    $display("\ntb_fetch_issue_ooo --> Test Failed!\n\n");
    $stop;
  end

  repeat (1) @ (posedge clock);

  if(fetch_request_valid !== 1'b1 |
     fetch_request_PC    !== 32'd4 ) begin
    $display("Test 2: fetch_request_valid: %b, fetch_request_PC: %h", fetch_request_valid, fetch_request_PC);
    $display("\ntb_fetch_issue_ooo --> Test Failed!\n\n");
    $stop;
  end

  repeat (4) @ (posedge clock);
  fetch_update_valid = 1;
  fetch_update_data  = 100;

  repeat (1) @ (posedge clock);
  fetch_update_valid = 0;

  repeat (1) @ (posedge clock);
  $display("\ntb_fetch_issue_ooo --> Test Passed!\n\n");
  $stop;
end

endmodule
