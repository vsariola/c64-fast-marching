# c64-fast-marching

c64-fast-marching is an implementation of 2D [fast marching method](https://en.wikipedia.org/wiki/Fast_marching_method) in 6502 assembly, particularly targeting the C64 platform.

## Background

The fast marching method solves the eikonal equation:

abs(nabla u(x)) = 1/f(x) for x in S

u(x) = 0 for x on the boundary of S

The solution u(x) can be thought as the minimum time needed to reach point x from the boundary and f(x) is the speed of moving at point x. The fast marching method can be used for:

- Path finding with the Euclidian norm. It finds the shortest path from the boundary to all cells, similar to uninformed Djikstra. Typically, the boundary is a point, for example the player character of a game. This kind of path finding is better suited for e.g. strategy games where one should show preview to the user, which cells can be reached by the character before taking an action. f(x) can depend on the type of the cell, to make some cells slower to pass through than others.
- Line of sight calculations. Run the fast marching method twice with the player as the seed. In one run, treat all walls as unpassable and in another run, treat them as passable. Then compare the arrival times of these two runs. If the arrival time of a cell with the walls is larger than the arrival time without the walls, that means that some wall is blocking the line of sight.
- Dynamic shadows. This is basically the same thing as line of sight calculations, with the light source as the seed. However, as an added bonus, we have just computed the distance to the light source, which can be useful for shading i.e. making the light dimmer as we are further away from it.

## Features

- Runs in O(N), N = number of cells visited. Original fast marching method, developed by J.A. Sethian, runs in O(N log N) time. The log N comes from the fact that considered cells are kept in a priority queue. L. Yatsiv, A. Bartesaghi and G. Sapiro proposed keeping the cells in a finite number of bins. In each bin, all cells have their priorities close to each other. When dequeuing, we take any cell from the lowest priority bin, which is O(1), so the whole algorithm became O(N). Here we take this idea slightly further, in that when we accept the cell, the assigned arrival time is the rounded, bin value. The implications of this rounding are not fully explored, but it seems to work :) I assume that on average, these rounding errors tend to cancel out.
- Supports arbitary size grid (up to memory limitations). The grid size is set by defining the variables FMM_WIDTH and FMM_HEIGHT. In particular, a 40 x 25 grid is convenient for the text mode. The only limitation is that the width of the grid should be <= 126.
- Features a programmable pipeline: the user can change where the algorithm reads the input map and where it writes outputs the arrival times. The algorithm also has a user-definable callback function which translates the input map into the speed values f(x). For example, line of sight calculations that need to run the algorithm twice do not need modify the input map at all - just change the output map and callback between the runs.
- Reasonably small memory print: apart from the output map and input maps, which are FMM_WIDTH \* FMM_HEIGHT, the algorithm needs only 1 kb of temporary memory, which is can be used freely after the algorithm is finished. Currently the code is less than 512b.
- Uses 8-bit integer math for all operations. The maximum arrival time is 249, inclusive. For example, if f = 1/15, this means that the algorithm can find a path with a distance less than 16.6 cells. Smaller f values can be used to increase path length; however, precision is then lost from norm and for example the Euclidian norm starts to become more like the taxicab-norm.
- Reasonably well-optimized: running with a maximum time horizon of 249 and f = 1/15 takes around 250k cycles i.e. about 250 ms on C64. With smaller time horizons, the line of sight calculations can probably be made fast enough for a turn-based roguelike.

## Installation

The project has been written and tested on the [CBM prg studio](https://www.ajordison.co.uk). Quickest way to get started is to install CBM prg studio, open c64-fast-marching.cbmprj and build one of the test_\*.asm files.

Note! Do not try to build the project, it won't build. All the test_\*.asm files are excluded from the project build and the main file - fast-marching.asm - is meant to be used as a library i.e. does not have a starting address.

## Quick example

Quick example from [example_simple.asm](example_simple.asm):

```asm  
FMM_WIDTH = 40   ; the width of the grid is 40 cells
FMM_HEIGHT = 25  ; the height of the grid is 25 cells

START_LOC = 10 + FMM_WIDTH*10        ; algorithm will start from coordinates X = 10, Y = 10
screen_mem = $0400  ; we'll output the arrival times directly to screen memory for quick visualization

* = $1900
incasm "fast_marching.asm"

; 10 SYS4096
* = $0801
        BYTE    $0B, $08, $0A, $00, $9E, $34, $30, $39, $36, $00, $00, $00

* = $1000       
                fmm_setmaps map,screen_mem  ; map is the input, screen_mem is the output
                fmm_setcallback callback    ; set the callback that translates the map values into f values
                JSR fmm_reset               ; resets the internal arrays and output array
                LDX #<START_LOC
                LDY #>START_LOC
                JSR fmm_seed                ; algorithm starts from X = 10, Y = 10               
                JSR fmm_run                 ; run the algorithm
@loop           JMP @loop
                       
callback        LDA (fmm_zp_input),y ; read the map
                CMP #32              ; in this map, 32 is empty, everything else is wall
                BNE @wall
@do_lookup      LDA lookup,x         ; return the slowness of the cell
                fmm_inlinecontinue   ; this is a macro
@wall           RTS                  ; was a wall, return and skip the cell
lookup          byte 11,10,10,9,8,8,7,7,6,5,4,4,3,2,1,0,15

Align
map             dcb 40,0    ; this is a minimal map that has the top and bottom 
                dcb 920,32  ; edges with walls to prevent the algorithm from 
                dcb 40,0    ; happily overwriting the memory
```

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License
[MIT](LICENSE)
