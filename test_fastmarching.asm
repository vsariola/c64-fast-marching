START_LOC = 10+32*15 ; $01EF
START_LOC2 = 22+32*15 ; 
START_LOC3 = 15+32*20 ; 

; 10 SYS4096

* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00


* = $1000       
                ;JSR fmm_dump
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed
                LDX #<START_LOC2
                LDY #>START_LOC2
                JSR fmm_seed
                LDX #<START_LOC3
                LDY #>START_LOC3
                JSR fmm_seed
                JSR fmm_dump
                JSR fmm_run

                JSR fmm_dump
@loop           JMP @loop
                JSR fmm_reset    
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed      
                JSR fmm_run
                JSR fmm_dump

incasm fastmarching.asm
incasm binaryheap.asm

