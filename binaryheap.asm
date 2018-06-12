; (c) 2018 Veikko Sariola
; License: MIT
watch heap_size
watch heap_priority
watch heap_hi
watch heap_lo

HEAP_MAX_SIZE = 255

;------------------------------
; queue_insert: 
; A = priority of the value to be inserted
; X = low byte of the address containing the back pointing heap pos byte
; Y = high byte of the address containing the back pointing heap pos byte
;------------------------------
queue_insert    STX @mutate_sta+1
                STY @mutate_sta+2
                LDX heap_size
                INC heap_size
                STA heap_priority,X
                TYA
                STA heap_hi,X
                LDA @mutate_sta+1
                STA heap_lo,X
                TXA
@mutate_sta     STA 4242 
                ; flow into _queue_bubbleup

;------------------------------
; _queue_bubbleup: 
; A = index of the element being bubbled up
;------------------------------
_queue_bubbleup TAY               ; y is now the index of the element to be bubbled up
                BEQ @finalize     ; if we reach the top of the heap, stop bubbling
                SEC
                SBC #1
                LSR
                TAX   ; x is the parent of y, x = (y - 1) >> 1
                LDA heap_priority,Y    ; comparing heap[x] to heap[y]
                CMP heap_priority,X
                BCS @finalize    ; if heap[x] <= heap[y], were done
                JSR _queue_swap
                TXA
                JMP _queue_bubbleup  ; continue bubbling up
@finalize       LDA #HEAP_MAX_SIZE ; remove one element from the end if full
                CMP heap_size            
                BCS _bd_return
                JMP queue_clearlast
_bd_return      RTS


;------------------------------
; queue_deletemin: deletes the smallest element in the heap
;   no parameters.
;------------------------------
queue_deletemin LDA heap_lo ; set heap_hi[0]:heap_lo[0] = 255
                STA @save+1
                LDA heap_hi
                STA @save+2
                LDA #255
@save           STA 4242 ; mutated
                DEC heap_size ; decrease heap size
                BEQ _bd_return ; move last element to first
                LDX heap_size
                LDA heap_lo,x
                STA heap_lo
                STA @save2+1
                LDA heap_hi,x
                STA heap_hi
                STA @save2+2
                LDA heap_priority,x
                STA heap_priority
                LDA #0
@save2          STA 4242   ; set the back pointer to zero
                LDA #0            ; start bubbling from top (y = node bubbled)
                ; flow directly into bubbledown

;------------------------------
; _queue_bubbledn 
; A = index of the element being bubbled down
;------------------------------
_queue_bubbledn TAX          
                CLC    
                ADC #1
                ASL 
                TAY ; y = (a << 1)+2 aka right child
                CMP heap_size
                BCC @has_two_childs
                BEQ @top_vs_child
                RTS ; no children, we're done!
@has_two_childs LDA heap_priority-1,y
                CMP heap_priority,y
                BCS @top_vs_child ; left >= right, so using right is ok
                DEY ; ok, so left was smaller, use it then
@top_vs_child   LDA heap_priority,y
                CMP heap_priority,x
                BCS _bd_return ; child >= top, so we're done for good
                JSR _queue_swap ; swap elements x and y
                TYA
                JMP _queue_bubbledn ; continue bubbling down

;------------------------------
; queue_lower_pri:  lowers the priority of an element in the queue if the new priority is smaller
; A = new priority of the value to be updated
; X = low byte of the address containing the back pointing heap pos byte
; Y = high byte of the address containing the back pointing heap pos byte
;------------------------------
queue_lower_pri STX @mutable_ldx+1
                STY @mutable_ldx+2
@mutable_ldx    LDX 4242
                CMP heap_priority,x
                BCS _bd_return ; the new priority is larger, no need to do anything
                STA heap_priority,x
                TXA
                JMP _queue_bubbleup
                
;------------------------------
; queue_clear
;------------------------------
queue_clear     LDX heap_size
                BEQ @done
                JSR _queue_cl_noldx
                JMP queue_clear
@done           RTS

;------------------------------
; queue_clearlast
;------------------------------
queue_clearlast LDX heap_size
_queue_cl_noldx LDA heap_lo-1,x
                STA @mutable_sta+1
                LDA heap_hi-1,x
                STA @mutable_sta+2
                LDA #255
@mutable_sta    STA 4242
                DEC heap_size
                RTS


;------------------------------
; _queue_swap_xy: a macro to swap two elements updates their back pointers
; X = element 1
; Y = element 2
;------------------------------
defm            _queue_swap_xy   ; swap elements x and y in table /1
                LDA /1,Y 
                PHA
                LDA /1,X
                STA /1,Y
                PLA
                STA /1,X
                endm

;------------------------------
; _queue_swap: swaps two elements in the heap and updates their back pointers
; X = element 1
; Y = element 2
;------------------------------
_queue_swap
                _queue_swap_xy heap_priority
                _queue_swap_xy heap_lo
                _queue_swap_xy heap_hi
                LDA heap_lo,x
                STA @savex+1
                LDA heap_hi,x
                STA @savex+2
@savex          STX 4242 ; mutated
                LDA heap_lo,y
                STA @savey+1
                LDA heap_hi,y
                STA @savey+2
@savey          STY 4242 ; mutated
                RTS      

;------------------------------
; DATA ELEMENTS
;------------------------------
heap_size       byte 0

; extra element is temporarily needed during adding
heap_priority   dcb HEAP_MAX_SIZE+1,0

heap_hi         dcb HEAP_MAX_SIZE+1,0

heap_lo         dcb HEAP_MAX_SIZE+1,0