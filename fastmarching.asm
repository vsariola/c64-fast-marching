ZP_HEAP_PTR = $FB
ZP_OUTPUT_VEC = $FD
ZP_INPUT_VEC = $F9
ZP_ATIME_1 = $F8
ZP_ATIME_2 = $F7
FAR_TIME = 150 ; hard maximum for any fast marching time. maximum: 240
EMPTY_HEAP = 255;

watch heap_location
watch ZP_HEAP_PTR
watch ZP_OUTPUT_VEC
watch ZP_INPUT_VEC
watch ZP_ATIME_1
watch ZP_ATIME_2

;------------------------------
; fmm_reset: resets the fast marching method
;------------------------------
fmm_reset       LDY #0 ; this is the low address byte, but arrival time should be page aligned
                STY ZP_OUTPUT_VEC
_fmm_resetpage  LDX #42 ; mutated
                STX ZP_OUTPUT_VEC+1        
                LDA #FAR_TIME   
                LDX #4
@loop           STA (ZP_OUTPUT_VEC),y 
                INY
                BNE @loop
                INC ZP_OUTPUT_VEC+1
                DEX
                BNE @loop
                JMP queue_clear ; tail call into queue_clear

;------------------------------
; macro fmm_setinput address
; sets the input map to address (uses only the MSB of the address, because
; assumes page align)
; touches A
;------------------------------
defm            fmm_setinput
                LDA #>/1 - heap_location
                STA _fmm_pshiftin+1
                endm

;------------------------------
; macro fmm_setoutput address
; sets the output  map to address (uses only the MSB of the address, because
; assumes page align)
; touches A and carry
;------------------------------
defm            fmm_setoutput   
                LDA #>/1 
                STA _fmm_resetpage+1
                SEC
                SBC #>heap_location
                STA _fmm_pshiftout+1
                endm

;------------------------------
; macro fmm_setcallback address
; sets the callback function, to allow the user change how a cell is considered
;-------------------------
defm            fmm_setcallback
                LDA #</1
                STA _fmm_callback+1
                LDA #>/1
                STA _fmm_callback+2
                endm

;------------------------------
; fmm_seed: seeds the fast marching method
; X = low byte of the cell index (0-1023 in 32*32 map)
; Y = two high bits of the cell index
;------------------------------
fmm_seed        TYA
                CLC
                ADC #>heap_location
                TAY
                LDA #0
                JMP queue_insert              

;------------------------------
; fmm_run
;------------------------------
fmm_run         LDA heap_size
                BEQ fmm_return  ;  if heap is empty, we're done
                LDA heap_lo
                SEC
                SBC #66 ; shift two rows and two columns
                STA ZP_HEAP_PTR
                STA ZP_OUTPUT_VEC
                STA ZP_INPUT_VEC
                LDA heap_hi
                SBC #0  ;
                STA ZP_HEAP_PTR+1 ; ZP_TMP_A points now to the heapptrs, but shifted two rows / columns
                CLC
_fmm_pshiftout  ADC #42 ; mutated code so the user can choose where to write output
                STA ZP_OUTPUT_VEC+1 ; ZP_TMP_B points now to arrival times
                LDA ZP_HEAP_PTR+1
                CLC
_fmm_pshiftin   ADC #42 ; mutated code so the user can choose where to read input
                STA ZP_INPUT_VEC+1
                LDA heap_priority
                LDY #66
                STA (ZP_OUTPUT_VEC),y ; store the priority into the arrival time
                JSR queue_deletemin ; this cell is now accepted
                LDY #65   ; consider the cell on the left
                JSR _fmm_consider
                LDY #67   ; consider the cell on the right
                JSR _fmm_consider
                LDY #34    ; consider the cell below
                JSR _fmm_consider
                LDY #98    ; consider cell above
                JSR _fmm_consider
                JMP fmm_run
fmm_return     RTS

;------------------------------
; consider a neighbour
; Y: index of the cell to be considered, relative to ZP_TMP_* vectors
;------------------------------
_fmm_consider   LDA (ZP_OUTPUT_VEC),y
                CMP #FAR_TIME
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
                SBC #33 ; shift left and down
                TAY
                LDA (ZP_OUTPUT_VEC),y
                STA ZP_ATIME_2
                TYA    
                ADC #63 ; shift two rows up (2*32), note that carry is set
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
                TYA       ; you probably didn't remember that y still is the cell index
                SEC
                SBC #32   ; shift one down = go back to the center
                TAY
_fmm_callback   JMP $4242 ; mutated to allow the user change the callback
fmm_continue
@pushto_queue   CLC
                ADC ZP_ATIME_1 ; add the smaller of the arrival times to the relative time
                CMP #FAR_TIME
                BCS fmm_return ; the new time is >= FAR_TIME so stop now
                STA ZP_ATIME_1 ; ATIME_1 is now the new arrival time
                LDA #EMPTY_HEAP
                CMP (ZP_HEAP_PTR),y
                BEQ @newcell
                LDA #<queue_lower_pri
                STA @mutate_jmp+1
                LDA #>queue_lower_pri
                STA @mutate_jmp+2
                JMP @call
@newcell        LDA #<queue_insert
                STA @mutate_jmp+1
                LDA #>queue_insert
                STA @mutate_jmp+2
@call           TYA              ; A = relative index to the cell
                CLC
                ADC ZP_HEAP_PTR ; add A to ZP_HEAP_PTR (word)
                TAX  ; X = low address
                LDA #0
                ADC ZP_HEAP_PTR+1
                TAY ; Y = high address 
                LDA ZP_ATIME_1 ; A = priority
@mutate_jmp     JMP 4242 ; tail call into queue_insert or queue_lower_pri      

Align
heap_location   dcb 1024,EMPTY_HEAP ; note: we assume the arrival time is right after the heap



