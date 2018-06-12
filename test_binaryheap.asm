* = $1000
                LDX #<heap_ptr
                LDY #>heap_ptr
                LDA #3
                JSR queue_insert

                LDX #<heap_ptr+1
                LDY #>heap_ptr
                LDA #4
                JSR queue_insert

                LDX #<heap_ptr+2
                LDY #>heap_ptr
                LDA #2
                JSR queue_insert

                LDX #<heap_ptr+3
                LDY #>heap_ptr
                LDA #1
                JSR queue_insert

                LDX #<heap_ptr+4
                LDY #>heap_ptr
                LDA #5
                JSR queue_insert

                JSR queue_deletemin

                JSR queue_clear

                LDX #<heap_ptr+3
                LDY #>heap_ptr
                LDA #2
                JSR queue_insert

                LDX #<heap_ptr+3
                LDY #>heap_ptr
                LDA #1

                JSR queue_insert

                BRK

incasm binaryheap.asm

Align
heap_ptr        dcb 512,0