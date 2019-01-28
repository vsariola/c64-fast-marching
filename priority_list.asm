; (c) 2018-2019 Veikko Sariola

; the priority of the largest element should always be < smallest priority + 
; NUM_LISTS. Furthermore, NUM_LISTS should be a power of 2 (which makes
; mod(x,NUM_LISTS) possible using AND).
NUM_LISTS = 16

ZP_PRI_TEMP = $04

; the list shall always contain only elements with priority <= MAX_PRIORITY
MAX_PRIORITY = 240

watch pri_base
watch pri_hi
watch pri_lo

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
pri_set         PHA
                STX ZP_PRI_TEMP
                STY ZP_PRI_TEMP+1
                LDY #0
                LDA (ZP_PRI_TEMP),y
                TAX
                CPX #255
                BNE @found_elem
                LDX list_next+255 ; find and element from the list of unused
                CPX #255          ; elements
                BNE @setptr       ; if there's unused elements, we jump
                LDA pri_base
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
@setptr         TXA
                STA (ZP_PRI_TEMP),y
                LDA ZP_PRI_TEMP ; ptrs[x] = ptr
                STA pri_lo,x ; note that list_move left X unchanged
                LDA ZP_PRI_TEMP+1
                STA pri_hi,x
@found_elem     PLA ; A was the priority
                AND #NUM_LISTS-1 ; the list head is priority & (NUM_LISTS-1)
                JMP list_move ; tail call to move eement X to list A

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
                LDA pri_lo,x
                STA @mutant5+1
                LDA pri_hi,x
                STA @mutant5+2
                LDA #255
@mutant5        STA $4242
                ;LDA #0  ; these are not really necessary
                ;STA pri_lo,x
                ;STA pri_hi,x
                LDA #255
                JSR list_move
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

;-------------------------------------------------------------------------------
; DATA
;-------------------------------------------------------------------------------
pri_base        byte 0          ; priority of the lowest element in the list
pri_hi          dcb 256,0       ; list of pointers to the backptr
pri_lo          dcb 256,0