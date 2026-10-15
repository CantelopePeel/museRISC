OUTPUT_FORMAT("elf64-littleriscv")
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text) *(.text.*) }
  . = ALIGN(8);
  .rodata : { *(.rodata) *(.rodata.*) *(.srodata) }
  .data : { *(.data) *(.sdata) }
  _bss_start = .;
  .bss : { *(.bss) *(.sbss) *(COMMON) }
  _bss_end = .;
}
