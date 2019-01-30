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
ZP_TIME = $F8    ; byte
ZP_PRI_TEMP = $04
ZP_CIRC_TEMP = $03

; All values in the time array will be <= FAR_TIME, except never considered
; cells that are 255. Limits how far the algorithm will expand the boundary,
; decreasing makes the algorithm faster
FAR_TIME = 240

; the priority of the largest element should always be < smallest priority + 
; NUM_LISTS. Furthermore, NUM_LISTS should be a power of 2 (which makes
; mod(x,NUM_LISTS) possible using AND).
NUM_LISTS = 16

; the list shall always contain only elements with priority <= MAX_PRIORITY
MAX_PRIORITY = 240


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
watch ZP_TIME
watch pri_base
watch pri_hi
watch pri_lo
watch list_next
watch list_prev

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
@pri_reset      JSR pri_dequeue ; reset the priority list
                BCC @pri_reset
                LDA #0
                STA pri_base
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
                ADC #>fmm_backptr ; we shift the high byte to point to the
                STA ZP_PRI_TEMP+1  ; fmm_backptr array. Low byte not needed
                TXA
                STA ZP_PRI_TEMP
                LDA #0             ; as we assume that fmm_backptr is aligned
                JMP pri_set ; tail call to set the priority of the cell    

;-------------------------------------------------------------------------------
; Internally used return, should be near the branch
;-------------------------------------------------------------------------------
_fmm_return     RTS

;-------------------------------------------------------------------------------
; fmm_run()
;       Runs the algorithm (reset and seeds should've been called before). Once
;       the algorithm is complete, the output table will contain arrival times
;       (distance), starting from the seeds.
; Paramters: none
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
fmm_run         JSR pri_dequeue ; A = priority, X = heap lo, Y = heap hi
                BCS _fmm_return  ; priority list was empty, exit
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
                LDA pri_base
                LDY #_FMM_X_2_Y_2
                STA (ZP_OUTPUT_VEC),y ; store the priority into the arrival time
                _fmm_consider _FMM_X_1_Y_2
                _fmm_consider _FMM_X_3_Y_2
                _fmm_consider _FMM_X_2_Y_1
                _fmm_consider _FMM_X_2_Y_3
                JMP fmm_run

;-------------------------------------------------------------------------------
; macro _fmm_consider /1
;       This is a private method for the FMM. This considers a cell neigboring
;       a just-accepted cell. If the new cell is already accepted, this returns
;       immediately. Otherwise, it computes the arrival time using the callback
;       function and inserts the new cell to the priority queue. Notice that if
;       we ever consider a new cell twice before it is accepted, the second time
;       it is considered its priority can only be lower. So we can just set the
;       priority of the cell; priority_list.asm will check if the new cell is 
;       already in the queue and move it from its current location
; Parameters:
;       /1: index of the cell to be considered, relative to ZP_TMP_* vectors
; Touches: A, X, Y, ZP_TIME, ZP_ATIME_2
;-------------------------------------------------------------------------------
defm            _fmm_consider
                LDY #/1 ; center cell
                LDA (ZP_OUTPUT_VEC),y
                CMP #FAR_TIME+1
                BCC @end ; this cell has already been accepted
                LDY #/1-1  ; cell on the left
                LDA (ZP_OUTPUT_VEC),y
                STA ZP_TIME
                LDY #/1+1 ; cell on the right
                LDA (ZP_OUTPUT_VEC),y
                CMP ZP_TIME
                BCS @left_le_right
                STA ZP_TIME ; ATIME_1 is smaller of the horizontal times
@left_le_right  LDY #/1-FMM_WIDTH ; cell below
                LDA (ZP_OUTPUT_VEC),y
                LDY #/1+FMM_WIDTH ; cell above
                CMP (ZP_OUTPUT_VEC),y
                BCC @bottom_le_top
                LDA (ZP_OUTPUT_VEC),y ; A is smaller of the vertical times
@bottom_le_top  LDY #/1 ; center cell
                JSR _consider_tail
@end
                endm

_consider_tail  TAX ; the smaller of vertical vertical times is stored in X
                SEC
                SBC ZP_TIME
                BCS @ispositive
                EOR #$FF ; A = 255-A
                ADC #1 ; carry is guaranteeed to be clear so add 1
                STX ZP_TIME
@ispositive     TAX  ; X is now the relative arrive time of the two cells
_fmm_callback   JMP $4242 ; mutated to allow the user change the callback


_fmm_return2    RTS ; should be near the branch
fmm_continue
@pushto_queue   CLC
                ADC ZP_TIME ; add relative time to smaller arrival time
                CMP #FAR_TIME+1
                BCS _fmm_return2 ; the new time is > FAR_TIME so stop now
                TAX ; X = priority
                TYA              ; A = relative index to the cell
                ADC ZP_BACKPTR_VEC ; add A to the low address, carry not set
                STA ZP_PRI_TEMP   ; ZP_PRI_TEMP points to the back pointer
                LDA #0
                ADC ZP_BACKPTR_VEC+1
                STA ZP_PRI_TEMP+1
                TXA ; A = priority
;-------------------------------------------------------------------------------
; pri_set(A,X,Y)
;       Sets the priority of the cell in the address ptr = $YX to A. The ptr 
;       should point to the back pointer of the cell. Back pointer is a byte
;       containing the index of the cell in the circular list.
;
; pseudocode:
; if *ptr != 255
;    elem = *ptr // the element is already in the queue so only update its prio
; else
;    if the list of unused elements is not empty
;       elem = the element with the highest priority (found using loop)
;       *(ptrs[elem]) = 255 // we will replace the element with highest prio
;    else
;       elem = first unused element
;    end
;    *ptr = elem
;    ptrs[elem] = ptr
; end
; move elem as the first element of list priority & (NUM_LISTS-1)
; 
; 
; Parameters:
;       A = priority of the cell & (NUM_LISTS-1)
;       X = low byte of the memory address containing the back pointer
;       Y = high byte of the memoty address containing the back pointer
; Touches: A, X, Y
;-------------------------------------------------------------------------------
pri_set         AND #NUM_LISTS-1 ; the list head is priority & (NUM_LISTS-1)
                PHA   ; store the correct list head in stack
                LDY #0
                LDA (ZP_PRI_TEMP),y
                TAX
                CPX #255
                BNE @found_elem
                LDX list_next+255 ; find and element from the list of unused
                CPX #255          ; elements
                BEQ @reuse       ; if there's no unused elements, we jump

                TXA
                LDY #0
                STA (ZP_PRI_TEMP),y
                LDA ZP_PRI_TEMP ; ptrs[y] = ptr
                STA pri_lo,x ; note that list_move left X unchanged
                LDA ZP_PRI_TEMP+1
                STA pri_hi,x

                LDA list_next,x ; a: the current follower of x
                STA list_next+255 ; empty list points now to current follower
                JMP @list_insert
                
@reuse          LDA pri_base
@loop           SBC #0 ; carry is guaranteed to be cleared here 
                AND #NUM_LISTS-1
                TAY
                CMP list_next,y
                BEQ @loop
                LDX list_next,y
                LDA pri_lo,x
                STA @mutant3+1
                LDA pri_hi,x
                STA @mutant3+2
                LDA #255
@mutant3        STA $4242     
                LDY #0
                TXA 
                STA (ZP_PRI_TEMP),y  ; set the back pointer (*ptr = x)
                LDA ZP_PRI_TEMP ; set the forward  pointr (ptrs[x] = ptr)
                STA pri_lo,x ; note that list_move left X unchanged
                LDA ZP_PRI_TEMP+1
                STA pri_hi,x
@found_elem     STX ZP_CIRC_TEMP
                LDA list_next,x ; following lines link the next[x] and prev[x]
                LDY list_prev,x ; elements pointing to each other
                STA list_next,y
                TAX
                TYA
                STA list_prev,x ; the old list is now linked
                LDX ZP_CIRC_TEMP
@list_insert    PLA ; A: head, X: new
                STA list_prev,x ; prev[new] = head              
                TAY ; A: head, X: new, Y: head
                TXA ; A: new, X: new, Y: head
                LDX list_next,y ; A: new, X: old, Y: head
                STA list_next,y ; next[head] = new
                STA list_prev,x ; prev[old] = new
                TAY  ; A: new, X: old, Y: new
                TXA  ; A: old, X: old, Y: new
                STA list_next,y ; next[new] = old
                RTS


;-------------------------------------------------------------------------------
; pri_dequeue()
;       Dequeues and returns the element with the lowest priority.
; 
; Parameters: none
; Returns:
;       (you can get the priority by reading pri_base)
;       X = low address of the dequeued cell
;       Y = high address of the dequeued cell
;       carry: set if there are no more items
;-------------------------------------------------------------------------------
pri_dequeue     LDA pri_base
                CMP #MAX_PRIORITY+1
                BCS @done        ; beyond MAX priority, returning carry set 
                AND #NUM_LISTS-1 ; indicates no more items
                TAX
                CMP list_next,x
                BNE @found
                INC pri_base
                JMP pri_dequeue
@found          LDA list_next,x
                TAX
                LDA pri_lo,x  ; destroy the forward ptr
                STA @mutant5+1
                LDA pri_hi,x
                STA @mutant5+2
                LDA #255
@mutant5        STA $4242
                ; deleting an element from list
                TXA 
                PHA
                LDA list_next,x ; following lines link the next[x] and prev[x]
                LDY list_prev,x ; a: after, x: element, y: before
                STA list_next,y ; next[before] = after
                TAX ; a: after, x: after, y: before
                TYA ; a: before, x: after, y: before
                STA list_prev,x ; prev[after] = before
                PLA
                LDX list_next+255 ; A: elem, X: old, Y: before
                STA list_next+255 ; next[255] = elem
                TAY             ; A: elem, X: old, Y: elem
                TXA             ; A: old, X: old, Y: elem
                STA list_next,y ; next[elem] = old
                LDX @mutant5+1
                LDY @mutant5+2
                CLC  ; carry not set => we've got an item
@done           RTS

;------------------------------
; initializes the A empty lists + one circular list with all unused elements
; note that A should be < 128
; touches 
; For example, if A = 2, the pointers are initialized like this
; list_next[0] = 0, list_prev[0] = 0 <- this is an empty list
; list_next[1] = 1, list_prev[1] = 1 <- this is an empty list_init
; list_next[2] = 3, list_prev[2] = 255 <- rest of the elements are a circular
; list_next[3] = 4, list_prev[3] = 2      list of unused elements
;------------------------------       
list_init       TAX
                TAY              ; keep the input parameter in Y 
@loop1          TXA              ; this loop creates the empty lists
                STA list_next,x
                STA list_prev,x
                DEX
                BPL @loop1
                STY @mutatecmp+1
@loop2          TYA              ; this loop sets the list_prev values of the
                INY              ; circular list
                BEQ @loop3 
                STA list_prev,y
                JMP @loop2
@loop3          TYA              ; this loop set the list_next values of the
                DEY              ; circular list
                STA list_next,y
@mutatecmp      CPY #42          ; when looping backwards, we should end before
                BNE @loop3       ; we overwrite the empty lists
                LDA #255
                STA list_prev,y  ; finally, we connect the ends of the 
                TAX              ; circular list
                TYA 
                STA list_next,x
                RTS 

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
pri_base        byte 0          ; priority of the lowest element in the list
pri_hi          dcb 256,0       ; list of pointers to the backptr
pri_lo          dcb 256,0
list_next       dcb 256,0
list_prev       dcb 256,0

Align
fmm_backptr     dcb _FMM_SIZE,255



