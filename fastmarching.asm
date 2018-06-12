ZP_HEAP_PTR = $FB
ZP_ARR_TIME = $FD
ZP_ATIME_1 = $FA
ZP_ATIME_2 = $F9
ZP_TMP_1 = $F7
ZP_TMP_2 = $F5
FAR_TIME = 150 ; hard maximum for any fast marching time. maximum: 240
EMPTY_HEAP = 255;

watch heap_location
watch fmm_time
watch ZP_HEAP_PTR
watch ZP_ARR_TIME
watch ZP_ATIME_1
watch ZP_ATIME_2

fmmdebug = 1; defining this includes useful debug commands in the build

;------------------------------
; fmm_reset: resets the fast marching method
;------------------------------
fmm_reset       LDY #0 ; this is the low address byte, but arrival time should be page aligned
                STY ZP_ARR_TIME
                LDX #>fmm_time
                STX ZP_ARR_TIME+1        
                LDA #FAR_TIME   
                LDX #4
@loop           STA (ZP_ARR_TIME),y 
                INY
                BNE @loop
                INC ZP_ARR_TIME+1
                DEX
                BNE @loop
                JMP queue_clear ; tail call into queue_clear

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
                BEQ _fmm_return  ;  if heap is empty, we're done
                LDA heap_lo
                SEC
                SBC #66 ; shift two rows and two columns
                STA ZP_HEAP_PTR
                STA ZP_ARR_TIME
                LDA heap_hi
                SBC #0  ;
                STA ZP_HEAP_PTR+1 ; ZP_TMP_A points now to the heapptrs, but shifted two rows / columns
                CLC
                ADC #4 ; the arrival times are 4 pages after heap locs
                STA ZP_ARR_TIME+1 ; ZP_TMP_B points now to arrival times
                LDA heap_priority
                LDY #66
                STA (ZP_ARR_TIME),y ; store the priority into the arrival time
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
_fmm_return     RTS

;------------------------------
; consider a neighbour
; Y: index of the cell to be considered, relative to ZP_TMP_* vectors
;------------------------------
_fmm_consider   LDA (ZP_ARR_TIME),y
                CMP #FAR_TIME
                BCC _fmm_return ; this cell has already been accepted
                DEY  ; shift one left
                LDA (ZP_ARR_TIME),y
                STA ZP_ATIME_1
                INY  ; shift two right
                INY
                LDA (ZP_ARR_TIME),y
                CMP ZP_ATIME_1
                BCS @left_le_right
                STA ZP_ATIME_1 ; ATIME_1 is smaller of the horizontal times
@left_le_right  TYA 
                SEC
                SBC #33 ; shift left and down
                TAY
                LDA (ZP_ARR_TIME),y
                STA ZP_ATIME_2
                TYA    
                ADC #63 ; shift two rows up (2*32), note that carry is set
                TAY
                LDA (ZP_ARR_TIME),y
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
@ispositive     CMP #15 ; TODO: this is the slowness - where to get?
                BCC @eikonal
                LDA #15  ; TODO: again, this is the slowness
                JMP @pushto_queue
@eikonal        TAX
                LDA _fmm_lookup+240,x
@pushto_queue   CLC
                ADC ZP_ATIME_1 ; add the smaller of the arrival times to the relative time
                CMP #FAR_TIME
                BCS _fmm_return ; the new time is >= FAR_TIME so stop now
                STA ZP_ATIME_1 ; ATIME_1 is now the new arrival time
                TYA       ; you probably didn't remember that y still is the cell index
                SEC
                SBC #32   ; shift one down = go back to the center
                TAY
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

_fmm_lookup     byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
                byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
                byte 1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
                byte 2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
                byte 3,3,4,4,4,4,4,4,4,4,4,4,4,4,4,4
                byte 4,4,4,5,5,5,5,5,5,5,5,5,5,5,5,5
                byte 4,5,5,5,6,6,6,6,6,6,6,6,6,6,6,6
                byte 5,5,6,6,7,7,7,7,7,7,7,7,7,7,7,7
                byte 6,6,7,7,7,8,8,8,8,8,8,8,8,8,8,8
                byte 6,7,7,8,8,8,9,9,9,9,9,9,9,9,9,9
                byte 7,8,8,8,9,9,9,10,10,10,10,10,10,10,10,10
                byte 8,8,9,9,10,10,10,10,11,11,11,11,11,11,11,11
                byte 8,9,9,10,10,11,11,11,11,12,12,12,12,12,12,12
                byte 9,10,10,11,11,11,12,12,12,13,13,13,13,13,13,13
                byte 10,10,11,11,12,12,12,13,13,13,14,14,14,14,14,14
                byte 11,11,12,12,12,13,13,14,14,14,14,15,15,15,15,15

Align
heap_location   dcb 1024,EMPTY_HEAP ; note: we assume the arrival time is right after the heap

fmm_time        dcb 1024,FAR_TIME


;------------------------------
; 
; DEBUG related stuff
; will not be included in the release version 
; 
;------------------------------

ifdef fmmdebug

screen_mem = $0400

fmm_dump        LDA #<fmm_time-1
                STA ZP_TMP_1
                LDA #>fmm_time-1
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
endif
