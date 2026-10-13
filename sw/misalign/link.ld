OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 16M }
SECTIONS {
  .text.init : { *(.text.init) *(.text*) } > RAM
  . = ALIGN(0x1000);
  .data : { *(.data*) *(.sdata*) } > RAM
  .bss : { *(.bss*) } > RAM
}
