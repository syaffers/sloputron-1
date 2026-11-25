; sloputron-1 demo: all four threads at once (rtl/board/sloputron.sv).
;   thread 0  prints "sloputron-1 crc16=29B1\r\n" over the UART, then echoes every byte
;   thread 1  counts on the LEDs (a 32-bit counter; the LEDs show bits 16..20)
;   thread 2  computes CRC-16/CCITT-FALSE of "123456789" and hands it to thread 0 in RAM
;   thread 3  idles
; Assemble: isa/asm.py programs/demo.s -o build/programs/demo.hex   (make does this)

        .equ  CRC,  0x010               ; RAM: thread 2's result
        .equ  FLAG, 0x011               ; RAM: nonzero once CRC is valid (RAM starts at 0)

start:  mov   r1, r15                   ; r15 = thread number
        skip  nz, r1
        jmp   t0
        sub   r1, 1
        skip  nz, r1
        jmp   t1
        sub   r1, 1
        skip  nz, r1
        jmp   t2
idle:   jmp   idle                      ; thread 3

; ---- thread 0: banner, then echo --------------------------------------------------------
t0:     li    r12, lo(putc)
        ldhi  r12, hi(putc)
        li    r2, 's'
        jal   r13, r12
        li    r2, 'l'
        jal   r13, r12
        li    r2, 'o'
        jal   r13, r12
        li    r2, 'p'
        jal   r13, r12
        li    r2, 'u'
        jal   r13, r12
        li    r2, 't'
        jal   r13, r12
        li    r2, 'r'
        jal   r13, r12
        li    r2, 'o'
        jal   r13, r12
        li    r2, 'n'
        jal   r13, r12
        li    r2, '-'
        jal   r13, r12
        li    r2, '1'
        jal   r13, r12
        li    r2, ' '
        jal   r13, r12
        li    r2, 'c'
        jal   r13, r12
        li    r2, 'r'
        jal   r13, r12
        li    r2, 'c'
        jal   r13, r12
        li    r2, '1'
        jal   r13, r12
        li    r2, '6'
        jal   r13, r12
        li    r2, '='
        jal   r13, r12

        li    r8, FLAG                  ; wait for thread 2
wflag:  ld    r3, [r8]
        skip  nz, r3
        jmp   wflag
        li    r8, CRC
        ld    r6, [r8]                  ; value to print

        li    r7, 4                     ; 4 hex digits, most significant first
digit:  li    r2, 0
        li    r8, 4
nib:    shl   r2                        ; r2 = r2 << 1 | top bit of r6
        skip  nneg, r6
        or    r2, 1
        shl   r6
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

        li    r2, 13
        jal   r13, r12
        li    r2, 10
        jal   r13, r12

echo:   li    r10, UART_STATUS & 0xff   ; 0xFD sign-extends to 0xFFFD: address 0xFFD
ewait:  ld    r11, [r10]
        and   r11, 2                    ; byte waiting?
        skip  nz, r11
        jmp   ewait
        li    r10, UART_RX & 0xff
        ld    r2, [r10]                 ; read clears "byte waiting"
        jal   r13, r12
        jmp   echo

; putc: send r2's low byte. Returns through r13. Uses r10, r11.
putc:   li    r10, UART_STATUS & 0xff
pwait:  ld    r11, [r10]
        and   r11, 1                    ; transmitter busy?
        skip  z, r11
        jmp   pwait
        li    r10, UART_TX & 0xff
        st    r2, [r10]
        jal   r0, r13

; ---- thread 1: LED counter -------------------------------------------------------------
t1:     li    r1, 0                     ; low word
        li    r2, 0                     ; high word
        li    r3, LED & 0xff
count:  add   r1, 1                     ; C = carry out of the low word
        skip  cc
        add   r2, 1
        st    r2, [r3]                  ; LEDs = bits 4..0 of the high word
        jmp   count

; ---- thread 2: CRC-16/CCITT-FALSE of "123456789" --------------------------------------
t2:     li    r1, -1                    ; crc
        li    r7, 0
        ldhi  r7, '1'                   ; current byte << 8
        li    r9, 0
        ldhi  r9, 1                     ; 0x100: next byte
        li    r4, 0x21
        ldhi  r4, 0x10                  ; polynomial 0x1021
        li    r6, 9                     ; bytes left
byte:   xor   r1, r7
        li    r3, 8
bit:    mov   r5, r1                    ; old top bit decides the xor
        shl   r1
        skip  nneg, r5
        xor   r1, r4
        sub   r3, 1
        skip  z, r3
        jmp   bit
        add   r7, r9
        sub   r6, 1
        skip  z, r6
        jmp   byte
        li    r8, CRC
        st    r1, [r8]
        li    r8, FLAG
        li    r2, 1
        st    r2, [r8]
done2:  jmp   done2
