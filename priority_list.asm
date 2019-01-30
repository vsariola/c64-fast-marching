; (c) 2018-2019 Veikko Sariola

; the priority of the largest element should always be < smallest priority + 
; NUM_LISTS. Furthermore, NUM_LISTS should be a power of 2 (which makes
; mod(x,NUM_LISTS) possible using AND).
NUM_LISTS = 16

ZP_PRI_TEMP = $04
ZP_CIRC_TEMP = $03

; the list shall always contain only elements with priority <= MAX_PRIORITY
MAX_PRIORITY = 240

watch pri_base
watch pri_hi
watch pri_lo
watch list_next
watch list_prev

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
;       A = priority of the cell
;       X = low byte of the memory address containing the back pointer
;       Y = high byte of the memoty address containing the back pointer
; Touches: A, X, Y
;-------------------------------------------------------------------------------
pri_set         AND #NUM_LISTS-1 ; the list head is priority & (NUM_LISTS-1)
                PHA   ; store the correct list head in stack
                STX ZP_PRI_TEMP   ; ZP_PRI_TEMP points to the back pointer
                STY ZP_PRI_TEMP+1
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

;-------------------------------------------------------------------------------
; pri_reset()
;       Removes all the elements from the queue and resets the starting priority
;       to 0.
; 
; Parameters: none
; Touches: A, X, Y
;-------------------------------------------------------------------------------
pri_reset       JSR pri_dequeue
                BCC pri_reset
                LDA #0
                STA pri_base
                RTS

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