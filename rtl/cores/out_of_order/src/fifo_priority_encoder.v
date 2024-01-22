/** @module : fifo_priority_encoder
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
 * For a FIFO of 1 << ADDR_WIDTH elements where the valid elements are in the range
 * [head, tail-1], and a set of wires, with one wire per element, selects either the
 * closest-to-head active wire, or closest-to-tail active wire, depending on the
 * module parameter.
 *
 * The main difficulty comes when the active set [head, tail-1] is broken over the
 * end of the FIFO. Here is an illustration of such a case:
 *
 * Idx 0   1   2   3   4   5   6   7
 *
 *        tail            head
 *    -->  |               |  -->  -->
 *   ______V_______________V__________
 *   |   |   |   |   |   |   |   |   |
 *   | 1 | X | X | X | X | 0 | 1 | 1 |
 *   |___|___|___|___|___|___|___|___|
 *     A                       A
 *     |                       |
 *     |                 find this one
 * not this one
*
* Masks:
*
*   up to tail mask:
*             t           h
*   __________V___________V__________
*   |   |   |   |   |   |   |   |   |
*   | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
*   |___|___|___|___|___|___|___|___|
*
*   head and up mask:
*             t           h
*   __________V___________V__________
*   |   |   |   |   |   |   |   |   |
*   | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
*   |___|___|___|___|___|___|___|___|
*
*   between mask:
*             h           t
*   __________V___________V__________
*   |   |   |   |   |   |   |   |   |
*   | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 0 |
*   |___|___|___|___|___|___|___|___|
 *
 *
 * Decision tree for the "head" configuration:
 *
 * head before tail? –––––––––––––––––
 *   (~inverted)       no            |
 *       |                           |
 *       | yes                       |
 *       V                           V
 * only listen to               main priority       no
 * main priority             encoder found match? ––––––––––––––––––
 *    encoder                        |                             |
 *                                   | yes                         |
 *                                   V                             V
 *                           take main result              take side result
 *
 *
 *
 * In the case we are searching for the signal closest to the tail, the tree should be:
 *
 * head before tail? ────────────────┐
 *   (~inverted)       no            │
 *       │                           │
 *       │ yes                       │
 *       V                           V
 * only listen to               side priority       no
 * main priority             encoder found match? ─────────────────┐
 *    encoder                        │                             │
 *                                   │ yes                         │
 *                                   V                             V
 *                           take side result              take main result
*
 */

module fifo_priority_encoder #(
    parameter ADDR_WIDTH = 5,
              CLOSEST_TO = "head",
    parameter SLOTS = 1 << ADDR_WIDTH
) (
    input  [SLOTS     -1:0] inputs,  // Set of wires we are searching through
    input  [ADDR_WIDTH-1:0] head,    // Head pointer, everything after  this up to tail should be searched
    input  [ADDR_WIDTH-1:0] tail,    // Tail pointer, everything before this up to head should be searched
    output                  valid,   // High if found a match
    output [ADDR_WIDTH-1:0] index    // Index of the match
);

    wire                  main_valid, part_valid;
    wire [ADDR_WIDTH-1:0] main_index, part_index;
    wire [SLOTS-1     :0] up_to_tail_mask  = ((1 << tail) - 1);                  // All wires up to tail, not including tail
    wire [SLOTS-1     :0] head_and_up_mask = {SLOTS{1'b1}} & ~((1 << head) - 1); // All wires including and after the head should be high
    wire [SLOTS-1     :0] between_mask     = head_and_up_mask & up_to_tail_mask; // All wires between head and tail
    wire                  inverted         = head > tail;                        // when the head is after the tail, the situation is complex

    wire [SLOTS-1:0] main_mask = ~inverted ? between_mask : head_and_up_mask;
    wire [SLOTS-1:0] part_mask = up_to_tail_mask;


    priority_encoder #(
        .WIDTH   (SLOTS                               ),
        .PRIORITY(CLOSEST_TO == "head" ? "LSB" : "MSB")
    ) main_PE (
        .decode(inputs & main_mask),
        .encode(main_index        ),
        .valid (main_valid        )
    );


    priority_encoder #(
        .WIDTH   (SLOTS                               ),
        .PRIORITY(CLOSEST_TO == "head" ? "LSB" : "MSB")
    ) part_PE (
        .decode(inputs & part_mask),
        .encode(part_index        ),
        .valid (part_valid        )
    );


    assign valid = ~inverted ? main_valid
                             : main_valid || part_valid;
    assign index = CLOSEST_TO == "head" ? ~inverted ? main_index               // head < tail
                                                    : main_valid ? main_index  // head > tail && match found in the right part
                                                                 : part_index  // head > tail && match found only in left part
                                        : ~inverted ? main_index               // head < tail
                                                    : part_valid ? part_index  // head > tail && match found in left part
                                                                 : main_index; // head > tail && match found only in right

endmodule
