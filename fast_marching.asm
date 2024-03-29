; O(N) Fast Marching Method in C64. (c) 2018-2019 Veikko Sariola
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
;   - Maximum arrival time is 249, inclusive. Values >= 250 in the output array
;     are used by the algorithm internally. After the algorithm is finished, all
;     values >= 250 should be considered to be FAR.
;   - The callback is responsible for bounds checking i.e. that fmm_zp_input
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
;   - Callback can return with:
;       1a. JMP fmm_continue, if the cell is considered
;       1b. calling macro fmm_inlinecontinue, which is same as 1a but inlined
;       2. RTS, if the cell should not be considered at all
;   - Callback should take two parameters: y, which is the index of the cell
;     considered, and x, which is the relative arrival times of the vertical
;     and horizontal cells or FMM_MAX_SLOW+1 if this cell has only straight
;     accepted neighbour. It returns the relative arrival time (compared to
;     the largest arrival times of neighbours) in register A
;   - Callback can access the map cell with LDA (fmm_zp_input),y
;
; Callback examples:
;
; This callback approximates L2-norm, where one map cell is 15 units long
;
; callback      LDA (fmm_zp_input),y  ; loads the map cell
;               CMP #$66              ; in this map, $66 denotes empty space
;               BEQ @notwall
;               RTS                   ; was a wall, no need to consider at all
; @notwall      LDA lookup,x
;               JMP fmm_continue
; lookup        byte 11,10,10,9,8,8,7,7,6,5,4,4,3,2,1,0,15
;
; The first 16 elements of the lookup table are generated with
; (sqrt(2*15*15-x*x)-x)/2. The last element is the slowness when moving straight
; This equation follows from solving u_x^2 + u_y^2 = 1/F^2, u_x = (u-a)/h,
; u_y = (u-b)/h where a and b are the smaller of the horizontal and vertical
; neighbours, respectively. Setting c = h/F so we get (u-a)^2 + (u-b)^2 = c^2.
; Without loss of generality we can assume b >= a and thus b = a+d. Solve for u
; (choosing the positive root) to get u = b + (sqrt(2*c^2-d^2)-d)/2. As usual,
; this first order approximation scheme is accurate (except the for rounding
; errors) for straight interfaces. For example, consider:
; 
;   0 ? ?      0 11  ?      0 11 22
;   # 0 ?  ->  #  0 11  ->  #  0 11
;   # # 0      #  #  0      #  #  0
;
; We see that 22 is very close to 15 * sqrt(2) = 21.213. However, extremely
; curved interface is the point source, where we have
;
;   ? ?      15  ?      15 26
;   0 ?  ->   0 15  ->   0 15
; 
; 26 is not very close to 15 * sqrt(2) = 21.213
;
; It is possible to use the algorithm with L1-norm also, by changing the lookup
; table. For example:
; 
; lookup          byte 15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,15

;-------------------------------------------------------------------------------
; Zero page registers
; Can be safely used when fmm_run, fmm_seed or fmm_reset are not running. 
;-------------------------------------------------------------------------------

fmm_zp_output = $FD ; vector (word)
fmm_zp_input = $02 ; vector (word)
fmm_zp_curtime = $04 ; byte
fmm_zp_curelem = $05 ; byte

watch fmm_zp_output
watch fmm_zp_input
watch fmm_zp_curtime
watch fmm_zp_curelem

;-------------------------------------------------------------------------------
; Constants / variables 
;-------------------------------------------------------------------------------
; the following constants are cell values in the output array, used to denote
; the type of the cell. The order is carefully chosen to optimize branching
; logic when considering the cell. Values < FMM_NEAR are the arrival times.
FMM_NORTH = 255 ; cell has been considered and north of an accepted cell
FMM_SOUTH = 254 ; cell has been considered and south of an accepted cell
FMM_FAR = 253 ; cell has never been considered
FMM_WEST = 252 ; cell has been considered and west of an accepted cell
FMM_EAST = 251 ; cell has been considered and east of an accepted cell
FMM_NEAR = 250 ; cell has been considered diagonally and will soon be accepted

; Your callback function should always return a value <= FMM_MAX_SLOW.
; Also, when X = FMM_MAX_SLOW+1 in the callback, the returned slowness should be
; the slowness when moving straight. In practice, the length of the callback
; lookup table will have to be FMM_MAX_SLOW+2
FMM_MAX_SLOW = 15

; FMM_WIDTH and FMM_HEIGHT should be defined by the user
FMM_X_0_Y_0 = 0+0*FMM_WIDTH
FMM_X_0_Y_1 = 0+1*FMM_WIDTH
FMM_X_0_Y_2 = 0+2*FMM_WIDTH
FMM_X_1_Y_0 = 1+0*FMM_WIDTH
FMM_X_1_Y_1 = 1+1*FMM_WIDTH
FMM_X_1_Y_2 = 1+2*FMM_WIDTH
FMM_X_2_Y_0 = 2+0*FMM_WIDTH
FMM_X_2_Y_1 = 2+1*FMM_WIDTH
FMM_X_2_Y_2 = 2+2*FMM_WIDTH

FMM_SIZE = FMM_WIDTH * FMM_HEIGHT
FMM_SIZE_MINUS_1 = FMM_WIDTH * FMM_HEIGHT - 1

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
                LDA #>/2+FMM_SIZE_MINUS_1
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
; macro fmm_setrange value
;       Sets the 'range' i.e. maximum arrival time, exclusive, of the fast
;       marching method
; Touches: A
;-------------------------------------------------------------------------------
defm            fmm_setrange
                LDA #/1
                STA _fmm_range+1
                endm

;-------------------------------------------------------------------------------
; fmm_reset()
;       Resets the fast marching method, should be called before each run of the
;       algorithm. Clears the output array with FMM_FAR and resets the
;       internally used priority list. Finally, sets current time to 0.
; Parameters: none
; Touches: A,X,Y,fmm_zp_output
;-------------------------------------------------------------------------------  
fmm_reset       LDX #0 ;    for i in range(0,256):
@loop           LDA #0 
                STA fmm_list_head,x ;         list_head[i] = 0
                TXA             ; this loop creates the empty lists
                DEX
                STA fmm_list_next,x ; list_next[i] = (i+1) & 255
                BNE @loop              
                ;     for i in range(len(output)):
                ;         output[i] = FMM_FAR
                LDY #0 ; low address byte = 0, because we assume page align
                STY fmm_zp_output
_fmm_resetpage  LDX #42 ; mutated
                STX fmm_zp_output+1        
                LDA #FMM_FAR   
                LDX #>FMM_SIZE_MINUS_1
                LDY #<FMM_SIZE_MINUS_1
@loop           STA (fmm_zp_output),y 
                DEY
                BNE @loop
                STA (fmm_zp_output),y 
                DEY
                DEC fmm_zp_output+1
                DEX
                BPL @loop
                LDA #0
                STA fmm_zp_curtime
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
                STA fmm_zp_output+1
                TXA
                STA fmm_zp_output
                LDY fmm_list_next 
                CLC
                ADC #<-FMM_X_1_Y_1
                STA fmm_addr_lo,y
                LDA fmm_zp_output+1
                ADC #>-FMM_X_1_Y_1
                STA fmm_addr_hi,y
                LDA #0
                JMP fmm_continue ; tail call to set the priority of the cell    

;-------------------------------------------------------------------------------
; fmm_run()
;       Runs the algorithm (reset and seeds should've been called before). Once
;       the algorithm is complete, the output table will contain arrival times
;       (distance), starting from the seeds.
; Parameters: none
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
_fmm_return     RTS
fmm_run         LDX fmm_zp_curtime
                byte $24 ; BIT .... skips the following command
_fmm_advance    INX ; X is now the current time
_fmm_range      CPX #FMM_NEAR
                BCS _fmm_return
                LDA fmm_list_head,x ; A is now the first element in list X
                BEQ _fmm_advance 
                STX fmm_zp_curtime ; store the current time to zero page
inner_loop      LDY #FMM_X_1_Y_1
inner_l_skipldy TAX ; X = current_element
inner_l_skiptax LDA fmm_addr_lo,x ; load the address of the element and store to
                STA fmm_zp_output ; fmm_zp_output
                STA fmm_zp_input ; already store the input low address 
                LDA fmm_addr_hi,x
                STA fmm_zp_output+1
                LDA (fmm_zp_output),y
                CMP #FMM_NEAR ; if output < FMM_NEAR, the cell has 
                BCS @set ; already been accepted and skip
                LDA fmm_list_next,x ; A is the following element
                BNE inner_l_skipldy
                TXA
                TAY
                JMP _fmm_list_destr
@set            LDA fmm_zp_output+1 ;    the high address of the INPUT_VEC is 
_fmm_pshiftin   ADC #42  ; carry is set. computed only if actually going to use
                STA fmm_zp_input+1 ; it
                LDA fmm_zp_curtime
                STA (fmm_zp_output),y ; finally: accept the cell, set its time!
                STX fmm_zp_curelem ; store the current element to zero page
                _fmm_consider_h FMM_X_0_Y_1,-1,FMM_WEST,FMM_X_0_Y_2,FMM_X_0_Y_0,_fmm_cb_1
                _fmm_consider_h FMM_X_2_Y_1,1,FMM_EAST,FMM_X_2_Y_2,FMM_X_2_Y_0,_fmm_cb_2
                _fmm_consider_v FMM_X_1_Y_2,FMM_WIDTH,FMM_SOUTH,FMM_X_0_Y_2,FMM_X_2_Y_2,_fmm_cb_3
                _fmm_consider_v FMM_X_1_Y_0,-FMM_WIDTH,FMM_NORTH,FMM_X_0_Y_0,FMM_X_2_Y_0,_fmm_cb_4
                LDY fmm_zp_curelem ; retrieve the index of the current element from ZP
                LDX fmm_list_next,y ; find the following element
                BEQ _fmm_list_destr ; list had elements so free them in the end
                LDY #FMM_X_1_Y_1
                JMP inner_l_skiptax
_fmm_list_destr LDX fmm_zp_curtime ; free the elements in the list
                LDA fmm_list_next
                STA fmm_list_next,y ; Y was the tail of the list
                LDA fmm_list_head,x
                STA fmm_list_next
                JMP _fmm_advance

;-------------------------------------------------------------------------------
; macro _fmm_consider_h cell,shift,code,northcell,southcell,labelname
;       Used to consider the horizontal i.e. cells west and east of an accepted
;       cell. Internally used by the algorithm - user should not need this.
; Parameters:
;       cell = address of the cell to be considered, relative to fmm_zp_output
;       shift = -1 for west cell, 1 for east cell
;       code = FMM_WEST for west cell, FMM_EAST for east cell
;       northcell = address north of cell
;       southcell = address south of cell
;       labelname = unique name for a label, used by macro set_callback
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
defm            _fmm_consider_h
                LDY #/1
                LDA (fmm_zp_output),y
                CMP #FMM_FAR  
                BCC /6+3; was already accepted or visited so no revisit
                BNE @test_1
                LDA #/3  ; the cell has never been considered
                STA (fmm_zp_output),y ; mark it as FMM_EAST or FMM_WEST
                LDX fmm_list_next 
                LDA fmm_zp_output
@foo = /2-1
                ADC #<@foo ; carry is set
                STA fmm_addr_lo,x
                LDA fmm_zp_output+1
                ADC #>@foo
                STA fmm_addr_hi,x
                LDX #FMM_MAX_SLOW+1 ; call callback with X = FMM_MAX_SLOW + 1
                JMP /6
@test_1         CMP #FMM_SOUTH
                BNE @test_2
                LDY #/5
                JMP @subs
@test_2         LDY #/4
@subs           LDA fmm_zp_curtime
                SBC (fmm_zp_output),y ; carry is set already!          
                TAX
                LDY fmm_list_next 
                LDA fmm_zp_output
                ADC #<@foo
                STA fmm_addr_lo,y
                LDA fmm_zp_output+1
                ADC #>@foo
                STA fmm_addr_hi,y
                LDA #FMM_NEAR
                LDY #/1
                STA (fmm_zp_output),y
/6              JSR $4242
                endm

;-------------------------------------------------------------------------------
; macro _fmm_consider_v cell,shift,code,westcell,eastcell,labelname
;       Used to consider the vertical i.e. cells north and south of an accepted
;       cell. Internally used by the algorithm - user should not need this.
; Parameters:
;       cell = address of the cell to be considered, relative to fmm_zp_output
;       shift = -FMM_WIDTH for north cell, FMM_WIDTH for south cell
;       code = FMM_NORTH for north cell, FMM_SOUTH for south cell
;       westcell = address west of cell
;       eastcell = address east of cell
;       labelname = unique name for a label, used by macro set_callback
; Touches: A, X, Y 
;-------------------------------------------------------------------------------
defm            _fmm_consider_v
                LDY #/1
                LDA (fmm_zp_output),y
                CMP #FMM_EAST  
                BCC /6+3; was already accepted or visited so no revisit
                CMP #FMM_FAR
                BNE @test_1
                LDA #/3  ; the cell has never been considered
                STA (fmm_zp_output),y ; mark it as FMM_NORTH or FMM_SOUTH
                LDX fmm_list_next 
                LDA fmm_zp_output
@foo = /2-1
                ADC #<@foo ; carry is set
                STA fmm_addr_lo,x
                LDA fmm_zp_output+1
                ADC #>@foo
                STA fmm_addr_hi,x
                LDX #FMM_MAX_SLOW+1 ; call callback with X = FMM_MAX_SLOW + 1
                JMP /6
@test_1         CMP #FMM_EAST
                BNE @test_2
                LDY #/4
                JMP @subs
@test_2         CMP #FMM_WEST
                BNE /6+3 ; branch after the JSR to callback i.e. skip
                LDY #/5
@subs           LDA fmm_zp_curtime
                SBC (fmm_zp_output),y ; carry is set already!          
                TAX
                LDY fmm_list_next 
                LDA fmm_zp_output
                ADC #<@foo
                STA fmm_addr_lo,y
                LDA fmm_zp_output+1
                ADC #>@foo
                STA fmm_addr_hi,y
                LDA #FMM_NEAR
                LDY #/1
                STA (fmm_zp_output),y
/6              JSR $4242
                endm

;-------------------------------------------------------------------------------
; fmm_continue(A)
;       Adds a new element to the priority queue. This is typically tail called
;       from the callback function.
; Parameters:
;       A = relative priority of the cell to be added.
; Touches: A,X,Y
;-------------------------------------------------------------------------------  
fmm_continue    fmm_inlinecontinue

defm            fmm_inlinecontinue
                LDX fmm_list_next ; elem = list_next[0] (elem is X)
                CLC 
                ADC fmm_zp_curtime
                TAY               ; list_index = relpriority + curtime
                LDA fmm_list_next,x
                STA fmm_list_next ; list_next[0] = list_next[elem]
                LDA fmm_list_head,y ; head = list_head[list_index]
                STA fmm_list_next,x ; list_next[elem] = head
                TXA
                STA fmm_list_head,y ; list_head[list_index] = elem
                RTS
                endm

;-------------------------------------------------------------------------------
; Internally used arrays for the fast marching method. Can be safely overwritten
; when the algorithm is not running; they are initialized by fmm_reset.
; These arrays contain the cells currently being considered.
;-------------------------------------------------------------------------------
fmm_addr_hi     dcb 256,0 ; high bytes of the cell address in the output array
fmm_addr_lo     dcb 256,0 ; low bytes of the cell address in the output array
fmm_list_next   dcb 256,0 ; next element indices in the linked list
fmm_list_head   dcb 256,0 ; fmm_list_head[time] contains the first element of a
; a linked list of elements that have been considered with the priority of time

watch fmm_addr_hi
watch fmm_addr_lo
watch fmm_list_next
watch fmm_list_head

