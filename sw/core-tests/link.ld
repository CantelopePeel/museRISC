/* Directed stage-1 tests: everything in one RAM image at 0. */
OUTPUT_FORMAT("elf64-littleriscv")
ENTRY(_start)
SECTIONS {
  . = 0x00000000;
  .text : { *(.text) *(.text.*) }
  . = ALIGN(8);
  .data : { *(.data) *(.sdata) *(.rodata) }
  .bss  : { *(.bss) *(.sbss) }
}
