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
;       ; needs to be called only first time:
;       JSR fmm_init
;       ; ...
;       ; needs to be called every time the input & output are changed
;       fmm_setinput map          ; map is a FMM_WIDTH * FMM_HEIGHT array
;       fmm_setoutput time        ; time is a FMM_WIDTH * FMM_HEIGHT array
;       fmm_setcallback callback  ; callback returns the slowness for a cell    
;       ; ...
;       ; needs to be called everytime before the algo reruns      
;       JSR fmm_reset            
;       LDX #<START_LOC           ; START_LOC is the index FMM_WIDTH*y + x 
;       LDY #>START_LOC           ; of the seed
;       JSR fmm_seed
;       JSR fmm_run
;  
; Tips:
;   - The maximum value for FMM_WIDTH is 63
;   - FAR_TIME determines how far the algorithm expands the boundary.
;     The maximum value for FAR_TIME is 255 minus the maximum value returned by
;     callback. If the maximum number you return is 15, then FAR_TIME has to be
;     240 or less.
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
;   - Callback is the most critical section of the code, so optimizing it will
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
ZP_OUTPUT_VEC = $FD ; word
ZP_INPUT_VEC = $02 ; word
ZP_CUR_LIST = $04 ; byte
ZP_CUR_TIME = $05

watch ZP_OUTPUT_VEC
watch ZP_INPUT_VEC

; All values in the output array will be <= FAR_TIME, except never considered
; cells that are 255. Limits how far the algorithm will expand the boundary,
; decreasing makes the algorithm faster. The list shall always contain only
; elements with priority <= FAR_TIME
; Note that FAR_TIME+maximum value returned by callback should always < 256
FAR_TIME = 240

; Your callback function should always return a value < NUM_LISTS. Furthermore,
; NUM_LISTS should be a power of 2
NUM_LISTS = 16
NUM_LISTS_MINUS_1 = NUM_LISTS-1

; FMM_WIDTH and FMM_HEIGHT should be defined by the user
_FMM_X_2_Y_3 = 2+3*FMM_WIDTH 
_FMM_X_3_Y_2 = 3+2*FMM_WIDTH 
_FMM_X_2_Y_2 = 2+2*FMM_WIDTH
_FMM_X_1_Y_2 = 1+2*FMM_WIDTH
_FMM_X_2_Y_1 = 2+1*FMM_WIDTH
_FMM_X_1_Y_1 = 2+1*FMM_WIDTH
_FMM_SIZE = FMM_WIDTH * FMM_HEIGHT
_FMM_SIZE_MINUS_1 = FMM_WIDTH * FMM_HEIGHT - 1


_fmm_head = 0
_fmm_lo = NUM_LISTS
_fmm_hi = _fmm_lo + 256
_fmm_next = _fmm_hi + 256

;-------------------------------------------------------------------------------
; macro fmm_setio input output
;       Sets the shift between the input and the output. Uses only the MSB of
;       the address, because assumes that addresses are aligned.
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setio
                LDA #>/1 - /2
                STA _fmm_shift+1
                LDA #>/2
                STA _fmm_outputpage
                endm

;-------------------------------------------------------------------------------
; macro fmm_setcallback address
;       Sets the callback function for considering straight cells. Callback
;       function reads the input map and 'returns' (more about that in the tips
;       above) the slowness of the cell
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setcallback
                LDA #</1
                STA _fmm_callback+1
                LDA #>/1
                STA _fmm_callback+2
                endm

;------------------------------
; fmm_init()
; 
; Initializes the linked lists.
; 
; TBW
;
; Parameters: none
; Touches: A, X
;------------------------------       
fmm_init        LDX #NUM_LISTS-1
                LDA #0
@loop_heads     STA fmm_head,x
                DEX
                BPL @loop_heads
                LDX #0
@loop_nexts     TXA
                DEX
                STA fmm_head,x
                BNE @loop_nexts
                RTS 

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
_fmm_outputpage=*+1  
                LDX #42 ; mutated
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
                LDA #0
                STA ZP_CUR_TIME
                RTS    

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
                ADC _fmm_outputpage ; we shift the high byte to point to the
                STA ZP_OUTPUT_VEC+1
                TXA
                STA ZP_OUTPUT_VEC
                LDA #0             ; as we assume that fmm_backptr is aligned
                LDY #0
                PHA
                ;JMP _fmm_set_prior ; tail call to set the priority of the cell    

;-------------------------------------------------------------------------------
; Internally used, reset the fmm_curtime = 0, should be near the branch
;-------------------------------------------------------------------------------
_fmm_cleanup    LDA #0
                STA ZP_CUR_TIME
                RTS

;-------------------------------------------------------------------------------
; fmm_run()
;       Runs the algorithm (reset and seeds should've been called before). Once
;       the algorithm is complete, the output table will contain arrival times
;       (distance), starting from the seeds.
; Paramters: none
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
fmm_run         LDX ZP_CUR_LIST
                LDY fmm_head,x
                BEQ _fmm_advance ; if the head is a null pointer, skip
                LDA fmm_next,y
                STA fmm_head,x ; set head to point to the next element
                LDA fmm_lo,y
                STA ZP_OUTPUT_VEC
                STA ZP_INPUT_VEC
                LDA fmm_hi,y
                STA ZP_OUTPUT_VEC+1 ; no need to check if it's already accepted
                LDY #_FMM_X_2_Y_2
                LDA #249
                CMP (ZP_OUTPUT_VEC),y
                BCC fmm_run ; already accepted
                LDA ZP_OUTPUT_VEC+1
_fmm_shift      ADC #42 ; mutated code so user choose output, carry is set
                STA ZP_INPUT_VEC+1 ; ZP_TMP_B points now to arrival times
                LDA ZP_CUR_TIME
                STA (ZP_OUTPUT_VEC),y ; store the priority into the arrival time
                JSR _fmm_cons_left
                JSR _fmm_cons_right
                JSR _fmm_cons_up
                JSR _fmm_cons_down
                JMP fmm_run
_fmm_advance    LDA ZP_CUR_TIME
                CLC
                ADC #1
                CMP FAR_TIME
                BCC _fmm_return
                AND #NUM_LISTS-1
                STA ZP_CUR_LIST
                JMP fmm_run
_fmm_return     RTS

;-------------------------------------------------------------------------------
; TBW
;-------------------------------------------------------------------------------
fmm_continue    CLC
                ADC ZP_CUR_TIME ; add relative time to larger arrival time
                CMP #FAR_TIME+1
                BCS @end; the new time is > FAR_TIME so stop now
                LDX fmm_next
                BEQ @end ; out of empty cells
                AND #NUM_LISTS-1 ; the list head is priority & (NUM_LISTS-1)
                TAY
                LDA fmm_head,y ; a: the current follower of x
                STA fmm_next,x; empty list points now to current follower
                TXA
                STA fmm_head,y         
@end            RTS

;-------------------------------------------------------------------------------
; macro _fmm_consider /1
;       This is a private method for the FMM. This considers a cell neigboring
;       a just-accepted cell. If the new cell is already accepted, this returns
;       immediately. Otherwise, it computes the arrival time using the callback
;       function and inserts the new cell to the priority queue. Notice that if
;       we ever consider a new cell twice before it is accepted, the second time
;       it is considered its priority can only be lower. So we can just set the
;       priority of the cell and check if the new cell is already in the lists
;       and move it from its current location
; Parameters:
;       /1: index of the cell to be considered, relative to ZP_* vectors
; Touches: A, X, Y, ZP_TEMP
;-------------------------------------------------------------------------------
defm            _fmm_consider_horz
                LDY #/1 ; center cell
                LDA (ZP_OUTPUT_VEC),y
                CMP #253 ; 251 = left, 252 = right, 253 = down, 254 = up
                BCC @end ; this cell has already been accepted
                CMP #255 ; never considered before
                BNE @diag
                LDA #/2
                STA (ZP_OUTPUT_VEC),y
                LDX #NUM_LISTS-1
                JMP _fmm_callback
@diag           CMP #254
                BEQ @up
@down           LDY #/1+FMM_WIDTH
                byte $2C ; BIT absolute, skips the next 2 bytes
@up             LDY #/1-FMM_WIDTH
@cont           LDA ZP_CUR_TIME
                SEC
                SBC (ZP_OUTPUT_VEC),y
                TAX
                LDY #/1
                LDA #250
                STA (ZP_OUTPUT_VEC),y
                JMP _fmm_callback
@end            RTS
                endm

defm            _fmm_consider_vert
                LDY #/1 ; center cell
                LDA (ZP_OUTPUT_VEC),y
                CMP #251 ; 251 = left, 252 = right, 253 = down, 254 = up
                BCC @end ; this cell has already been accepted
                CMP #253 ; never considered before
                BCC @diag
                CMP #255 ; never considered before
                BCC @end
                LDA #/2
                STA (ZP_OUTPUT_VEC),y
                LDX #NUM_LISTS-1
                JMP _fmm_callback     
@diag           CMP #252
                BEQ @right
@left           LDY #/1+1
                byte $2C ; BIT absolute, skips the next 2 bytes
@right          LDY #/1-1
@cont           LDA ZP_CUR_TIME
                SEC
                SBC (ZP_OUTPUT_VEC),y
                TAX
                LDY #/1
                LDA #250
                STA (ZP_OUTPUT_VEC),y
                JMP _fmm_callback
@end            RTS
                endm

_fmm_cons_left  _fmm_consider_horz _FMM_X_1_Y_2,251
_fmm_cons_right _fmm_consider_horz _FMM_X_3_Y_2,252
_fmm_cons_up    _fmm_consider_vert _FMM_X_2_Y_3,254
_fmm_cons_down  _fmm_consider_vert _FMM_X_2_Y_1,253

_fmm_callback   JMP $4242 ; mutated to allow the user change the callback

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
fmm_head   dcb NUM_LISTS,0
fmm_lo     dcb 256,0
fmm_hi     dcb 256,0       ; list of pointers to the output
fmm_next   dcb 256,0

watch fmm_head
watch fmm_lo
watch fmm_hi
watch fmm_next

