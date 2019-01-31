FMM_WIDTH = 40;
FMM_HEIGHT = 25;

START_LOC = 10+FMM_WIDTH*10 ; $01EF
START_LOC2 = 22+32*15 ; $01F6
screen_mem = $0400

; 10 SYS4096

* = $1900
incasm "fast_marching.asm"

* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00


* = $1000       
                fmm_setinput map
                fmm_setoutput screen_mem
                fmm_setcallback callback
                LDA #16
                JSR fmm_init
                JSR fmm_reset
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed
                LDX #<START_LOC2
                LDY #>START_LOC2
                JSR fmm_seed
                
                JSR fmm_run
@loop           JMP @loop
                
  
        
; callbacks shouldn't touch ys
; callback get X, which is the relative distance between the two cells
callback        LDA (ZP_INPUT_VEC),y ; this loads the 
                CMP #32
                BEQ @notwall
                RTS  ; ... so we don't have to consider this cell at all
@notwall        CPX #15
                BCS @maxedout
                LDA lookup,x
                JMP fmm_continue
@maxedout       LDA #15
                JMP fmm_continue

Align
time            dcb 1000,FAR_TIME

Align
map     BYTE    $23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23
        BYTE    $23,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$23,$23,$23,$23,$23,$20,$23,$23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$20,$20,$20,$20,$20,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$20,$23,$23,$23,$23,$23,$23,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$23,$23,$23,$23,$20,$23,$23,$23,$20,$23,$20,$20,$20,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$23
        BYTE    $23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23,$23


lookup          byte 11,11,12,12,12,13,13,14,14,14,14,15,15,15,15,15