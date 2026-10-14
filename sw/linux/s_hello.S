// Minimal S-mode payload (issue #21): proves OpenSBI jumped to
// supervisor with delegation live, using the legacy SBI console
// putchar extension (a7 = 1). Loaded by fw_jump at 0x8020_0000
// in place of a kernel Image for the first boot gate; soc_tb
// passes when it sees the banner on the UART.
	.section .text
	.globl _start
_start:
	la	t0, msg
1:	lbu	a0, 0(t0)
	beqz	a0, 2f
	li	a7, 1			// SBI console putchar
	ecall
	addi	t0, t0, 1
	j	1b
2:	wfi
	j	2b

	.section .rodata
msg:	.asciz "HELLO FROM S-MODE\r\n"
