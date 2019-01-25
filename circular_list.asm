watch list_next
watch list_prev

;------------------------------
; checks if list X is empty
; touches A
; zero flag is set if the list is empty
;------------------------------ 
defm            list_empty
                LDA list_next,x
                CMP list_prev,x
endm

;------------------------------
; finds the next element after X
; touches A
;------------------------------ 
defm            list_getnext
                LDA list_next,x
                TAX
endm

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

;------------------------------
; inserts element X as the first element of list A, removing
; X first from where it is now
; touches A and Y
;------------------------------ 
list_move       PHA   ; store the new list for now, remove from the old list first
                TXA   
                PHA   ; store X, the element being added
                LDA list_next,x ; following lines link the next[x] and prev[x]
                LDY list_prev,x ; elements pointing to each other
                STA list_next,y
                TAX
                TYA
                STA list_prev,x ; the old list is now linked
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
                STA list_next,x
                RTS

list_next       dcb 256,0
list_prev       dcb 256,0