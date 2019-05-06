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
;       ; needs to be called every time the input & output are changed
;       fmm_setmaps map,time      ; map & time are FMM_WIDTH * FMM_HEIGHT arrays
;       fmm_setcallback callback  ; callback returns the slowness for a cell    
;       ; ...
;       ; needs to be called everytime before the algo reruns, after setmaps     
;       JSR fmm_reset            
;       LDX #<START_LOC           ; START_LOC is the index FMM_WIDTH*y + x 
;       LDY #>START_LOC           ; of the seed
;       JSR fmm_seed
;       JSR fmm_run
;  
; Tips:
;   - The maximum value for FMM_WIDTH is 126
;   - Maximum arrival time is 249, inclusive
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
; @notwall      LDA lookup,x
;               JMP fmm_continue
; lookup        byte 11,10,10,9,8,8,7,7,6,5,4,4,3,2,1,0,15
; ; the first 16 elements of the lookup table are generated with
; ; sqrt(2*15*15-x*x))/2. The last element is the straight slowness Replace 15
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
; ; This lookup table implements L1-norm
; lookup          byte 0,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,15
;
; ; This lookup table implements Linfinity-norm
; lookup          byte 0,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,15

; Temporary zero page registers used internally by fmm_run. Can be safely used
; when fmm_run is not running. 
ZP_OUTPUT_VEC = $FD ; word
ZP_INPUT_VEC = $02 ; word
fmm_curtime = $04 ; byte
ZP_TEMP = $05 ; byte

watch ZP_OUTPUT_VEC
watch ZP_INPUT_VEC
watch fmm_curtime


NORTH = 255
SOUTH = 254
NEVER_CONSIDERED = 253
WEST = 252
EAST = 251
SOON_ACCEPTED = 250

; Your callback function should always return a value < MAX_SLOWNESS.
; Also, when X = MAX_SLOWNESS in the callback, the returned slowness should be
; the slowness when moving straight.
MAX_SLOWNESS = 16

; FMM_WIDTH and FMM_HEIGHT should be defined by the user

_FMM_X_0_Y_0 = 0+0*FMM_WIDTH
_FMM_X_0_Y_1 = 0+1*FMM_WIDTH
_FMM_X_0_Y_2 = 0+2*FMM_WIDTH
_FMM_X_1_Y_0 = 1+0*FMM_WIDTH
_FMM_X_1_Y_1 = 1+1*FMM_WIDTH
_FMM_X_1_Y_2 = 1+2*FMM_WIDTH
_FMM_X_2_Y_0 = 2+0*FMM_WIDTH
_FMM_X_2_Y_1 = 2+1*FMM_WIDTH
_FMM_X_2_Y_2 = 2+2*FMM_WIDTH

_FMM_SIZE = FMM_WIDTH * FMM_HEIGHT
_FMM_SIZE_MINUS_1 = FMM_WIDTH * FMM_HEIGHT - 1

;-------------------------------------------------------------------------------
; macro fmm_setmaps input output
;       Sets the input (i.e. map) to be read from input and writes the arrival
;       times to outtput. Uses only the MSB of the address, because assumes that
;       address is page aligned.
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setmaps
                LDA #>/2
                STA _fmm_seed_himut+1
                LDA #>/2+_FMM_SIZE_MINUS_1
                STA _fmm_resetpage+1
_fmm_setmaps_tmp/1/2 = >/1 - /2
                LDA #_fmm_setmaps_tmp/1/2 - 1
                STA _fmm_pshiftin+1
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
                STA _fmm_cb_1+1
                STA _fmm_cb_2+1
                STA _fmm_cb_3+1
                STA _fmm_cb_4+1
                LDA #>/1
                STA _fmm_cb_1+2
                STA _fmm_cb_2+2
                STA _fmm_cb_3+2
                STA _fmm_cb_4+2
                endm

;-------------------------------------------------------------------------------
; fmm_reset()
;       Resets the fast marching method, should be called before each run of the
;       algorithm. Clears the output array with 255 and resets the internally
;       used priority list.
; Parameters: none
; Touches: A,X,Y,ZP_OUTPUT_VEC
;-------------------------------------------------------------------------------  
fmm_reset       LDX #0 ;    for i in range(0,256):
@loop           LDA #0 
                STA fmm_list_head,x ;         list_head[i] = 0
                TXA             ; this loop creates the empty lists
                DEX
                STA fmm_list_next,x ; list_next[i] = (i+1) & 255
                BNE @loop              
                ;     for i in range(len(output)):
                ;         output[i] = NEVER_CONSIDERED
                LDY #0 ; low address byte = 0, because we assume page align
                STY ZP_OUTPUT_VEC
_fmm_resetpage  LDX #42 ; mutated
                STX ZP_OUTPUT_VEC+1        
                LDA #NEVER_CONSIDERED   
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
                STA fmm_curtime
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
_fmm_seed_himut ADC #42 ; we shift the high byte to point to the output
                STA ZP_OUTPUT_VEC+1
                TXA
                STA ZP_OUTPUT_VEC
                LDY fmm_list_next 
                CLC
                ADC #<-_FMM_X_1_Y_1
                STA fmm_addr_lo,y
                LDA ZP_OUTPUT_VEC+1
                ADC #>-_FMM_X_1_Y_1
                STA fmm_addr_hi,y
                LDA #0
                JMP fmm_continue ; tail call to set the priority of the cell    

;;-------------------------------------------------------------------------------
;; fmm_run()
;;       Runs the algorithm (reset and seeds should've been called before). Once
;;       the algorithm is complete, the output table will contain arrival times
;;       (distance), starting from the seeds.
;; Paramters: none
;; Touches: A, X, Y 
;;-------------------------------------------------------------------------------
_fmm_return     RTS
fmm_run         LDX fmm_curtime
                byte $24 ; BIT .... skips the following command
_fmm_advance    INX ; X is now the current time
                CPX #SOON_ACCEPTED
                BCS _fmm_return
                LDA fmm_list_head,x ; A is now the first element in list X
                BEQ _fmm_advance 
                STX fmm_curtime ; store the current time to zero page
inner_loop      LDY #_FMM_X_1_Y_1
inner_l_skipldy TAX ; X = current_element
inner_l_skiptax LDA fmm_addr_lo,x ; load the address of the element and store to
                STA ZP_OUTPUT_VEC ; ZP_OUTPUT_VEC
                STA ZP_INPUT_VEC ; already store the input low address 
                LDA fmm_addr_hi,x
                STA ZP_OUTPUT_VEC+1
                LDA (ZP_OUTPUT_VEC),y
                CMP #SOON_ACCEPTED ; if output < SOON_ACCEPTED, the cell has 
                BCS @set ; already been accepted and skip
                LDA fmm_list_next,x ; A is the following element
                BNE inner_l_skipldy
                TXA
                TAY
                JMP _fmm_list_destr
@set            LDA ZP_OUTPUT_VEC+1 ;    the high address of the INPUT_VEC is 
_fmm_pshiftin   ADC #42  ; carry is set. computed only if actually going to use
                STA ZP_INPUT_VEC+1 ; it
                LDA fmm_curtime
                STA (ZP_OUTPUT_VEC),y ; finally: accept the cell, set its time!
                STX ZP_TEMP ; store the current element to zero page
                _fmm_consider_v _FMM_X_1_Y_2,FMM_WIDTH,SOUTH,EAST,_FMM_X_0_Y_2,WEST,_FMM_X_2_Y_2,_fmm_cb_1
                _fmm_consider_v _FMM_X_1_Y_0,-FMM_WIDTH,NORTH,EAST,_FMM_X_0_Y_0,WEST,_FMM_X_2_Y_0,_fmm_cb_2
                _fmm_consider_h _FMM_X_0_Y_1,-1,WEST,NORTH,_FMM_X_0_Y_2,SOUTH,_FMM_X_0_Y_0,_fmm_cb_3
                _fmm_consider_h _FMM_X_2_Y_1,1,EAST,NORTH,_FMM_X_2_Y_2,SOUTH,_FMM_X_2_Y_0,_fmm_cb_4
                LDY ZP_TEMP ; retrieve the index of the current element from ZP
                LDX fmm_list_next,y ; find the following element
                BEQ _fmm_list_destr ; list had elements so free them in the end
                LDY #_FMM_X_1_Y_1
                JMP inner_l_skiptax
_fmm_list_destr LDX fmm_curtime ; free the elements in the list
                LDA fmm_list_next
                STA fmm_list_next,y ; Y was the tail of the list
                LDA fmm_list_head,x
                STA fmm_list_next
                JMP _fmm_advance

;-------------------------------------------------------------------------------
; macro _fmm_consider_v index shift cellval
defm            _fmm_consider_h
                LDY #/1
                LDA (ZP_OUTPUT_VEC),y
                CMP #NEVER_CONSIDERED  
                BCC /8+3; was already accepted or visited so no revisit
                BNE @test_1
                LDA #/3  ; the cell has never been considered
                STA (ZP_OUTPUT_VEC),y ; mark it as NORTH, SOUTH, EAST or WEST
                LDX fmm_list_next 
                LDA ZP_OUTPUT_VEC
@foo = /2-1
                ADC #<@foo ; carry is set
                STA fmm_addr_lo,x
                LDA ZP_OUTPUT_VEC+1
                ADC #>@foo
                STA fmm_addr_hi,x
                LDX #MAX_SLOWNESS ; call callback with X = MAX_SLOWNESS
                JMP /8
@test_1         CMP #/6
                BNE @test_2
                LDY #/7 ; this case, subtract NORTH-EAST cell from center cell
                JMP @subs
@test_2         LDY #/5 ; this case, subtract NORTH-WEST cell from center cell
@subs           LDA fmm_curtime
                SBC (ZP_OUTPUT_VEC),y ; carry is set already!          
                TAX
                LDY fmm_list_next 
                LDA ZP_OUTPUT_VEC
                ADC #<@foo
                STA fmm_addr_lo,y
                LDA ZP_OUTPUT_VEC+1
                ADC #>@foo
                STA fmm_addr_hi,y
                LDA #SOON_ACCEPTED
                LDY #/1
                STA (ZP_OUTPUT_VEC),y
/8              JSR $4242
                endm


defm            _fmm_consider_v
                LDY #/1
                LDA (ZP_OUTPUT_VEC),y
                CMP #EAST  
                BCC /8+3; was already accepted or visited so no revisit
                CMP #NEVER_CONSIDERED
                BNE @test_1
                LDA #/3  ; the cell has never been considered
                STA (ZP_OUTPUT_VEC),y ; mark it as NORTH, SOUTH, EAST or WEST
                LDX fmm_list_next 
                LDA ZP_OUTPUT_VEC
@foo = /2-1
                ADC #<@foo ; carry is set
                STA fmm_addr_lo,x
                LDA ZP_OUTPUT_VEC+1
                ADC #>@foo
                STA fmm_addr_hi,x
                LDX #MAX_SLOWNESS ; call callback with X = MAX_SLOWNESS
                JMP /8
@test_1         CMP #/4
                BNE @test_2
                LDY #/5 ; this case, subtract NORTH-EAST cell from center cell
                JMP @subs
@test_2         CMP #/6
                BNE /8+3 ; branch after the JSR to callback i.e. skip
                LDY #/7 ; this case, subtract NORTH-WEST cell from center cell
@subs           LDA fmm_curtime
                SBC (ZP_OUTPUT_VEC),y ; carry is set already!          
                TAX
                LDY fmm_list_next 
                LDA ZP_OUTPUT_VEC
                ADC #<@foo
                STA fmm_addr_lo,y
                LDA ZP_OUTPUT_VEC+1
                ADC #>@foo
                STA fmm_addr_hi,y
                LDA #SOON_ACCEPTED
                LDY #/1
                STA (ZP_OUTPUT_VEC),y
/8              JSR $4242
                endm

;-------------------------------------------------------------------------------
; fmm_continue  Adds a new element to the priority queue
; A = priority
; ZP_OUTPUT_VEC = addr, to which a 16-bit signed addition is done before it is
;                 added to list
; $(_fmm_add_hi_mut,_fmm_add_hi_mut) = 16-bit integer added to ZP_OUTPUT_VEC
;-------------------------------------------------------------------------------
fmm_continue    fmm_inlinecontinue

defm            fmm_inlinecontinue
                LDX fmm_list_next ; elem = list_next[0] (elem is X)
                CLC 
                ADC fmm_curtime
                TAY               ; list_index = slowness + curtime
                LDA fmm_list_next,x
                STA fmm_list_next ; list_next[0] = list_next[elem]
                LDA fmm_list_head,y ; head = list_head[list_index]
                STA fmm_list_next,x ; list_next[elem] = head
                TXA
                STA fmm_list_head,y ; list_head[list_index] = elem
                RTS
                endm

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
fmm_addr_hi     dcb 256,0       ; list of pointers to the backptr
fmm_addr_lo     dcb 256,0
fmm_list_next   dcb 256,0
fmm_list_head   dcb 256,0

watch fmm_addr_hi
watch fmm_addr_lo
watch fmm_list_next
watch fmm_list_head

