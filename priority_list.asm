NUM_LISTS = 16
MAX_PRIORITY = 255

watch pri_base
watch pri_hi
watch pri_lo

; A = priority of the value to be inserted
; X = low byte of the address containing the back pointing heap pos byte
; Y = high byte of the address containing the back pointing heap pos byte
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
; end
; move elem as the first element of list priority & (NUM_LISTS-1)
; ptrs[elem] = ptr
pri_set         PHA
                STX @mutant+1
                STY @mutant+2
@mutant         LDX $4242
                CPX #255
                BNE @found_elem
                LDX list_next+255 ; find and element from the list of unused
                CPX #255          ; elements
                BNE @setptr       ; if there's unused elements, we jump
                LDA pri_base
@loop           SEC
                SBC #1
                AND #NUM_LISTS-1
                TAX
                CMP list_next,x
                BEQ @loop
                LDA pri_lo,x
                STA @mutant3+1
                LDA pri_hi,x
                STA @mutant3+2
                LDA #255
@mutant3        STA $4242
@setptr         LDA @mutant+1     ; *ptr = X
                STA @mutant2+1
                LDA @mutant+2
                STA @mutant2+2
@mutant2        STX $4242
@found_elem     PLA
                AND #NUM_LISTS-1
                JSR list_move ; list_move(X = element,A = priority & (NUMLISTS-1))
                LDA @mutant+1 ; ptrs[x] = ptr
                STA pri_lo,x ; note that list_move left X unchanged
                LDA @mutant+2
                STA pri_hi,x
                RTS

; TBW
pri_dequeue     LDA pri_base
                CMP #MAX_PRIORITY
                BCS @done          ; we've reached the MAX priority, returning carry set indicates we have no more items
                AND #NUM_LISTS-1
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
                LDA #0
                STA pri_lo,x
                STA pri_hi,x
                LDA #255
                JSR list_move
                LDX @mutant5+1
                LDY @mutant5+2
                LDA pri_base
                CLC  ; carry not set => we've got an item
@done           RTS

pri_reset       JSR pri_dequeue
                BCC pri_reset
                LDA #0
                STA pri_base
                RTS

pri_base        byte 0
pri_hi          dcb 256,0
pri_lo          dcb 256,0