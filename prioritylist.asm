NUM_HEADS = 16
EMPTY_VALUE = 255
AFTER_LAST = PRIORITY_LIST_LENGTH AND 255
PRIORITY_LIST_LAST = PRIORITY_LIST_LENGTH-1
       
ZP_LIST_TEMP = $EE
ZP_LIST_TEMP2 = $EE


* = 801

watch list_base_pri
watch list_hi
watch list_lo
watch list_next
watch list_prev

;------------------------------
; list_update: 
; A = priority of the value to be inserted
; X = low byte of the address containing the back pointing heap pos byte
; Y = high byte of the address containing the back pointing heap pos byte
;------------------------------
list_update     STX @mutable_ldx+1
                STY @mutable_ldx+2
@mutable_ldx    LDX 4242
                PHA
                JSR list_delete
                PLA
                LDX @mutable_ldx+1
                LDY @mutable_ldx+2
                JMP list_insert

;------------------------------
; list_insert: 
; A = priority of the value to be inserted
; X = low byte of the address containing the back pointing heap pos byte
; Y = high byte of the address containing the back pointing heap pos byte
;------------------------------
list_insert     STX @mutate_sta+1
                STY @mutate_sta+2
                PHA
                TXA
                LDX list_next+PRIORITY_LIST_LAST
                STA list_lo,x 
                TYA
                STA list_hi,x ; store the forward pointer
                CPX #PRIORITY_LIST_LAST
                BNE @adding
                JSR list_del_last
@adding         LDX list_next+PRIORITY_LIST_LAST
                PLA
                SEC
                SBC list_base_pri
                AND #NUM_HEADS-1
                STA list_prev,x
                TAY
                LDA list_next,y
                STA list_next,x
                PHA
                TXA
                STA list_next,y
                PLA
                TAY
                TXA
                STA list_prev,y
@mutate_sta     STA 4242  ; store the back pointer
                RTS

;------------------------------
; touches A, X, Y
;------------------------------
list_clear_all  LDX #0 ; load the next ptr of first head
@loop           LDA list_next,x
                BEQ @done     ; if we reach back to the first head, we're done
                TAX
                CPX #NUM_HEADS
                BCC @loop
                JSR list_delete
                JMP @loop
@done           LDA #0
                STA list_base_pri
                RTS
     
                

;------------------------------
; touches A, X, Y
;------------------------------
list_find_first LDA list_base_pri
                AND #NUM_HEADS-1
                STA @loop+1
                TAX
                LDA list_next,x
@loop           CMP #42
                BEQ @not_found
                TAX
                CPX #NUM_HEADS
                BCS @return    
                LDA list_next,x
                INC list_base_pri
                JMP @loop
@not_found      LDX #EMPTY_VALUE
@return         RTS


;------------------------------
; touches A, X, Y
;------------------------------
list_del_last   LDA list_base_pri
                AND #NUM_HEADS-1
                STA @loop+1
                TAX
                LDA list_prev,x
@loop           CMP #42
                BEQ @done_del
                TAX
                CPX #NUM_HEADS
                BCS list_delete
                LDA list_prev,x
                JMP @loop
@done_del       RTS
                
   
;------------------------------
; inserts element X as the first element of list A, removing
; X first from where it is now
;------------------------------ 
list_move       PHA   ; store the new list for now, remove from the old list first
                TXA   
                PHA   ; store X, the element being added
                LDA list_next,x ; following lines link the next[x] and prev[x]
                LDY list_prev,x ; elements pointing to each other
                STA list_next,y
                TAX
                TYA
                STA list_prev,x ; the old list is now 
                PLA ; recover the element being added from stack
                TAX ; X = the element being added
                PLA ; A = the head of the new list
                STA list_prev,x ; prev[x] = head              
                TAY ; Y = the head of the new list
                LDA list_next,y
                PHA ; push current next[head]
                TXA
                STA list_next,y ; next[head] = elem
                PLA ; A is the soon to be second elemt
                TAY ; Y is the soon to be second element
                TXA
                STA list_prev,y ; 
                TYA
                STA list_next,y
                RTS
                

;------------------------------
; X = element id
; touches A, Y
;------------------------------
list_delete     LDA list_hi,x
                BEQ @done       ; if there's no pointer -> nothing to clear
                STA @mutable_sta+2  
                LDA list_lo,x
                STA @mutable_sta+1
                LDA #EMPTY_VALUE
@mutable_sta    STA 4242         ; clear the back pointer
                LDA #0
                STA list_hi,x   ; clear the forward pointer
                LDA list_next,x ; link the elements before and after element x
                LDY list_prev,x
                STA list_next,y
                LDA list_prev,x
                LDY list_next,x
                STA list_prev,y
                LDA #PRIORITY_LIST_LENGTH-1 ; add x in between the list 
                STA list_prev,x  ; of empty values
                LDY #PRIORITY_LIST_LENGTH-1
                LDA list_next,y
                STA list_next,x
                TXA 
                STA list_next,y
                LDY list_next,x
                TXA
                STA list_prev,y
@done           RTS

list_base_pri   byte 0
list_hi         dcb 256,0
list_lo         dcb 256,0