# SPDX-License-Identifier: MIT
# bradasm -- the BradISA V2 assembler.
#
# Nothing but a C99 compiler. No configure, no dependencies, no code
# generation: if you can build the FPGA you can build the assembler.

CC      ?= cc
CFLAGS  ?= -O2 -std=c99 -Wall -Wextra -Wshadow -Wstrict-prototypes \
           -Wmissing-prototypes -Wpointer-arith -Wcast-qual -pedantic
LDFLAGS ?=

SRCDIR   = src
INCDIR   = include
TESTDIR  = tests
BUILDDIR = build

LIB_SRC  = $(SRCDIR)/bradasm.c
LIB_OBJ  = $(BUILDDIR)/bradasm.o
CLI_OBJ  = $(BUILDDIR)/main.o
TEST_OBJ = $(BUILDDIR)/test_brad_as.o

LIB  = $(BUILDDIR)/libbradasm.a
ASM  = $(BUILDDIR)/bradasm
TEST = $(BUILDDIR)/test_brad_as

DEFINES ?= ../../rtl/verilog/bradisa_defines.v

.PHONY: all test clean check install

all: $(ASM) $(TEST)

$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

$(LIB_OBJ): $(LIB_SRC) $(INCDIR)/brad/bradasm.h $(INCDIR)/brad/bradisa.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(INCDIR) -c $< -o $@

$(CLI_OBJ): $(SRCDIR)/main.c $(INCDIR)/brad/bradasm.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(INCDIR) -c $< -o $@

$(TEST_OBJ): $(TESTDIR)/test_brad_as.c $(INCDIR)/brad/bradasm.h | $(BUILDDIR)
	$(CC) $(CFLAGS) -I$(INCDIR) -c $< -o $@

$(LIB): $(LIB_OBJ)
	$(AR) rcs $@ $^

$(ASM): $(CLI_OBJ) $(LIB)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CLI_OBJ) $(LIB)

$(TEST): $(TEST_OBJ) $(LIB)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(TEST_OBJ) $(LIB)

# The self-test assembles every V2 mnemonic and asserts exact encodings
# against brad/bradisa.h, then parses bradisa_defines.v and fails if the RTL's
# opcode table has drifted away from the assembler's header. Pass the path if
# it is not where the default expects.
test: $(TEST)
	./$(TEST) $(DEFINES)

check: test

clean:
	rm -rf $(BUILDDIR)
