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
fmm_curtime = $04 ; byte

watch ZP_OUTPUT_VEC
watch ZP_INPUT_VEC

NEVER_CONSIDERED = 255
NORTH = 254
SOUTH = 253
WEST = 252
EAST = 251
SOON_ACCEPTED = 250

; Your callback function should always return a value < NUM_LISTS. Furthermore,
; NUM_LISTS should be a power of 2
NUM_LISTS = 16

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
                LDA #>/1 - /2
                STA _fmm_pshiftin+1
                LDA #>/2
                STA _fmm_seed_himut+1
                LDA #>/2+_FMM_SIZE_MINUS_1
                STA _fmm_resetpage+1
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
fmm_reset       LDX #0 ;    for i in range(0,256):
@loop1          TXA             ; this loop creates the empty lists
                DEX
                STA fmm_list_next,x ; list_next[i] = (i+1) & 255
                BNE @loop1               
                LDX NUM_LISTS ;     for i in range(NUM_LISTS):
                LDA #0 
@loop2          DEX
                STA fmm_list_head,x ;         list_head[i] = 0
                STA fmm_list_tail,x ;         list_tail[i] = 0
                BNE @loop2
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
                LDA #<-_FMM_X_1_Y_1
                STA _fmm_add_lo_mut+1
                LDA #>-_FMM_X_1_Y_1
                STA _fmm_add_hi_mut+1
                LDA #0
                JMP _fmm_list_add ; tail call to set the priority of the cell    

;;-------------------------------------------------------------------------------
;; fmm_run()
;;       Runs the algorithm (reset and seeds should've been called before). Once
;;       the algorithm is complete, the output table will contain arrival times
;;       (distance), starting from the seeds.
;; Paramters: none
;; Touches: A, X, Y 
;;-------------------------------------------------------------------------------
_fmm_return     RTS
fmm_run         
_fmm_run_loop   LDA fmm_curtime
                CMP #SOON_ACCEPTED
                BCS _fmm_return
                AND #NUM_LISTS-1 
                TAX
                LDA fmm_list_head,x
                BNE inner_loop
                INC fmm_curtime
                JMP _fmm_run_loop
inner_loop      TAX ; X = current_element
                LDA fmm_addr_lo,x
                STA ZP_OUTPUT_VEC
                STA ZP_INPUT_VEC
                LDA fmm_addr_hi,x
                STA ZP_OUTPUT_VEC+1
                CLC
_fmm_pshiftin   ADC #42
                STA ZP_INPUT_VEC+1
                LDY #_FMM_X_1_Y_1
                LDA (ZP_OUTPUT_VEC),y
                CMP #SOON_ACCEPTED
                BCS @set
                JMP _fmm_load_next
@set            LDA fmm_curtime
                STA (ZP_OUTPUT_VEC),y
                TXA
                PHA
                _fmm_consider _FMM_X_1_Y_2,FMM_WIDTH,SOUTH,EAST,_FMM_X_0_Y_2,WEST,_FMM_X_2_Y_2,EAST
                _fmm_consider _FMM_X_1_Y_0,-FMM_WIDTH,NORTH,EAST,_FMM_X_0_Y_0,WEST,_FMM_X_2_Y_0,EAST
                _fmm_consider _FMM_X_0_Y_1,-1,WEST,NORTH,_FMM_X_0_Y_2,SOUTH,_FMM_X_0_Y_0,SOUTH
                _fmm_consider _FMM_X_2_Y_1,1,EAST,NORTH,_FMM_X_2_Y_2,SOUTH,_FMM_X_2_Y_0,SOUTH
                PLA
                TAX
_fmm_load_next  LDA fmm_list_next,x
                BEQ _fmm_list_destr
                JMP inner_loop
_fmm_list_destr LDA fmm_curtime
                AND #NUM_LISTS-1 
                TAX
                LDY fmm_list_tail,x
                LDA fmm_list_next
                STA fmm_list_next,y
                LDA fmm_list_head,x
                STA fmm_list_next
                LDA #0
                STA fmm_list_head,x
                STA fmm_list_tail,x
_fmm_run_cont   INC fmm_curtime
                JMP _fmm_run_loop

;-------------------------------------------------------------------------------
; macro _fmm_consider_v index shift cellval
defm            _fmm_consider
                LDY #/1
                LDA (ZP_OUTPUT_VEC),y
                CMP #/8
                BCC @skip
                CMP #NEVER_CONSIDERED
                BNE @test_1
                LDA #/3
                STA (ZP_OUTPUT_VEC),y
                LDX #NUM_LISTS
                JMP @call
@test_1         CMP #/4
                BNE @test_2
                LDA fmm_curtime
                LDY #/5
                SEC
                SBC (ZP_OUTPUT_VEC),y
                JMP @subs
@test_2         CMP #/6
                BNE @skip
                LDA fmm_curtime
                LDY #/7
                SEC
                SBC (ZP_OUTPUT_VEC),y
@subs           TAX
                LDA #SOON_ACCEPTED
                LDY #/1
                STA (ZP_OUTPUT_VEC),y
@call           LDA #</2
                STA _fmm_add_lo_mut+1
                LDA #>/2
                STA _fmm_add_hi_mut+1
                JSR _fmm_callback 
@skip           
                endm


_fmm_callback   JMP $4242 ; mutated to allow the user change the callback

_fmm_return3    RTS   

;-------------------------------------------------------------------------------
; _fmm_list_add
; A = priority
; ZP_OUTPUT_VEC = addr, which is shifted by a mutated 16-bit shift
;-------------------------------------------------------------------------------
fmm_continue
_fmm_list_add   LDX fmm_list_next ; elem = list_next[0] (elem is X)
                BEQ _fmm_return3      ; if list_next[0] == 0: return
                CLC 
                ADC fmm_curtime
                AND #NUM_LISTS-1
                TAY
                LDA fmm_list_next,x
                STA fmm_list_next ; list_next[0] = list_next[elem]
                LDA ZP_OUTPUT_VEC
_fmm_add_lo_mut ADC #42
                STA fmm_addr_lo,x ; addr_lo[elem] = addr & 255
                LDA ZP_OUTPUT_VEC+1
_fmm_add_hi_mut ADC #42
                STA fmm_addr_hi,x ; addr_hi[elem] = addr >> 8
                LDA #0
                STA fmm_list_next,x ; list_next[elem] = 0
                TXA
                LDX fmm_list_tail,y ; old_tail:Y = list_tail[priority]
                BNE @not_empty ; if old_tail == 0:
                STA fmm_list_head,y ;  list_head[priority] = elem
                JMP @continue
@not_empty      STA fmm_list_next,x ; list_next[old_tail] = elem
@continue       STA fmm_list_tail,y ; list_tail[priority] = elem
_fmm_return2    RTS   

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
fmm_addr_hi     dcb 256,0       ; list of pointers to the backptr
fmm_addr_lo     dcb 256,0
fmm_list_next   dcb 256,0
fmm_list_head   dcb NUM_LISTS,0
fmm_list_tail   dcb NUM_LISTS,0

watch fmm_curtime
watch fmm_addr_hi
watch fmm_addr_lo
watch fmm_list_next
watch fmm_list_head
watch fmm_list_tail

