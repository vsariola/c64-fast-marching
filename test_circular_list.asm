* = $2000
incasm "circular_list.asm"

* = $0801
        LDA #16
        JSR list_init
        LDX #16
        list_getnext
        LDA #0
        JSR list_move
        LDX #16
        list_getnext
        LDA #0
        JSR list_move
        LDX #16
        list_getnext
        LDA #1
        JSR list_move
        LDX #1
        list_getnext
        LDA #16
        JSR list_move
        BRK
