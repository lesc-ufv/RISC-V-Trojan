function is_compressed (input [15:0] C);
    is_compressed = C[1:0] != 2'b11;
endfunction

/*
 * Takes a 16-bit compressed instruction and returns a 32bit I / F instruction
 *
 * TODO: go through and make sure to check whether any of these are RV32-specific, and remove them
 * TODO: fix C.LDSP on RV64
 * TODO: fix C.SDSP on RV64
 * TODO: make sure that the hints are ignored
 * TODO: find a way to systematically test all the 16-32bit translations
 *
 */
function [31:0] c2i (input [15:0] C); 
    case ({C[1:0], C[15:13]})
        // Quadrant 0
        5'b00000: c2i = {2'b0, C[10:7], C[12:11], C[5], C[6], 2'b00, 5'h02, 3'b0, 2'b01, C[4:2], 7'b0010011};         // c.addi4spn -> addi rd', x2, imm
        5'b00001: c2i = {4'b0, C[6:5], C[12:10], 3'b000, 2'b01, C[9:7], 3'b011, 2'b01, C[4:2], 7'b0000111};           // c.fld -> fld rd', offset(rs1')
        5'b00010: c2i = {5'b0, C[5], C[12:10], C[6], 2'b0, 2'b01, C[9:7], 3'b010, 2'b01, C[4:2], 7'b0000011};         // c.lw -> lw rd',  offset(rs1')
        5'b00011: c2i = {5'b0, C[5], C[12:10], C[6], 2'b0, 2'b01, C[9:7], 3'b010, 2'b01, C[4:2], 7'b0000111};         // c.flw -> flw rd',  offset(rs1')
        5'b00011: c2i = {4'b0, C[6:5], C[12:10], 3'b0, 2'b01, C[9:7], 3'b011, 2'b01, C[4:2], 7'b0000011};             // c.ld -> ld rd',  offset(rs1')
        5'b00101: c2i = {4'b0, C[6:5], C[12], 2'b01, C[4:2], 2'b01, C[9:7], 3'b011, C[11:10], 3'b0, 7'b0100111};      // c.fsd -> fsd rs2',  offset(rs1')
        5'b00110: c2i = {5'b0, C[5], C[12], 2'b01, C[4:2], 2'b01, C[9:7], 3'b010, C[11:10], C[6], 2'b0, 7'b0100011};  // c.sw -> sw rs2',  offset(rs1')
        5'b00111: c2i = {5'b0, C[5], C[12], 2'b01, C[4:2], 2'b01, C[9:7], 3'b010, C[11:10], C[6], 2'b0, 7'b0100111};  // c.fsw -> fsw rs2',  offset(rs1')
        5'b00111: c2i = {4'b0, C[6:5], C[12], 2'b01, C[4:2], 2'b01, C[9:7], 3'b011, C[11:10], 3'b0, 7'b0100011};      // c.sd -> sd rs2' offset(rs1')

        //
        // Quadrant 1
        //
        5'b01000: c2i = {{6{C[12]}}, C[12], C[6:2], C[11:7], 3'b0, C[11:7], 7'b0010011};                              // c.addi -> addi rd,  rd,  imm
        5'b01001: c2i = {C[12], C[8], C[10:9], C[6], C[7], C[2], C[11], C[5:3], {9{C[12]}}, 5'b00001, 7'b1101111};    // c.jal -> jal x1,  offset
        5'b01001: c2i = {{7{C[12]}}, C[6:2], C[11:7], 3'b0, C[11:7], 7'b0011011};                                     // c.addiw -> addiw rd,  rd,  imm
        5'b01010: c2i = {{7{C[12]}}, C[6:2], 5'b0, 3'b0, C[11:7], 7'b0010011};                                        // c.li -> addi rd,  x0,  imm
        5'b01011: c2i = {{15{C[12]}}, C[6:2], C[11:7], 7'b0110111};                                                   // c.lui -> lui rd,  imm
        5'b01011:
            if (C[11:7]==5'h02) c2i = {{3{C[12]}}, C[4:3], C[5], C[2], C[6], 4'b0, 5'h02, 3'b0, 5'h02, 7'b0010011};   // c.addi16sp -> addi x2,  x2,  imm
            else c2i = {{15{C[12]}}, C[6:2], C[11:7], 7'b0110111};                                                    // c.lui -> lui rd,  imm
        5'b01100: casex({C[12:10],  C[6:5]})
            5'bx00xx: c2i = {7'b0, C[6:2], 2'b01, C[9:7], 3'b101, 3'b01, C[9:7], 7'b0010011};                         // c.srli -> srli rd',  rd',  shamt
            5'bx01xx: c2i = {7'b0100000, C[6:2], 2'b01, C[9:7], 3'b101, 2'b01, C[9:7], 7'b0010011};                   // c.srai -> srai rd',  rd',  shamt
            5'bx10xx: c2i = {{7{C[12]}}, C[6:2], 2'b01, C[9:7], 3'b111, 2'b01, C[9:7], 7'b0010011};                   // c.andi -> andi rd',  rd',  imm
            5'b01100: c2i = {7'b0100000, 2'b01, C[4:2], 2'b01, C[9:7], 3'b0, 2'b01, C[9:7], 7'b0110011};              // c.sub -> sub rd',  rd',  rs2'
            5'b01101: c2i = {7'b0, 2'b01, C[4:2], 2'b01, C[9:7], 3'b100, 2'b01, C[9:7], 7'b0110011};                  // c.xor -> xor rd',  rd',  rs2'
            5'b01110: c2i = {7'b0, 2'b01, C[4:2], 2'b01, C[9:7], 3'b110, 2'b01, C[9:7], 7'b0110011};                  // c.or -> or rd',  rd',  rs2'
            5'b01111: c2i = {7'b0, 2'b01, C[4:2], 2'b01, C[9:7], 3'b111, 2'b01, C[9:7], 7'b0110011};                  // c.and -> and rd',  rd',  rs2'
            5'b11100: c2i = {7'b0100000, 2'b01, C[4:2], 2'b01, C[9:7], 3'b0, 2'b01, C[9:7], 7'b0111011};              // c.subw -> subw rd',  rd',  rs2'
            5'b11101: c2i = {7'b0000000, 2'b01, C[4:2], 2'b01, C[9:7], 3'b0, 2'b01, C[9:7], 7'b0111011};              // c.addw -> addw rd',  rd',  rs2'
        endcase
        5'b01101: c2i = {C[12], C[8], C[10:9], C[6], C[7], C[2], C[11], C[5:3], {9{C[12]}}, 5'b0, 7'b1101111};        // c.j -> jal x0,  offset
        5'b01110: c2i = {{4{C[12]}}, C[6:5], C[2], 5'b0, 2'b01, C[9:7], 3'b0, C[11:10], C[4:3], C[12], 7'b1100011};   // c.beqz -> beq rs1',  x0,  offset
        5'b01111: c2i = {{4{C[12]}}, C[6:5], C[2], 5'b0, 2'b01, C[9:7], 3'b001, C[11:10], C[4:3], C[12], 7'b1100011}; // c.bnez -> bne rs1',  x0,  offset

        //
        // Quadrant 2
        //
        5'b10000: c2i = {7'b0, C[6:2], C[11:7], 3'b001, C[11:7], 7'b0010011};                                         // c.slli -> slli rd,  rd,  shamt
        5'b10001: c2i = {3'b0, C[4:2], C[12], C[6:5], 3'b0, 5'h02, 3'b011, C[11:7], 7'b0000111};                      // c.fldsp -> fld rd,  offset(x2)
        5'b10010: c2i = {4'b0, C[3:2], C[12], C[6:4], 2'b0, 5'h02, 3'b010, C[11:7], 7'b0000011};                      // c.lwsp -> lw rd,  offset(x2)
        5'b10011: c2i = {4'b0, C[3:2], C[12], C[6:4], 2'b0, 5'h02, 3'b010, C[11:7], 7'b0000111};                      // c.flwsp -> flw rd,  offset(x2) TODO: should be C.LDSP on RV64
        // 5'b10011: c2i = {};                                                                                        // c.ldsp -> ld rd,  offset(x2)
        5'b10100: casex(C[12:2])
            11'b0_xxxxx_00000: c2i = {12'b0, C[11:7], 3'b0, 5'b0, 7'b1100111};                                        // c.jr -> jalr x0,  0(rs1)
            11'b0_xxxxx_xxxxx: c2i = {7'b0, C[6:2], 5'b0, 3'b0, C[11:7], 7'b0110011};                                 // c.mv -> add rd,  x0,  rs2
            11'b1_00000_00000: c2i = {12'h01, 13'b0, 7'b1110011};                                                     // c.ebreak -> ebreak
            11'b1_xxxxx_00000: c2i = {12'b0, C[11:7], 3'b0, 5'h01, 7'b1100111};                                       // c.jalr -> jalr x1,  0(rs1)
            11'b1_xxxxx_xxxxx: c2i = {7'b0, C[6:2], C[11:7], 3'b0, C[11:7], 7'b0110011};                              // c.add -> add rd,  rd,  rs2
        endcase
        5'b10101: c2i = {3'b0,C[9:7],C[12],C[6:2],5'h02,3'b011,C[11:10],3'b0,7'b0100111};                             // c.fsdsp -> fsd rs2, offset(x2)
        5'b10110: c2i = {4'b0,C[8:7],C[12],C[6:2],5'h02,3'b010,C[11:9],2'b0,7'b0100011};                              // c.swsp -> sw rs2, offset(x2)
        5'b10111: c2i = {4'b0,C[8:7],C[12],C[6:2],5'h02,3'b010,C[11:9],2'b0,7'b0100111};                              // c.fswsp -> fsw rs2, offset(x2)
    endcase
endfunction
