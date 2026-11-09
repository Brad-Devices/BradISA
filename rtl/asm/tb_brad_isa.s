; SPDX-License-Identifier: MIT
; BradISA V2 -- the full-ISA program both testbenches execute.
;
; rtl/verilog/tb_brad_isa.v and rtl/vhdl/tb_brad_isa.vhd load the words this
; file assembles to (tb_brad_isa_prog.mem) and check what the core did with
; them.  The program stores every observable result to its own data-memory
; slot, so both simulators see the same bytes and the same checks.  Until
; this file existed, each testbench encoded every instruction by hand -- which
; is how 0x82000007 quietly meant "ADDI r2" while somebody believed it meant
; "ADDI r1" -- and the two trees could drift apart while both stayed green.
; Now the program is written once, in assembly, and the encodings it produces
; are the encodings the RTL executes; bradasm's self-test asserts each of
; those encodings against the simulated core.
;
; dmem slots (word address = addr, STW base r0 writes dmem[addr>>2]):
;   0x00..0x1C  the eight RRR results (r1)      ADD SUB MUL AND OR XOR SHL SHR
;   0x20        ADDI r2, r0, -7   -> 0xFFFFFFF9
;   0x24        ADDI r1, r1, -7   -> 0          (same-register rsum)
;   0x28        write to r0 discarded -> 0      (r0 hardwired zero)
;   0x2C        ADDI r2, r0, 42   -> 42
;   0x30        LDW r4 result     -> 42         0x34: STW base -> 0x40
;   0x38        BZ taken          -> 7
;   0x3C        BZ not taken      -> 99
;   0x40        BNZ taken         -> 7
;   0x44        JMP               -> 7
;   0x48        CALL return r1    -> 1          0x4C: sub r2 -> 7
;   0x50        ra after RET      -> 0x12C (V2 ABI: ra is r15)
;   0x54        loop sum r2       -> 55         0x58: loop counter r3 -> 0
;
; The branch/jump offsets are computed by the assembler from the labels.
; Hand-computing (12-4-4)/4 = 1 was the old way and it is a trap.

        .org 0x00

; ── The eight RRR ops, each result stored to its own slot ──────────────
        ADDI r2, r0, 7           ; operand A = 7
        ADDI r3, r0, 5           ; operand B = 5
        ADD  r1, r2, r3          ; 7 + 5
        STW  r1, [r0 + 0x00]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        SUB  r1, r2, r3          ; 7 - 5
        STW  r1, [r0 + 0x04]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        MUL  r1, r2, r3          ; 7 * 5
        STW  r1, [r0 + 0x08]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        AND  r1, r2, r3          ; 7 & 5
        STW  r1, [r0 + 0x0C]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        OR   r1, r2, r3          ; 7 | 5
        STW  r1, [r0 + 0x10]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        XOR  r1, r2, r3          ; 7 ^ 5
        STW  r1, [r0 + 0x14]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        SHL  r1, r2, r3          ; 7 << (5 & 31)
        STW  r1, [r0 + 0x18]
        ADDI r2, r0, 7
        ADDI r3, r0, 5
        SHR  r1, r2, r3          ; 7 >> (5 & 31)
        STW  r1, [r0 + 0x1C]

; ── ADDI: negative immediate, same-register form, r0 constant ──────────
        ADDI r2, r0, -7          ; r2 = 0xFFFFFFF9
        ADDI r1, r0, 7
        ADDI r1, r1, -7          ; r1 = 0
        STW  r1, [r0 + 0x24]     ; rsum
        STW  r2, [r0 + 0x20]     ; negative immediate
        ADDI r2, r0, 42
        ADDI r0, r0, -1          ; write to r0 is discarded
        STW  r0, [r0 + 0x28]     ; r0 hardwired zero
        STW  r2, [r0 + 0x2C]     ; 42

; ── STW / LDW round trip ───────────────────────────────────────────────
; STW keeps its source register in the RS2 field [19:16]; the RD field is
; unused.  docs/04-base-isa.md says RD -- the RTL wins.
        ADDI r2, r0, 0x40        ; data base
        ADDI r3, r0, 42          ; value
        STW  r3, [r2 + 8]
        LDW  r4, [r2 + 8]
        STW  r4, [r0 + 0x30]     ; round-trip value
        STW  r2, [r0 + 0x34]     ; base register

; ── BZ taken: r1 = 0, so the 99 is skipped ─────────────────────────────
        ADDI r1, r0, 0
        BZ   r1, bz_taken_dst    ; r1 == 0 -> branch
        ADDI r1, r0, 99          ; only runs on a broken BZ
        STW  r1, [r0 + 0x38]     ; failure record
        JMP  bz_taken_after
bz_taken_dst:
        ADDI r1, r0, 7
bz_taken_after:
        STW  r1, [r0 + 0x38]     ; 7 on success, overwrites any 99

; ── BZ not taken: r1 = 5, so control falls through ─────────────────────
        ADDI r1, r0, 5
        BZ   r1, bz_nt_dst       ; r1 != 0 -> fall through
        ADDI r1, r0, 99
        STW  r1, [r0 + 0x3C]     ; expected: 99
        JMP  bz_nt_after
bz_nt_dst:
        ADDI r1, r0, 7           ; must not run; records 7 on a broken BZ
        STW  r1, [r0 + 0x3C]
bz_nt_after:

; ── BNZ taken: r1 = 5, so the 99 is skipped ────────────────────────────
        ADDI r1, r0, 5
        BNZ  r1, bnz_taken_dst   ; r1 != 0 -> branch
        ADDI r1, r0, 99
        STW  r1, [r0 + 0x40]     ; failure record
        JMP  bnz_taken_after
bnz_taken_dst:
        ADDI r1, r0, 7
bnz_taken_after:
        STW  r1, [r0 + 0x40]     ; 7 on success

; ── JMP: the skipped words stay skipped ────────────────────────────────
        JMP  jmp_dst
        ADDI r1, r0, 99
        STW  r1, [r0 + 0x44]     ; failure record
        JMP  jmp_after
jmp_dst:
        ADDI r1, r0, 7
        STW  r1, [r0 + 0x44]     ; 7 on success
jmp_after:

; ── CALL / RET ──────────────────────────────────────────────────────────
; CALL writes LR = PC+4, RET is implemented as PC <- rs1, so the gateway
; back through LR is what makes a subroutine possible at all.
        CALL sub_call            ; LR = address of the next instruction
        ADDI r1, r0, 1           ; return point
        STW  r1, [r0 + 0x48]     ; 1
        STW  r2, [r0 + 0x4C]     ; 7, written by the subroutine
        STW  lr,  [r0 + 0x50]    ; ra = return address (V2: lr is r15)
        JMP  sum_init
sub_call:
        ADDI r2, r0, 7
        RET                      ; bare RET returns through lr

; ── A real loop: r2 = sum(10..1) = 55 ───────────────────────────────────
; This is the combination the old testbench never ran: an RRR op whose rs2
; was produced one instruction earlier, immediately followed by the ADDI
; that rewrites that same register.
sum_init:
        ADDI r2, r0, 0           ; accumulator
        ADDI r3, r0, 10          ; counter
sum_loop:
        ADD  r2, r2, r3          ; acc += counter
        ADDI r3, r3, -1
        BNZ  r3, sum_loop        ; 10 iterations
        STW  r2, [r0 + 0x54]     ; 55
        STW  r3, [r0 + 0x58]     ; 0
        JMP  $                   ; park: never fetch a non-instruction

        .entry 0x00