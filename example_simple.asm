FMM_WIDTH = 40   ; the width of the grid is 40 cells
FMM_HEIGHT = 25  ; the height of the grid is 25 cells

START_LOC = 10 + FMM_WIDTH*10        ; algorithm will start from coordinates X = 10, Y = 10
screen_mem = $0400  ; we'll output the arrival times directly to screen memory for quick visualization

* = $1900
incasm "fast_marching.asm"

; 10 SYS4096
* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00

* = $1000       
                fmm_setmaps map,screen_mem  ; map is the input, screen_mem is the output
                fmm_setcallback callback    ; set the callback that translates the map values into f values
                JSR fmm_reset               ; resets the internal arrays and output array
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed                ; algorithm starts from X = 10, Y = 10               
                JSR fmm_run                 ; run the algorithm
@loop           JMP @loop
                       
callback        LDA (fmm_zp_input),y ; read the map
                CMP #32              ; in this map, 32 is empty, everything else is wall
                BNE @wall
@do_lookup      LDA lookup,x         ; return the slowness of the cell
                fmm_inlinecontinue   ; this is a macro
@wall           RTS                  ; was a wall, return and skip the cell
lookup          byte 11,10,10,9,8,8,7,7,6,5,4,4,3,2,1,0,15

Align
map             dcb 40,0    ; this is a minimal map that has the top and bottom 
                dcb 920,32  ; edges with walls to prevent the algorithm from 
                dcb 40,0    ; happily overwriting the memory