* = $1000
               RTS

ZP_TMP_A = $FB
ZP_TMP_B = $FD

coord_to_ptr    STX ZP_TMP_A
                STY ZP_TMP_A+1
                LDA #0
                LSR ZP_TMP_A+1
                ROR
                LSR ZP_TMP_A+1
                ROR
                LSR ZP_TMP_A+1
                ROR
                ORA ZP_TMP_A
                STA ZP_TMP_A
                LDA ZP_TMP_A+1
                ORA #>heap_ptr
                TAY
                LDX ZP_TMP_A
                RTS    


             
                
                
        

