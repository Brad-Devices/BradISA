// SPDX-License-Identifier: MIT
// BradISA V2 -- Verilog RTL Package
// 6-bit opcode, 32 registers, 7 formats, 50 instructions.
// Every instruction is exactly 32 bits.
//
// Field layout (all formats):
//   [31:26]  op    (6 bits)
//   [25:21]  rd    (5 bits)  -- or rs2 for SI/BR
//   [20:16]  rs1   (5 bits)  -- or rd for JMP/U
//   [15:0]   imm/offset (16 bits) -- or rs2 for RRR/BR
//
// Format table (from bradisa_spec.tex §3):
//   RRR: op[5:0] rd[4:0] rs1[4:0] rs2[4:0] 11'b0
//   RI:  op[5:0] rd[4:0] rs1[4:0] imm[15:0]
//   SI:  op[5:0] rs2[4:0] rs1[4:0] imm[15:0]
//   BR:  op[5:0] rs1[4:0] rs2[4:0] offset[15:0]
//   IJ:  op[5:0] rd[4:0] rs1[4:0] imm[15:0]
//   JMP: op[5:0] rd[4:0] offset[20:0]
//   U:   op[5:0] rd[4:0] imm[20:0]

`ifndef BRADISA_PKG_V2
`define BRADISA_PKG_V2

// ─── Opcodes (6-bit, 64 slots) ──────────────────────────────

// ALU, register-register (0x00-0x0F): 15 used, 1 reserved
localparam BRAD_OP_NOP    = 6'h00;
localparam BRAD_OP_ADD    = 6'h01;
localparam BRAD_OP_SUB    = 6'h02;
localparam BRAD_OP_MUL    = 6'h03;
localparam BRAD_OP_MULHU  = 6'h04;
localparam BRAD_OP_DIV    = 6'h05;
localparam BRAD_OP_DIVU   = 6'h06;
localparam BRAD_OP_REM    = 6'h07;
localparam BRAD_OP_REMU   = 6'h08;
localparam BRAD_OP_AND    = 6'h09;
localparam BRAD_OP_OR     = 6'h0A;
localparam BRAD_OP_XOR    = 6'h0B;
localparam BRAD_OP_SHL    = 6'h0C;
localparam BRAD_OP_SHR    = 6'h0D;
localparam BRAD_OP_SAR    = 6'h0E;
// 0x0F reserved

// ALU, register-immediate (0x10-0x1F): 9 used, 7 reserved
localparam BRAD_OP_ADDI   = 6'h10;
localparam BRAD_OP_ANDI   = 6'h11;
localparam BRAD_OP_ORI    = 6'h12;
localparam BRAD_OP_XORI   = 6'h13;
localparam BRAD_OP_SLLI   = 6'h14;
localparam BRAD_OP_SRLI   = 6'h15;
localparam BRAD_OP_SRAI   = 6'h16;
localparam BRAD_OP_SLTI   = 6'h17;
localparam BRAD_OP_SLTIU  = 6'h18;
// 0x19-0x1F reserved

// Load / store (0x20-0x27): 6 used, 2 reserved
localparam BRAD_OP_LDW    = 6'h20;
localparam BRAD_OP_LHU    = 6'h21;
localparam BRAD_OP_LHBU   = 6'h22;
localparam BRAD_OP_STW    = 6'h23;
localparam BRAD_OP_SH     = 6'h24;
localparam BRAD_OP_SB     = 6'h25;
// 0x26-0x27 reserved

// Upper immediate (0x28-0x2F): 8 used (LUI, AUIPC, JMP, JAL, CALL, JALR, RET, FENCE)
localparam BRAD_OP_LUI    = 6'h28;
localparam BRAD_OP_AUIPC  = 6'h29;
localparam BRAD_OP_JMP    = 6'h2A;
localparam BRAD_OP_JAL    = 6'h2B;
localparam BRAD_OP_CALL   = 6'h2C;
localparam BRAD_OP_JALR   = 6'h2D;
localparam BRAD_OP_RET    = 6'h2E;
localparam BRAD_OP_FENCE  = 6'h2F;

// Branches (0x30-0x3F): 8 used, 8 reserved
localparam BRAD_OP_BEQ    = 6'h30;
localparam BRAD_OP_BNE    = 6'h31;
localparam BRAD_OP_BLT    = 6'h32;
localparam BRAD_OP_BGE    = 6'h33;
localparam BRAD_OP_BLTU   = 6'h34;
localparam BRAD_OP_BGEU   = 6'h35;
localparam BRAD_OP_BZ     = 6'h36;
localparam BRAD_OP_BNZ    = 6'h37;
// 0x38-0x3F reserved

// Atomics (0x38-0x3B): 4 used, 0 reserved (0x3C-0x3F reserved separately)
localparam BRAD_OP_LR_W       = 6'h38;
localparam BRAD_OP_SC_W       = 6'h39;
localparam BRAD_OP_AMOSWAP_W  = 6'h3A;
localparam BRAD_OP_AMOADD_W   = 6'h3B;
// 0x3C-0x3F reserved (extension escape)

// 0x50-0x5F reserved (extension space)
// 0x60-0x63 vector escape (reserved)

// ─── Register numbers (5-bit, 32 registers) ─────────────────
// The ABI is the one published in bradisa_spec.tex §3.2 and
// KINETIC_MICROARCHITECTURE.md: eight argument registers, six
// temporaries, eleven callee-saved, a link register, a stack pointer,
// a global pointer and a thread pointer. r30 and r31 are reserved.
// The link register is r15.  tools/check_isa_drift.py compares this
// block against the C header and fails if they disagree.
localparam BRAD_R0   = 5'd0;   // zero register (hardwired 0)
localparam BRAD_A0   = 5'd1;   // argument 0 / return value
localparam BRAD_A1   = 5'd2;   // argument 1
localparam BRAD_A2   = 5'd3;   // argument 2
localparam BRAD_A3   = 5'd4;   // argument 3
localparam BRAD_A4   = 5'd5;   // argument 4
localparam BRAD_A5   = 5'd6;   // argument 5
localparam BRAD_A6   = 5'd7;   // argument 6
localparam BRAD_A7   = 5'd8;   // argument 7
localparam BRAD_T0   = 5'd9;   // temporary
localparam BRAD_T1   = 5'd10;  // temporary
localparam BRAD_T2   = 5'd11;  // temporary
localparam BRAD_T3   = 5'd12;  // temporary
localparam BRAD_T4   = 5'd13;  // temporary
localparam BRAD_T5   = 5'd14;  // temporary
localparam BRAD_LR   = 5'd15;  // link register (return address)
localparam BRAD_RA   = 5'd15;  // alias: return address = lr
localparam BRAD_S0   = 5'd16;  // saved (frame pointer)
localparam BRAD_S1   = 5'd17;  // saved
localparam BRAD_S2   = 5'd18;  // saved
localparam BRAD_S3   = 5'd19;  // saved
localparam BRAD_S4   = 5'd20;  // saved
localparam BRAD_S5   = 5'd21;  // saved
localparam BRAD_S6   = 5'd22;  // saved
localparam BRAD_S7   = 5'd23;  // saved
localparam BRAD_S8   = 5'd24;  // saved
localparam BRAD_S9   = 5'd25;  // saved
localparam BRAD_S10  = 5'd26;  // saved
localparam BRAD_SP   = 5'd27;  // stack pointer
localparam BRAD_GP   = 5'd28;  // global pointer
localparam BRAD_TP   = 5'd29;  // thread pointer
// r30-r31 reserved
localparam BRAD_NUM_REGS = 32;

// ─── Field positions (V2) ────────────────────────────────────
localparam BRAD_OPCODE_SHIFT = 26;
localparam BRAD_RD_SHIFT     = 21;
localparam BRAD_RS1_SHIFT    = 16;
localparam BRAD_RS2_SHIFT    = 11;
localparam BRAD_IMM_SHIFT    = 0;

// ─── Field masks ────────────────────────────────────────────
localparam [5:0]  BRAD_OPCODE_MASK = 6'h3F;
localparam [4:0]  BRAD_REG_MASK    = 5'h1F;

// ─── Format identification ───────────────────────────────────
// Format is determined by opcode range, not by a separate field.
//   RRR: 0x00-0x0E  (ALU reg-reg)
//   RI:  0x10-0x22  (ALU reg-imm, loads)
//   SI:  0x23-0x25  (stores)
//   U:   0x28-0x29  (upper immediate)
//   JMP: 0x2A-0x2C  (JMP, JAL, CALL)
//   IJ:  0x2D       (JALR)
//   BR:  0x30-0x37  (branches)
//   AMO: 0x38-0x3B  (atomics; RRR field shape)
//   RET: 0x2E       (return)
//   FENCE: 0x2F     (ordering barrier)

localparam [2:0] BRAD_FMT_RRR = 3'd0;
localparam [2:0] BRAD_FMT_RI  = 3'd1;
localparam [2:0] BRAD_FMT_SI  = 3'd2;
localparam [2:0] BRAD_FMT_BR  = 3'd3;
localparam [2:0] BRAD_FMT_IJ  = 3'd4;
localparam [2:0] BRAD_FMT_JMP = 3'd5;
localparam [2:0] BRAD_FMT_U   = 3'd6;
localparam [2:0] BRAD_FMT_SP  = 3'd7;  // NOP, RET, FENCE

// ─── Pipeline model constants ────────────────────────────────
localparam BRAD_PHOENIX_DEPTH      = 10;
localparam BRAD_PHOENIX_EXEC_STAGE = 6;
localparam BRAD_FALCON_DEPTH       = 5;
localparam BRAD_FALCON_EXEC_STAGE  = 3;

// ─── Exception vectors ──────────────────────────────────────
localparam BRAD_EXC_RESET      = 32'h00000000;
localparam BRAD_EXC_UNDEF_INSN = 32'h00000004;
localparam BRAD_EXC_PAGE_FAULT = 32'h00000008;
localparam BRAD_EXC_UNALIGNED  = 32'h0000000C;
localparam BRAD_EXC_PRIVILEGE  = 32'h00000010;
localparam BRAD_EXC_SYSCALL    = 32'h00000014;
localparam BRAD_EXC_TIMER      = 32'h00000018;

// ─── MSR indices ────────────────────────────────────────────
localparam BRAD_MSR_STATUS    = 3'd0;
localparam BRAD_MSR_CAUSE     = 3'd1;
localparam BRAD_MSR_EPC       = 3'd2;
localparam BRAD_MSR_EAR       = 3'd3;
localparam BRAD_MSR_TICK      = 3'd5;

// ─── RET encoding ───────────────────────────────────────────
// Opcode 0x2E occupies bits [31:26], so the word is 0xB8000000.
// 0x2E000000 (the V1-shaped constant) would decode as opcode 0x0B.
localparam BRAD_RET_ENCODING = 32'hB8000000;

`endif
