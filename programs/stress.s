; sloputron-1 stress test for the clock sweep (scripts/board_sweep.py, docs/phase3/board.md).
; Threads 1-3 repeat a D-002 kernel on data they generate, check the answer against the
; D-002 check value, and count passes and failures in RAM:
;   thread 1  crc16 (CCITT-FALSE) of the 256 LFSR bytes            expect 0x2865
;   thread 2  the 64 16x16->32 multiplies of LFSR pairs, shift-and-add;
;             xor of the 32-bit products                             expect 0x755EA6D0
;   thread 3  insertion sort of 64 LFSR words, then checks that they ascend and that
;             sum((i+1) * a[i]) mod 2^16                             expect 0xE0FB
; The longest timing paths go through the adder's carry chain into the carry flag, so the
; kernels lean on add, sub and cmp with carry skips. They use every ISA 1.0 extension
; (D-008): bcc/bcs, carry shifts (shl/shr into C, rcl/rcr) and load/store offsets.
; Thread 0 answers each byte received on the UART with one line of six 4-digit hex counts:
;   "P1 F1 P2 F2 P3 F3\r\n"   (P = passes, F = failures, per worker thread)
; LFSR (D-002): x = 0xACE1; each step x = (x >> 1) ^ (0xB400 if x was odd); use the new x.

        .equ  COUNTS, 0x020             ; RAM: P1 F1 P2 F2 P3 F3 (RAM starts at zero)
        .equ  ARRAY,  0x100             ; RAM: thread 3's 64 words

start:  mov   r1, r15                   ; r15 = thread number
        skip  nz, r1
        jmp   t0
        sub   r1, 1
        skip  nz, r1
        jmp   t1
        sub   r1, 1
        skip  nz, r1
        jmp   t2
        jmp   t3

; ---- thread 0: one line of counts per received byte ---------------------------------------
t0:     li    r12, lo(putc)
        ldhi  r12, hi(putc)
        li    r2, 'S'
        jal   r13, r12
        li    r2, 13
        jal   r13, r12
        li    r2, 10
        jal   r13, r12

query:  li    r10, UART_STATUS & 0xff   ; 0xFD sign-extends to 0xFFFD: address 0xFFD
qwait:  ld    r11, [r10]
        and   r11, 2                    ; byte waiting?
        skip  nz, r11
        jmp   qwait
        li    r10, UART_RX & 0xff
        ld    r2, [r10]                 ; read clears "byte waiting"

        li    r3, COUNTS
count:  ld    r6, [r3]
        li    r7, 4                     ; 4 hex digits, most significant first
digit:  li    r2, 0
        li    r8, 4
nib:    shl   r6                        ; C = top bit of r6
        rcl   r2                        ; r2 = r2 << 1 | C
        sub   r8, 1
        skip  z, r8
        jmp   nib
        li    r9, 10
        cmp   r2, r9
        skip  cc                        ; r2 < 10: no letter adjust
        add   r2, 7                     ; 'A' - '0' - 10
        add   r2, '0'
        jal   r13, r12
        sub   r7, 1
        skip  z, r7
        jmp   digit
        add   r3, 1
        li    r9, COUNTS + 6
        cmp   r3, r9
        bcs   eol                       ; all six printed
        li    r2, ' '
        jal   r13, r12
        jmp   count
eol:    li    r2, 13
        jal   r13, r12
        li    r2, 10
        jal   r13, r12
        jmp   query

; putc: send r2's low byte. Returns through r13. Uses r10, r11.
putc:   li    r10, UART_STATUS & 0xff
pwait:  ld    r11, [r10]
        and   r11, 1                    ; transmitter busy?
        skip  z, r11
        jmp   pwait
        li    r10, UART_TX & 0xff
        st    r2, [r10]
        jal   r0, r13

; ---- thread 1: crc16 ----------------------------------------------------------------------
t1:     li    r4, 0x21
        ldhi  r4, 0x10                  ; crc polynomial 0x1021
        li    r12, 0
        ldhi  r12, 0xB4                 ; LFSR taps 0xB400
cround: li    r10, 0xE1
        ldhi  r10, 0xAC                 ; LFSR seed 0xACE1
        li    r1, -1                    ; crc
        li    r6, 0
        ldhi  r6, 0xFF                  ; -256: counts up to 0 (256 bytes)
cbyte:  shr   r10                       ; LFSR step: C = the bit shifted out
        skip  cc
        xor   r10, r12
        mov   r7, r10                   ; byte << 8: eight shifts drop the high byte
        shl   r7
        shl   r7
        shl   r7
        shl   r7
        shl   r7
        shl   r7
        shl   r7
        shl   r7
        xor   r1, r7
        li    r3, -8                    ; 8 bits
cbit:   shl   r1                        ; C = old top bit, which decides the xor
        skip  cc
        xor   r1, r4
        add   r3, 1                     ; C when the count reaches 0
        bcc   cbit
        add   r6, 1
        bcc   cbyte
        li    r9, 0x65
        ldhi  r9, 0x28                  ; expect 0x2865
        xor   r9, r1
        li    r8, COUNTS + 0
        skip  z, r9
        add   r8, 1                     ; wrong: count a failure
        ld    r9, [r8]
        add   r9, 1
        st    r9, [r8]
        jmp   cround

; ---- thread 2: mul16 ----------------------------------------------------------------------
t2:     li    r12, 0
        ldhi  r12, 0xB4                 ; LFSR taps
mround: li    r10, 0xE1
        ldhi  r10, 0xAC                 ; LFSR seed
        li    r1, 0                     ; xor of the low words
        li    r7, 0                     ; xor of the high words
        li    r8, -64                   ; 64 pairs
mpair:  shr   r10                       ; a = next LFSR value
        skip  cc
        xor   r10, r12
        mov   r2, r10
        shr   r10                       ; b = next LFSR value
        skip  cc
        xor   r10, r12
        mov   r3, r10
        li    r4, 0                     ; hi (lo needs no start value: all 16 bits shift in)
        li    r6, -16                   ; 16 bits, least significant first
mbit:   shr   r3                        ; C = next bit of b
        skip  cc
        add   r4, r2                    ; hi += a; C = carry out
        rcr   r4                        ; (C:hi:lo) >>= 1
        rcr   r5
        add   r6, 1
        bcc   mbit
        xor   r1, r5
        xor   r7, r4
        add   r8, 1
        bcc   mpair
        li    r9, 0xD0
        ldhi  r9, 0xA6                  ; expect low 0xA6D0
        xor   r9, r1
        li    r11, 0x5E
        ldhi  r11, 0x75                 ; expect high 0x755E
        xor   r11, r7
        or    r9, r11
        li    r8, COUNTS + 2
        skip  z, r9
        add   r8, 1
        ld    r9, [r8]
        add   r9, 1
        st    r9, [r8]
        jmp   mround

; ---- thread 3: insertion sort -------------------------------------------------------------
t3:     li    r12, 0
        ldhi  r12, 0xB4                 ; LFSR taps
        li    r14, 0
        ldhi  r14, hi(ARRAY)            ; array start
        mov   r13, r14
        add   r13, 64                   ; array end
sround: li    r10, 0xE1
        ldhi  r10, 0xAC                 ; LFSR seed
        mov   r1, r14
fill:   shr   r10                       ; LFSR step
        skip  cc
        xor   r10, r12
        st    r10, [r1]
        shr   r10                       ; two per pass: the second store uses an offset
        skip  cc
        xor   r10, r12
        st    r10, [r1+1]
        add   r1, 2
        cmp   r1, r13
        bcc   fill
        mov   r1, r14
        add   r1, 1                     ; p = &a[1]
outer:  ld    r2, [r1]                  ; key = *p
        mov   r4, r1
        sub   r4, 1                     ; j; the hole is always j + 1
inner:  ld    r5, [r4]                  ; a[j] (read even when j is below the array)
        cmp   r4, r14
        bcc   place                     ; j below the array
        cmp   r2, r5
        bcs   place                     ; key >= a[j]
        st    r5, [r4+1]                ; move a[j] up
        sub   r4, 1
        jmp   inner
place:  st    r2, [r4+1]
        add   r1, 1
        cmp   r1, r13
        bcc   outer
        li    r6, 0                     ; s = sum of a[i..63]
        li    r7, 0                     ; t = sum of s = sum((i+1) * a[i])
        li    r9, -1                    ; a[i+1], starting above any word
        li    r11, 0                    ; order errors
        mov   r1, r13
check:  sub   r1, 1
        ld    r5, [r1]
        cmp   r9, r5
        skip  cs                        ; a[i+1] >= a[i]: in order
        or    r11, 1
        mov   r9, r5
        add   r6, r5
        add   r7, r6
        cmp   r14, r1
        bcc   check                     ; not yet at a[0]
        li    r9, 0xFB
        ldhi  r9, 0xE0                  ; expect 0xE0FB
        xor   r9, r7
        or    r9, r11
        li    r8, COUNTS + 4
        skip  z, r9
        add   r8, 1
        ld    r9, [r8]
        add   r9, 1
        st    r9, [r8]
        jmp   sround
