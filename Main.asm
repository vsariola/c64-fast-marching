START_LOC = 2+32*1 ; $01EF
START_LOC2 = 22+32*15 ; 
START_LOC3 = 15+32*20 ; 
screen_mem = $0400
ZP_TMP_1 = $F5
ZP_TMP_2 = $F3

; 10 SYS4096

* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00


* = $1000       
                fmm_setinput map
                fmm_setoutput time
                fmm_setcallback callback
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed
                LDX #<START_LOC2
                LDY #>START_LOC2
                JSR fmm_seed
                
                JSR fmm_run


                JSR dumpscreen
@loop           JMP @loop
                
       
        
; callbacks shouldn't touch ys
; callback get X, which is the relative distance between the two cells
callback        LDA (ZP_INPUT_VEC),y ; this loads the 
                BEQ @notwall ; if there's 1 in the map, it's a wall...
                RTS  ; ... so we don't have to consider this cell at all
@notwall        CPX #15
                BCS @maxedout
                LDA lookup,x
                JMP fmm_continue
@maxedout       LDA #15
                JMP fmm_continue



dumpscreen      LDA #<time-1
                STA ZP_TMP_1
                LDA #>time-1
                STA ZP_TMP_1+1
                LDA #<screen_mem-1
                STA ZP_TMP_2
                LDA #>screen_mem-1
                STA ZP_TMP_2+1
                LDY #32
                LDX #25
@loop           LDA (ZP_TMP_1),y
                STA (ZP_TMP_2),y
                DEY
                BNE @loop
                LDY #32
                LDA ZP_TMP_1
                CLC
                ADC #32
                STA ZP_TMP_1
                LDA ZP_TMP_1+1
                ADC #0
                STA ZP_TMP_1+1
                LDA ZP_TMP_2
                CLC
                ADC #40
                STA ZP_TMP_2
                LDA ZP_TMP_2+1
                ADC #0
                STA ZP_TMP_2+1
                DEX
                BNE @loop
                RTS

Align
time            dcb 1024,FAR_TIME

map             dcb 32,1
                byte 0,1,0,0,0,0,0,0,0,0
                dcb 22,0
                byte 0,1,0,1,1,1,1,1,1,0
                dcb 22,0
                byte 0,1,0,1,0,0,0,0,1,0
                dcb 22,0
                byte 0,1,0,1,0,0,0,0,1,0
                dcb 22,0
                byte 0,0,0,1,0,0,0,0,1,0
                dcb 22,0
                byte 0,1,0,1,0,0,0,0,1,0
                dcb 22,0
                byte 0,1,0,1,0,0,0,0,0,0
                dcb 22,0
                byte 0,1,0,0,0,0,0,0,0,0
                dcb 22,0
                dcb 22*32,0
                dcb 32,1

lookup          byte 11,11,12,12,12,13,13,14,14,14,14,15,15,15,15,15