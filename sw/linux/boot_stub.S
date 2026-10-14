// Previous-stage stub for OpenSBI (issue #21): loaded into the
// harness boot ROM at 0x1000, presents the standard firmware
// entry contract (a0 = hartid, a1 = DTB pointer) and jumps to
// OpenSBI fw_jump at 0x8000_0000. Memory layout (soc_tb):
//   0x8000_0000  OpenSBI fw_jump.bin
//   0x8020_0000  S payload (Linux Image, or s_hello test)
//   0x8200_0000  initrd (when used)
//   0x8300_0000  DTB
	.section .text
	.globl _start
_start:
	li	a0, 0			// hartid 0 (a0 is also 0 at reset)
	li	a1, 0x83000000		// DTB
	li	t0, 0x80000000		// OpenSBI
	jr	t0
