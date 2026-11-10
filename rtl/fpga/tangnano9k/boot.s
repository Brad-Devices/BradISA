; SPDX-License-Identifier: MIT
; Tang Nano 9K boot ROM -- BradISA V2
;
; This is what the CPU on the board actually executes.  The board's 27 MHz
; oscillator would run it about 13 million times a second, so the board top
; divides the core clock down to one cycle per ~0.5 s and this program walks
; a counter on the 6 onboard LEDs via the data-memory write port.
;
; The generated boot_rom.vh is the V2-assembled image; its words are the
; encodings the RTL executes, and the assembler's self-test asserts the
; image byte for byte.
;
; IMEM_WORDS is 16 on the board top, and the last 11 words are NOP padding
; (V2 opcode 0), which the core decodes as a no-op. Nothing ever fetches
; them -- the loop is closed by the JMP -- but a combinational ROM should
; not contain uninitialised bits either way.

        .org 0x00

        ADDI r1, r0, 0            ; init counter
loop:   ADDI r1, r1, 1            ; r1++
        ADDI r2, r0, 0x04        ; r2 = data address 0x04
        STW  r1, [r2 + 0]        ; publish counter out through dmem
        JMP  loop                ; back to the loop head

        ; V2 NOP padding to 16 words (opcode 0)
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0
        .word 0

        .entry 0x00
