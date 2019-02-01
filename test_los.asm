FMM_WIDTH = 40
FMM_HEIGHT = 25
FMM_SIZE_MINUS_1 = _FMM_SIZE-1

START_LOC = 11+FMM_WIDTH*10 ; $01EF
SCREEN_MEM = $0400
COLOR_MEM = $D800

ZP_1      = $05
ZP_2      = $07
ZP_SCREEN = $09
ZP_COLOR  = $11
ZP_MAP    = $13

watch time1
watch time2
watch map
watch ZP_1
watch ZP_2
watch ZP_SCREEN
watch ZP_COLOR
watch ZP_MAP

* = $2100
incasm "fast_marching.asm"

* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00


* = $1000       
                LDA #0
                STA $D020 ; border black
                LDA #0
                STA $D021 ; background black
                JSR fmm_init
@loop           fmm_setinput map
                fmm_setoutput time1
                fmm_setcallback callback1
                JSR fmm_reset
                LDX coord_lo
                LDY coord_hi
                JSR fmm_seed
                JSR fmm_run
                fmm_setoutput time2
                fmm_setcallback callback2
                JSR fmm_reset
                LDX coord_lo
                LDY coord_hi
                JSR fmm_seed
                JSR fmm_run
                JSR draw
                JSR read_joystick
                JMP @loop
                
read_joystick   LDX #_FMM_X_2_Y_2
                LDA #%0001
                BIT $DC01
                BNE @not_up
                LDX #_FMM_X_2_Y_1
@not_up         LDA #%0010
                BIT $DC01
                BNE @not_down
                LDX #_FMM_X_2_Y_3
@not_down       LDA #%0100
                BIT $DC01
                BNE @not_left
                DEX
@not_left       LDA #%1000
                BIT $DC01
                BNE @not_right
                INX
@not_right      TXA
                CLC
                ADC coord_lo
                STA coord_lo
                LDA #0
                ADC coord_hi
                STA coord_hi
                SEC
                LDA coord_lo
                SBC #_FMM_X_2_Y_2
                STA coord_lo
                LDA coord_hi
                SBC #0
                STA coord_hi
                RTS

draw            LDA #0
                STA ZP_1
                STA ZP_2
                STA ZP_SCREEN
                STA ZP_COLOR
                STA ZP_MAP
                LDA #>time1+FMM_SIZE_MINUS_1
                STA ZP_1+1
                LDA #>time2+FMM_SIZE_MINUS_1
                STA ZP_2+1
                LDA #>SCREEN_MEM+FMM_SIZE_MINUS_1
                STA ZP_SCREEN+1
                LDA #>COLOR_MEM+FMM_SIZE_MINUS_1
                STA ZP_COLOR+1
                LDA #>map+FMM_SIZE_MINUS_1
                STA ZP_MAP+1
                LDY #<FMM_SIZE_MINUS_1
                LDX #>FMM_SIZE_MINUS_1
@copyloop       TXA
                PHA
                LDA (ZP_1),y
                SEC
                SBC (ZP_2),y
                CMP #5
                BCS @dark
                LDA (ZP_1),y
                LSR
                LSR
                LSR
                LSR
                CMP #15
                BCS @dark
                TAX
                LDA color_gradient,x
                JMP @setcolor
@dark           LDA color_gradient+14
@setcolor       STA (ZP_COLOR),y
                LDA (ZP_MAP),y
                STA (ZP_SCREEN),y          
                PLA
                TAX
                DEY
                CPY #255
                BNE @copyloop
                DEX
                DEC ZP_1+1
                DEC ZP_2+1
                DEC ZP_SCREEN+1
                DEC ZP_COLOR+1
                DEC ZP_MAP+1
                CPX #255
                BNE @copyloop
                RTS

; callbacks shouldn't touch ys
; callback get X, which is the relative distance between the two cells
callback1       LDA (ZP_INPUT_VEC),y ; this loads the 
                CMP #$66
                BEQ @notwall
                RTS  ; ... so we don't have to consider this cell at all
@notwall        CPX #11
                BCS @maxedout
                LDA lookup,x
                JMP fmm_continue
@maxedout       LDA #15
                JMP fmm_continue

callback2       LDA (ZP_INPUT_VEC),y ; this loads the 
                CMP #$A0
                BNE @notwall2
                RTS  ; ... so we don't have to consider this cell at all
@notwall2       CPX #11
                BCS @maxedout2
                LDA lookup,x
                JMP fmm_continue
@maxedout2      LDA #15
                JMP fmm_continue

coord_lo        byte <START_LOC
coord_hi        byte >START_LOC

Align
time1           dcb 1000,FAR_TIME

Align
time2           dcb 1000,FAR_TIME


Align
map     BYTE    $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
        BYTE    $A0,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$23,$23,$23,$23,$23,$66,$23,$23,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$66,$66,$66,$66,$66,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$66,$23,$23,$23,$23,$23,$23,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$23,$23,$23,$23,$66,$23,$23,$23,$66,$23,$66,$66,$66,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$23,$23,$23,$23,$23,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$A0
        BYTE    $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0




lookup          byte 11,11,12,12,12,13,13,14,14,14,14

color_gradient  byte 1,1,13,13,13,12,12,12,12,8,8,8,8,8,9