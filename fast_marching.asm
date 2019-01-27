; (c) 2018-2019 Veikko Sariola
; O(N) Fast Marching Method in C64
;
; Original Fast Marching Method which runs in O(N log N) time was developed by
; Sethian (N = number of cells visited). The log N comes from the fact that
; cells are kept in a priority queue. Yatsiv, Bartesaghi and Sapiro proposed
; keeping the cells in a finite number of bins. In each bin, all cells have
; their priorities close to each other. When dequeuing, we take a cell from the
; lowest priority bin.
; 
; Here we take this idea slightly further, in that when we accept the cell, the
; assigned arrival time is the rounded, bin value. The implications of this
; rounding are not fully explored, but it seems to work :) I assume that on
; average, these rounding errors tend to cancel out.
;
; Long story short, we have blazing fast FMM using 8-bit integer math. On C64.
; 
; Quick how to use:
;
; FMM_WIDTH = 40
; FMM_HEIGHT = 25
;       ; needs to be called only firsttime:
;       LDA #16                   ; callback should now return < 16
;       JSR list_init
;       ; ...
;       ; needs to be called every time the input & output are changed
;       fmm_setinput map          ; map is a FMM_WIDTH * FMM_HEIGHT array
;       fmm_setoutput time        ; time is a FMM_WIDTH * FMM_HEIGHT array
;       fmm_setcallback callback  ; callback returns the slowness for a cell    
;       ; ...
;       ; needs to be called everytime seeds are changed and the algo reruns      
;       JSR fmm_reset            
;       LDX #<START_LOC           ; START_LOC is the index FMM_WIDTH*y + x 
;       LDY #>START_LOC           ; of the seed
;       JSR fmm_seed
;       JSR fmm_run
;  
; Tips:
;   - The maximum value for FMM_WIDTH is 63 (4*FMM_WIDTH+2 < 256)
;   - The maximum value for FAR_TIME is 255 - maximum value returned by callback
;   - The callback is responsible for bounds checking i.e. that ZP_INPUT_VEC
;     is within the bounds of the map. If it fails to do that, fmm_run will
;     likely overwrite some / all of the memory... However, it is usually
;     fastest to pad your map with cells that have infinite slowness i.e. are 
;     not considered at all, preventing fmm_run from 'leaking'. It is enough
;     to pad one row above, one row below, and one column between the rows,
;     because the map wraps so one column is enough to prevent wrapping in x
;   - map and time should be page aligned!
;
; How to implement the callback function:
;   - callback function is responsible for defining the norm and how the
;     map values are converted into slowness values.
;   - Callback is the most ritical section of the code, so optimizing it will
;     make the algorithm run faster.
;   - Callback should return with JMP fmm_continue, if the cell is considered,
;     or with RTS, if the cell should not be considered at all
;   - Callback should take two parameters: y, which is the index of the cell
;     considered, and x, which is the relative arrival times of the vertical
;     and horizontal cells. It returns the relative arrival time (compared to
;     the smallest arrival times of neighbours) in register A
;   - callback should keep Y-register unchanged!
;
; Callback examples:
;
; ; This callback approximates L2-norm, where one map cell is 15 units long
; callback      LDA (ZP_INPUT_VEC),y  ; loads the map cell
;               CMP #$66              ; in this map, $66 denotes empty space
;               BEQ @notwall
;               RTS                   ; was a wall, no need to consider at all
; @notwall      CPX #11               ; the lookup table is 11 cells long
;               BCS @maxedout
;               LDA lookup,x
;               JMP fmm_continue
; @maxedout     LDA #15               ; what is the value after the lookup table
;               JMP fmm_continue
; lookup        byte 11,11,12,12,12,13,13,14,14,14,14
; ; the lookup table is generated with (x+sqrt(2*15*15-x*x))/2. Replace 15
; ; with length of your map cells. This equation follows from solving
; ; u_x^2 + u_y^2 = 1/F^2, u_x = (u-a)/h, u_y = (u-b)/h where a and b are the
; ; smaller of the horizontal and vertical neighbours, respectively. Setting
; ; c = h/F so we get (u-a)^2 + (u-b)^2 = c^2. Without loss of generality we can
; ; assume b >= a and thus b = a+d. Solve for u (choosing the positive root) to
; ; get u = a + (d+sqrt(2*c^2-d^2))/2
; ; As usual, this first order approximation scheme is accurate (except the for
; ; rounding errors) for straight interfaces. For example, consider:
; ;   0 ? ?    0 11  ?    0 11 22
; ;   # 0 ? -> #  0 11 -> #  0 11
; ;   # # 0    #  #  0    #  #  0
; ; We see that 22 is very close to 15 * sqrt(2) = 21.213
; ; However, extremely curved interface is the point source, where we have
; ;   ? ?    15  ?    15 26
; ;   0 ? ->  0 15 -> 0  15
; ; 26 is not very close to 15 * sqrt(2) = 21.213
; ;
; ; This callback implements L1-norm, where one map cell is 1 units long
; callback      LDA (ZP_INPUT_VEC),y  ; loads the map cell
;               CMP #$66              ; in this map, $66 denotes empty space
;               BEQ @notwall
;               RTS                   ; was a wall, no need to consider at all
; @notwall      LDA #1
;               JMP fmm_continue
;
; ; This callback implements Linfinity-norm; one map cell is 1 units long
; callback      LDA (ZP_INPUT_VEC),y  ; loads the map cell
;               CMP #$66              ; in this map, $66 denotes empty space
;               BEQ @notwall
;               RTS                   ; was a wall, no need to consider at all
; @notwall      TXA
;               BEQ @cont
;               LDA #1
; @cont         JMP fmm_continue


; Temporary zero page registers used internally by fmm_run. Can be safely used
; when fmm_run is not running. 
ZP_BACKPTR_VEC = $FB   ; word
ZP_OUTPUT_VEC = $FD ; word
ZP_INPUT_VEC = $F9  ; word
ZP_ATIME_1 = $F8    ; byte
ZP_ATIME_2 = $F7    ; byte

; All values in the time array will be <= FAR_TIME, except never considered
; cells that are 255. Limits how far the algorithm will expand the boundary,
; decreasing makes the algorithm faster
FAR_TIME = 240

; FMM_WIDTH and FMM_HEIGHT should be defined by the user
_FMM_X_2_Y_3 = 2+3*FMM_WIDTH 
_FMM_X_3_Y_2 = 3+2*FMM_WIDTH 
_FMM_X_2_Y_2 = 2+2*FMM_WIDTH
_FMM_X_1_Y_2 = 1+2*FMM_WIDTH
_FMM_X_0_Y_2 = 0+2*FMM_WIDTH
_FMM_X_2_Y_1 = 2+1*FMM_WIDTH
_FMM_X_1_Y_1 = 1+1*FMM_WIDTH
_FMM_SIZE = FMM_WIDTH * FMM_HEIGHT
_FMM_SIZE_MINUS_1 = FMM_WIDTH * FMM_HEIGHT - 1

watch fmm_backptr
watch ZP_BACKPTR_VEC
watch ZP_OUTPUT_VEC
watch ZP_INPUT_VEC
watch ZP_ATIME_1
watch ZP_ATIME_2

;-------------------------------------------------------------------------------
; macro fmm_setinput address
;       Sets the input (i.e. map) to be read from address. Uses only the MSB of
;       the address, because assumes that address is page aligned.
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setinput
                LDA #>/1 - fmm_backptr
                STA _fmm_pshiftin+1
                endm

;-------------------------------------------------------------------------------
; macro fmm_setoutput address
;       Sets the output (i.e. array of arrival times) to address. Uses only the
;       MSB of the address, because assumes that address is page aligned.
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setoutput   
                LDA #>/1 + _FMM_SIZE_MINUS_1 
                STA _fmm_resetpage+1
                LDA #>/1
                SEC
                SBC #>fmm_backptr
                STA _fmm_pshiftout+1
                endm

;-------------------------------------------------------------------------------
; macro fmm_setcallback address
;       Sets the callback function to address. Call back function reads the
;       input map and 'returns' (more about that in the tips above) the
;       slowness of the cell
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setcallback
                LDA #</1
                STA _fmm_callback+1
                LDA #>/1
                STA _fmm_callback+2
                endm

;-------------------------------------------------------------------------------
; fmm_reset()
;       Resets the fast marching method, should be called before each run of the
;       algorithm. Clears the output array with 255 and resets the internally
;       used priority list.
; Parameters: none
; Touches: A,X,Y,ZP_OUTPUT_VEC
;-------------------------------------------------------------------------------
fmm_reset       LDY #0 ; low address byte = 0, because we assume page align
                STY ZP_OUTPUT_VEC
_fmm_resetpage  LDX #42 ; mutated
                STX ZP_OUTPUT_VEC+1        
                LDA #255   
                LDX #>_FMM_SIZE_MINUS_1
                LDY #<_FMM_SIZE_MINUS_1
@loop           STA (ZP_OUTPUT_VEC),y 
                DEY
                BNE @loop
                STA (ZP_OUTPUT_VEC),y 
                DEY
                DEC ZP_OUTPUT_VEC+1
                DEX
                BPL @loop
                JMP pri_reset ; tail call into pri_reset

;-------------------------------------------------------------------------------
; fmm_seed(X,Y)
;       Seeds the fast marching method
; Parameters:
;       X = low byte of the cell index
;       Y = high byte of the cell index
; Touches: A, X, Y
;-------------------------------------------------------------------------------
fmm_seed        TYA
                CLC
                ADC #>fmm_backptr ; we shift the high byte to point to the
                TAY                ; fmm_backptr array. Low byte not needed
                LDA #0             ; as we assume that fmm_backptr is aligned
                JMP pri_set ; tail call to set the priority of the cell        

;-------------------------------------------------------------------------------
; fmm_run()
;       Runs the algorithm (reset and seeds should've been called before). Once
;       the algorithm is complete, the output table will contain arrival times
;       (distance), starting from the seeds.
; Paramters: none
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
fmm_run         JSR pri_dequeue ; A = priority, X = heap lo, Y = heap hi
                BCS fmm_return  ; priority list was empty, exit
                PHA ; push priority to stack
                TXA ; NOTICE! carry is cleared so that...
                SBC #_FMM_X_1_Y_2 ; ... this shifts two rows and two cols
                STA ZP_BACKPTR_VEC
                STA ZP_OUTPUT_VEC
                STA ZP_INPUT_VEC
                TYA
                SBC #0  ;
                STA ZP_BACKPTR_VEC+1 ; ZP_TMP_A points to fmm_backptr[x-2,y-2]
                CLC
_fmm_pshiftout  ADC #42 ; mutated code so user can choose where to put output
                STA ZP_OUTPUT_VEC+1 ; ZP_TMP_B points now to arrival times
                LDA ZP_BACKPTR_VEC+1
                CLC
_fmm_pshiftin   ADC #42 ; mutated code so user can choose where to get input
                STA ZP_INPUT_VEC+1
                PLA
                LDY #_FMM_X_2_Y_2
                STA (ZP_OUTPUT_VEC),y ; store the priority into the arrival time
                LDY #_FMM_X_1_Y_2   ; consider the cell on the left
                JSR _fmm_consider
                LDY #_FMM_X_3_Y_2   ; consider the cell on the right
                JSR _fmm_consider
                LDY #_FMM_X_2_Y_1   ; consider the cell below
                JSR _fmm_consider
                LDY #_FMM_X_2_Y_3   ; consider cell above
                JSR _fmm_consider
                JMP fmm_run
fmm_return      RTS

;-------------------------------------------------------------------------------
; _fmm_consider(Y)
;       This is a private method for the FMM. This considers a cell neigboring
;       a just-accepted cell. If the new cell is already accepted, this returns
;       immediately. Otherwise, it computes the arrival time using the callback
;       function and inserts the new cell to the priority queue. Notice that if
;       we ever consider a new cell twice before it is accepted, the second time
;       it is considered its priority can only be lower. So we can just set the
;       priority of the cell; priority_list.asm will check if the new cell is 
;       already in the queue and move it from its current location
; Parameters:
;       Y: index of the cell to be considered, relative to ZP_TMP_* vectors
; Touches: A, X, Y, ZP_ATIME_1, ZP_ATIME_2
;-------------------------------------------------------------------------------
_fmm_consider   LDA (ZP_OUTPUT_VEC),y
                CMP #FAR_TIME+1
                BCC fmm_return ; this cell has already been accepted
                DEY  ; shift one left
                LDA (ZP_OUTPUT_VEC),y
                STA ZP_ATIME_1
                INY  ; shift two right
                INY
                LDA (ZP_OUTPUT_VEC),y
                CMP ZP_ATIME_1
                BCS @left_le_right
                STA ZP_ATIME_1 ; ATIME_1 is smaller of the horizontal times
@left_le_right  TYA 
                SEC
                SBC #_FMM_X_1_Y_1 ; shift left and down
                TAY
                LDA (ZP_OUTPUT_VEC),y
                STA ZP_ATIME_2
                TYA    
                ADC #_FMM_X_0_Y_2-1; shift two rows up, note that carry is set
                TAY
                LDA (ZP_OUTPUT_VEC),y
                CMP ZP_ATIME_2
                BCS @bottom_le_top
                STA ZP_ATIME_2 ; ATIME_2 is smaller of the vertical times
@bottom_le_top  LDA ZP_ATIME_2
                SEC
                SBC ZP_ATIME_1
                BCS @ispositive
                EOR #$FF ; A = 255-A
                ADC #1 ; carry is guaranteeed to be clear so add 1
                LDX ZP_ATIME_2
                STX ZP_ATIME_1
@ispositive     TAX  ; X is now the relative arrive time of the two cells
                TYA       ; y still is the cell index
                SEC
                SBC #FMM_WIDTH   ; shift one down = go back to the center
                TAY
_fmm_callback   JMP $4242 ; mutated to allow the user change the callback
fmm_continue
@pushto_queue   CLC
                ADC ZP_ATIME_1 ; add relative time to smaller arrival time
                CMP #FAR_TIME+1
                BCS fmm_return ; the new time is > FAR_TIME so stop now
                STA ZP_ATIME_1 ; ATIME_1 is now the new arrival time
                TYA              ; A = relative index to the cell
                ADC ZP_BACKPTR_VEC ; add A to the low address, carry not set
                TAX  ; X = low address
                LDA #0
                ADC ZP_BACKPTR_VEC+1
                TAY ; Y = high address 
                LDA ZP_ATIME_1 ; A = priority
                JMP pri_set ; tail call to setting priority

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
Align
fmm_backptr     dcb _FMM_SIZE,255



