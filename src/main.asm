.INCDIR         "./src/"
.INCLUDE        "include/mem.wla"
.INCLUDE        "include/ram.wla"
.INCLUDE        "include/constants.asm"

;===============================================================================
; SEGA ROM Header
;===============================================================================
; compute the checksum too
.SMSHEADER
        PRODUCTCODE     26, 7, 2
        VERSION         0
        REGIONCODE      4               ; SMS Export EU.
        RESERVEDSPACE   0xFF, 0xFF
        ROMSIZE         0xC             ; 32KB
.ENDSMS


;===============================================================================
; Z-80 starts here
;===============================================================================
.BANK 0 SLOT 0
.ORG $0000
        di                              ; Disable interrupts.
        im      1                       ; Interrupt mode 1.
        jp      f_init                  ; Jump to main program.


;===============================================================================
; VBLANK/HBLANK interrupt handler
;===============================================================================
.ORG $0038
        di                              ; Disable interrupt.
        call    f_vdp_iHandler          ; Process interrupt.
        ei                              ; Enable interrupt.
        ret


;===============================================================================
; NMI (Pause Button) interrupt handler
;===============================================================================
.ORG $0066
        call    f_pause_iHandler
        retn                            ; Return and acquit NMI.


;===============================================================================
; INIT
;===============================================================================
.ORG $0100
f_init:
        ld      sp, $DFF0               ; Init stack pointer.

        ; ====== Clear RAM.
        ld      a, $00
        ld      (SMS_RAM_ADDRESS), a    ; Load the value 0 to the RAM at $C000
        ld      hl, SMS_RAM_ADDRESS     ; Starting cleaning at $C000
        ld      de, SMS_RAM_ADDRESS + 1 ; Destination: next address in RAM.
        ld      bc, $1FFF               ; Copy 8191 bytes. $C000 to $DFFF.
        ldir

        ; ====== Clear VRAM.
        ld      a, $00                  ; VRAM write address to 0.
        out     (SMS_PORTS_VDP_COMMAND), a
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      bc, $4000               ; Output 16KB of zeroes.
@loop_clear_vram:
                ld      a, $00                  ; Value to write.
                out     (SMS_PORTS_VDP_DATA), a ; Auto-incremented after each write.
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_clear_vram

        ; ====== Init VDP Registers.
        call    f_VDPInitialisation

        ; ====== Load Snake palette.
        ld      hl, plt_SnakeTiles
        ld      b, plt_SnakeTilesSize
        ld      a, 0
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a
@loop_load_plt:
        ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        dec     b
        jp      nz, @loop_load_plt

        ; ====== Load Snake tiles.
        ld      a, $00
        out     (SMS_PORTS_VDP_COMMAND), a
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      hl, tiles_snake
        ld      bc, tiles_snakeSize
@loop_load_tiles:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_load_tiles

        ; ====== Draw field.
        call    f_draw_field

        ; ====== Init variables.
        ld      a, SNAKE_DEFAULT_SPEED
        ld      (RAM_SNAKE_SPEED), a

        ld      hl, $3910               ; snake tail starting position.
        ld      (RAM_SNAKE_TAIL_MEM_POS), hl
        ld      (RAM_SNAKE_HEAD_OLD_MEM_POS), hl

        ld      hl, $3912               ; snake head starting position.
        ld      (RAM_SNAKE_HEAD_MEM_POS), hl

        ld      a, $00
        ld      (RAM_SNAKE_TAIL_X_POS), a
        ld      (RAM_SNAKE_TAIL_Y_POS), a
        ld      (RAM_SNAKE_HEAD_Y_POS), a
        ld      (RAM_PALETTE_SWITCH),   a
        ld      (RAM_APPLE_EATEN), a

        ld      a, $01
        ld      (RAM_SNAKE_HEAD_X_POS), a
        ld      (RAM_VDP_ROUTINE_DONE), a

        ld      a, GOING_RIGHT
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        ld      (RAM_SNAKE_DIRECTION), a
        ld      (RAM_SNAKE_OLD_DIRECTION), a
        ld      (RAM_SNAKE_TAIL_DIRECTION), a

        ld      a, SEED                 ; load the seed at compiling. CHANGE ME.
        ld      (RAM_RNG_VALUE), a

        call    f_make_apple

        ; ====== enable screen.
        ld      a, %11100000
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_REGISTER_1
        out     (SMS_PORTS_VDP_COMMAND), a

        ; ====== Enable interrupt.
        ei

        ; ====== Start Game.
        jp      f_main_loop


;===============================================================================
; MAIN
;===============================================================================
f_main_loop:

        ; ====== Loop until new frame occur.
        ld      a, (RAM_VDP_ROUTINE_DONE)
        cp      $01
        jr      nz, f_main_loop
        ld      a, $00
        ld      (RAM_VDP_ROUTINE_DONE), a

        ; ====== Check joypad direction.
        call    f_read_joypad

        ; ====== Check timer reached.
        ld      a, (RAM_FRAME_COUNTER)
        ld      hl, RAM_SNAKE_SPEED
        cp      (hl)
        jp      nz, @end_main_loop      ; If timer is not reached:

        ; ====== Set the new snake direction.
        ld      a, (RAM_SNAKE_DIRECTION)
        ld      (RAM_SNAKE_OLD_DIRECTION), a
        ld      a, (RAM_SNAKE_NEXT_DIRECTION)
        ld      (RAM_SNAKE_DIRECTION), a

        ; ====== Compute the next movement.
        ld      a, (RAM_SNAKE_HEAD_X_POS)
        ld      b, a
        ld      a, (RAM_SNAKE_HEAD_Y_POS)
        ld      c, a
        ld      a, (RAM_SNAKE_DIRECTION)
        ld      hl, (RAM_SNAKE_HEAD_MEM_POS)
        call    f_compute_body_movement
        ld      a, b
        ld      (RAM_SNAKE_HEAD_NEXT_X_POS), a
        ld      a, c
        ld      (RAM_SNAKE_HEAD_NEXT_Y_POS), a
        ld      (RAM_SNAKE_HEAD_NEXT_MEM_POS), hl

        ; ====== Check collision for the next movement.
        call    f_detect_collision

        ; ====== Move the head.
        call    f_move_snake_head

        ; ====== Move the tail.
        call    f_move_snake_tail

        ; ====== Generate a new apple if we've eaten one.
        ld      a, (RAM_APPLE_EATEN)
        cp      $01
        jp      nz, @no_apple_eaten
        ld      a, $00
        ld      (RAM_APPLE_EATEN), a
        call    f_make_apple

        ; and increase snake's speed.
        ld      hl, RAM_SNAKE_SPEED
        ld      a, (hl)
        cp      SNAKE_MAX_SPEED
        jp      c, @no_apple_eaten
        dec     (hl)                    ; Increase snake speed.
@no_apple_eaten:

        ; ====== Flush frame counter.
        ld      a, $00
        ld      (RAM_FRAME_COUNTER), a

        ; ====== End main loop.
@end_main_loop:
        ld      a, $01
        ld      (RAM_GAME_ROUTINE_DONE), a
        jp      f_main_loop


;===============================================================================
; Function to read joypad inputs for snake direction
;===============================================================================
f_read_joypad:
        in      a, (SMS_PORT_JOY1)

        bit     JOYPAD_P1_UP, a
        jr      z, @joypad_up_pressed

        bit     JOYPAD_P1_DOWN, a
        jr      z, @joypad_down_pressed

        bit     JOYPAD_P1_LEFT, a
        jr      z, @joypad_left_pressed

        bit     JOYPAD_P1_RIGHT, a
        jr      z, @joypad_right_pressed

        jr      @end_joypad_input_check

@joypad_up_pressed:
        ld      a, (RAM_SNAKE_DIRECTION)
        cp      GOING_DOWN
        jr      z, @end_joypad_input_check
        ld      a, GOING_UP
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        jr      @end_joypad_input_check

@joypad_down_pressed:
        ld      a, (RAM_SNAKE_DIRECTION)
        cp      GOING_UP
        jr      z, @end_joypad_input_check
        ld      a, GOING_DOWN
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        jr      @end_joypad_input_check

@joypad_left_pressed:
        ld      a, (RAM_SNAKE_DIRECTION)
        cp      GOING_RIGHT
        jr      z, @end_joypad_input_check
        ld      a, GOING_LEFT
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        jr      @end_joypad_input_check

@joypad_right_pressed:
        ld      a, (RAM_SNAKE_DIRECTION)
        cp      GOING_LEFT
        jr      z, @end_joypad_input_check
        ld      a, GOING_RIGHT
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        jr      @end_joypad_input_check

@end_joypad_input_check:
        ret


;===============================================================================
; Function to compute the next body movement.
; in    a:      BODY_DIRECTION
; in    b:      BODY_X_POS
; in    c:      BODY_Y_POS
; in    hl:     BODY_MEM_POS
;===============================================================================
f_compute_body_movement:
        cp      GOING_UP
        jr      z, @moving_up

        cp      GOING_DOWN
        jr      z, @moving_down

        cp      GOING_LEFT
        jr      z, @moving_left

        cp      GOING_RIGHT
        jr      z, @moving_right

@moving_up:
        dec     c
        ld      a, l
        sub     $40
        ld      l, a
        jr      nc, @moving_up_no_borrow
        dec     h
@moving_up_no_borrow:
        jr      @end_moving

@moving_down:
        inc     c
        ld      de, $40
        add     hl, de
        jr      @end_moving

@moving_left:
        dec     b
        ld      a, l
        sub     $02
        ld      l, a
        jr      nc, @moving_left_no_borrow
        dec     h
@moving_left_no_borrow:
        jr      @end_moving

@moving_right:
        inc     b
        ld      de, $02
        add     hl, de
        jr      @end_moving

@end_moving:
        ret


;===============================================================================
; Function to move snake's head
;===============================================================================
f_move_snake_head:
        ; The current head position is now the old position.
        ld      a, (RAM_SNAKE_HEAD_X_POS)
        ld      (RAM_SNAKE_HEAD_OLD_X_POS), a
        ld      a, (RAM_SNAKE_HEAD_Y_POS)
        ld      (RAM_SNAKE_HEAD_OLD_Y_POS), a
        ld      de, (RAM_SNAKE_HEAD_MEM_POS)
        ld      (RAM_SNAKE_HEAD_OLD_MEM_POS), de

        ; Update snake array with the current direction
        ; at current head position.
        ld      hl, RAM_SNAKE_HEAD_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_HEAD_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (RAM_SNAKE_DIRECTION)
        ld      (hl), a

        ; Indicates that an apple has been eaten here.
        ld      a, (RAM_APPLE_EATEN)
        cp      $01
        jp      nz, @no_apple_eaten
        ld      a, (hl)
        or      %10000000               ; set 7th bit
        ld      (hl), a
@no_apple_eaten:

        ; Move the snake head.
        ld      a, (RAM_SNAKE_HEAD_NEXT_X_POS)
        ld      (RAM_SNAKE_HEAD_X_POS), a
        ld      a, (RAM_SNAKE_HEAD_NEXT_Y_POS)
        ld      (RAM_SNAKE_HEAD_Y_POS), a
        ld      de, (RAM_SNAKE_HEAD_NEXT_MEM_POS)
        ld      (RAM_SNAKE_HEAD_MEM_POS), de

        ret


;===============================================================================
; Function to move snake's tail
;===============================================================================
f_move_snake_tail:
        ; Check if an apple is digested here.
        ld      hl, RAM_SNAKE_TAIL_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_TAIL_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)

        bit     7, a                    ; if we eaten an apple, the 7th bit is set.
        jr      z, @no_apple_digested
        and     %01111111               ; unset it.
        ld      (hl), a
        jr      @end_f_move_snake_tail

@no_apple_digested:
        ; The current tail position is now the old position.
        ld      a, (RAM_SNAKE_TAIL_X_POS)
        ld      (RAM_SNAKE_TAIL_OLD_X_POS), a
        ld      a, (RAM_SNAKE_TAIL_Y_POS)
        ld      (RAM_SNAKE_TAIL_OLD_Y_POS), a
        ld      de, (RAM_SNAKE_TAIL_MEM_POS)
        ld      (RAM_SNAKE_TAIL_OLD_MEM_POS), de

        ; Flush current tail position in the snake array.
        ld      hl, RAM_SNAKE_TAIL_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_TAIL_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, $00
        ld      (hl), a

        ; Moving the snake tail.
        ld      a, (RAM_SNAKE_TAIL_X_POS)
        ld      b, a
        ld      a, (RAM_SNAKE_TAIL_Y_POS)
        ld      c, a
        ld      a, (RAM_SNAKE_TAIL_DIRECTION)
        ld      hl, (RAM_SNAKE_TAIL_MEM_POS)
        call    f_compute_body_movement
        ld      a, b
        ld      (RAM_SNAKE_TAIL_X_POS), a
        ld      a, c
        ld      (RAM_SNAKE_TAIL_Y_POS), a
        ld      (RAM_SNAKE_TAIL_MEM_POS), hl

        ; Update the tail direction based on value in snake array.
        ld      hl, RAM_SNAKE_TAIL_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_TAIL_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)
        and     %01111111               ; Set the new direction, without the Apple information.
        ld      (RAM_SNAKE_TAIL_DIRECTION), a

@end_f_move_snake_tail:
        ret


;===============================================================================
; Function to detect a collision
;===============================================================================
f_detect_collision:
        ; Detecte Edge collision.
        ld      a, (RAM_SNAKE_HEAD_NEXT_X_POS)
        cp      LEFT_BORDER
        jr      z, @collision_triggered
        cp      RIGHT_BORDER
        jr      z, @collision_triggered

        ld      a, (RAM_SNAKE_HEAD_NEXT_Y_POS)
        cp      DOWN_BORDER
        jr      z, @collision_triggered
        cp      UP_BORDER
        jr      z, @collision_triggered

        ; Detecte Apple collision.
        ld      hl, RAM_SNAKE_HEAD_NEXT_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_HEAD_NEXT_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)

        cp      APPLE
        jr      z, @apple_eaten

        ; Detecte snake collision
        cp      $00
        jr      nz, @collision_triggered

        ret

@apple_eaten:
        ld      a, $01
        ld      (RAM_APPLE_EATEN), a
        ret

@collision_triggered:
        RST     $00                     ; For now, we just reset PC.


;===============================================================================
; Function to compute index based on X and Y position.
; in    B: Position X
; in    C: Position Y
; out   HL = Y * 16 + X
;===============================================================================
f_compute_array_index_from_position:
        ; multiply Y by 16.
        ld      hl, $0000
        ld      l, c
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl

        ; add Y*16 + X
        ld      de, $0000
        ld      e, b
        add     hl, de
        ret


;===============================================================================
; Function to compute position X and Y based on index.
; in    A: index
; out   B: Position X
; out   C: Position Y
;===============================================================================
f_compute_position_from_array_index:
        ld      c, $00
@start_compute_index:
        cp      16
        jp      c, @end_compute_index
        sub     16
        inc     c
        jp      @start_compute_index
@end_compute_index:
        ld      b, a
        ret


;===============================================================================
; Function to generate a new apple
;===============================================================================
f_make_apple:
        ld      b, $00

@search_random_empty_space:
        ; ====== Ask a new random position.
        ld      hl, RAM_RNG_VALUE
        call    f_get_new_random_value
        inc     b
        ld      a, b

        ; Checks how many loops we've made.
        ; If we loop 255 times, there is no empty space anymore in the field.
        ; it's a property of LFSR: you can't generate the same number twice without looping.
        cp      $ff
        jp      z, @no_more_space

        ; ====== Check if the position is empty (no snake body).
        ld      hl, $0000
        ld      a, (RAM_RNG_VALUE)
        ld      l, a
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)
        cp      $00
        jp      nz, @search_random_empty_space

        ; ====== Reserve space for apple.
        ld      (hl), APPLE

        ; ====== Determines position relative to index.
        ld      a, (RAM_RNG_VALUE)
        call    f_compute_position_from_array_index
        ld      hl, RAM_APPLE_X_POS
        ld      (hl), b
        ld      hl, RAM_APPLE_Y_POS
        ld      (hl), c

        ; ====== Determines where to draw apple from position.
        call    f_compute_vdp_memory_addr
        ld      (RAM_APPLE_MEM_POS), hl

        ret

@no_more_space:
        RST     $00                     ; For now, we just reset PC.


;===============================================================================
; Function to compute VDP address based on X and Y position.
; in    B: Position X
; in    C: Position Y
; out   HL = VDP VRAM ADDR
;            $3800 + ((Y+4) * 32 + (X + 8)) * 2 bytes
;===============================================================================
f_compute_vdp_memory_addr:
        ld      a, c
        add     a, $04

        ; multiply Y by 32.
        ld      hl, $0000
        ld      l, a
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl
        add     hl, hl

        ; add X + 8

        ld      a, b
        add     a, $08
        ld      de, $0000
        ld      e, a
        add     hl, de

        ; *2 bytes
        add     hl, hl
        ld      de, $3800
        add     hl, de
        ret


;===============================================================================
; Function to return random value (8 bits).
; in    HL: seed
; out   (hl): new random value
;===============================================================================
f_get_new_random_value:
        ld      a, (hl)
@loop_lfsr:
        sla     a
        jr      nc, @loop_lfsr_no_xor
        xor     $1d                     ; best taps for lfsr on 8 bits.
@loop_lfsr_no_xor:
        ld      (hl), a
        ret


;===============================================================================
; Function to draw field's borders.
;===============================================================================
f_draw_field:
        ; ====== Draw corners ==========
        ld      ix, addr_field_corners
        ld      b, $04                  ; How many corner we must to draw.
@loop_draw_field_corner:
                ld      l, (ix+0)       ; Load the low byte VDP address.
                ld      h, (ix+1)       ; Load the high byte VDP address.

                ; Draw corner tile in VDP memory.
                ld      a, l
                out     (SMS_PORTS_VDP_COMMAND), a
                ld      a, h
                or      SMS_VDP_WRITE_RAM
                out     (SMS_PORTS_VDP_COMMAND), a
                ld      a, $01
                out     (SMS_PORTS_VDP_DATA), a
                ld      a, (ix+2)       ; Load tile property.
                out     (SMS_PORTS_VDP_DATA), a
                dec     b
                ld      de, $04
                add     ix, de
                jp      nz, @loop_draw_field_corner

        ; ====== Draw borders ==========
        ld      ix, addr_field_borders
        ld      b, $04                  ; How many borders we must draw.
@loop_draw_all_field_borders:
                ld      l, (ix+0)               ; Load the low byte VDP address.
                ld      h, (ix+1)               ; Load the high byte VDP address.
                ld      c, $10                  ; How many tile per border we must draw.
@loop_draw_border:
                        ld      d, (ix+2)               ; load tile number.
                        ld      e, (ix+4)               ; load tile property.
                        ld      a, l
                        out     (SMS_PORTS_VDP_COMMAND), a
                        ld      a, h
                        or      SMS_VDP_WRITE_RAM
                        out     (SMS_PORTS_VDP_COMMAND), a
                        ld      a, d
                        out     (SMS_PORTS_VDP_DATA), a
                        ld      a, e
                        out     (SMS_PORTS_VDP_DATA), a
                        ld      e, (ix+6)               ; load addr increment.
                        ld      d, $00
                        add     hl, de
                        dec     c
                        jp      nz, @loop_draw_border

                dec     b
                ld      d, $00
                ld      de, $08
                add     ix, de
                jp      nz, @loop_draw_all_field_borders

        ret


;===============================================================================
; Function triggered when VDP sent interrupt signal.
;===============================================================================
f_vdp_iHandler:
        ; saves registers on the stack
        push    af
        push    bc
        push    de
        push    hl

        ; read interrupt variables.
        in      a, (SMS_PORTS_VDP_STATUS) ; Retrieve from the VDP what interrupted us.
        and     %10000000               ; VDP Interrupt information.
                ;x.......               ; 1: VBLANK Interrupt, 0: H-Line Interrupt [if enabled].
                ;.X......               ; 9 sprites on a raster line.
                ;..x.....               ; Sprite Collision.
        jr      nz, @vblank_handler

@hblank_handler:
        ; ====== HBlank_Handler here ===
        nop
        jp      @f_vdp_iHandler_end

        ; ====== VBlank_Handler here ===
@vblank_handler:

        ; ====== Check if game logic done working.
        ld      a, (RAM_GAME_ROUTINE_DONE)
        cp      $01
        jp      nz, @f_vdp_iHandler_end
        ld      a, $00
        ld      (RAM_GAME_ROUTINE_DONE), a

        ; ====== Update frame counter ==
        ld      hl, RAM_FRAME_COUNTER
        inc     (hl)

        ; yes:
        ; flush old snake tail position.
        ld      hl, (RAM_SNAKE_TAIL_OLD_MEM_POS)
        ld      bc, $0000
        call    f_draw_tile

        ; Draw snake head in VRAM.
        ld      hl, (RAM_SNAKE_HEAD_OLD_MEM_POS)
        ld      a, (RAM_SNAKE_DIRECTION)

        cp      GOING_UP
        jr      z, @snake_moving_up

        cp      GOING_DOWN
        jp      z, @snake_moving_down

        cp      GOING_LEFT
        jp      z, @snake_moving_left

        cp      GOING_RIGHT
        jp      z, @snake_moving_right

@snake_moving_up:
        ld      a, (RAM_SNAKE_OLD_DIRECTION)

        cp      GOING_UP
        jr      z, @snake_moving_up_from_up

        cp      GOING_LEFT
        jr      z, @snake_moving_up_from_left

        cp      GOING_RIGHT
        jr      z, @snake_moving_up_from_right

        @snake_moving_up_from_up:
                ld      bc, $0700
                call    f_draw_tile
                jr      @end_snake_moving_up
        @snake_moving_up_from_left:
                ld      bc, $0A06
                call    f_draw_tile
                jr      @end_snake_moving_up
        @snake_moving_up_from_right:
                ld      bc, $0A04
                call    f_draw_tile
                jr      @end_snake_moving_up

        @end_snake_moving_up:
                ld      bc, $0500
                jp      @draw_snake_head

@snake_moving_down:
        ld      a, (RAM_SNAKE_OLD_DIRECTION)

        cp      GOING_DOWN
        jr      z, @snake_moving_down_from_down

        cp      GOING_LEFT
        jr      z, @snake_moving_down_from_left

        cp      GOING_RIGHT
        jr      z, @snake_moving_down_from_right

        @snake_moving_down_from_down:
                ld      bc, $0704
                call    f_draw_tile
                jr      @end_snake_moving_down
        @snake_moving_down_from_left:
                ld      bc, $0A02
                call    f_draw_tile
                jr      @end_snake_moving_down
        @snake_moving_down_from_right:
                ld      bc, $0A00
                call    f_draw_tile
                jr      @end_snake_moving_down

        @end_snake_moving_down:
                ld      bc, $0504
                jp      @draw_snake_head

@snake_moving_left:
        ld      a, (RAM_SNAKE_OLD_DIRECTION)

        cp      GOING_UP
        jr      z, @snake_moving_left_from_up

        cp      GOING_DOWN
        jr      z, @snake_moving_left_from_down

        cp      GOING_LEFT
        jr      z, @snake_moving_left_from_left

        @snake_moving_left_from_up:
                ld      bc, $0902
                call    f_draw_tile
                jr      @end_snake_moving_left
        @snake_moving_left_from_down:
                ld      bc, $0906
                call    f_draw_tile
                jr      @end_snake_moving_left
        @snake_moving_left_from_left:
                ld      bc, $0802
                call    f_draw_tile
                jr      @end_snake_moving_left

        @end_snake_moving_left:
                ld      bc, $0602
                jp      @draw_snake_head

@snake_moving_right:
        ld      a, (RAM_SNAKE_OLD_DIRECTION)

        cp      GOING_UP
        jr      z, @snake_moving_right_from_up

        cp      GOING_DOWN
        jr      z, @snake_moving_right_from_down

        cp      GOING_RIGHT
        jr      z, @snake_moving_right_from_right

        @snake_moving_right_from_up:
                ld      bc, $0900
                call    f_draw_tile
                jr      @end_snake_moving_right
        @snake_moving_right_from_down:
                ld      bc, $0904
                call    f_draw_tile
                jr      @end_snake_moving_right
        @snake_moving_right_from_right:
                ld      bc, $0800
                call    f_draw_tile
                jr      @end_snake_moving_right

        @end_snake_moving_right:
                ld      bc, $0600
                jp      @draw_snake_head

@draw_snake_head:
        ld      hl, (RAM_SNAKE_HEAD_MEM_POS)
        call    f_draw_tile

        ; Draw snake tail in VRAM.
        ld      a, (RAM_SNAKE_TAIL_DIRECTION)

        cp      GOING_UP
        jr      z, @tail_going_up

        cp      GOING_DOWN
        jr      z, @tail_going_down

        cp      GOING_LEFT
        jr      z, @tail_going_left

        cp      GOING_RIGHT
        jr      z, @tail_going_right

@tail_going_up:
        ld      bc, $0F00
        jr      @draw_snake_tail
@tail_going_down:
        ld      bc, $0F04
        jr      @draw_snake_tail
@tail_going_left:
        ld      bc, $1000
        jr      @draw_snake_tail
@tail_going_right:
        ld      bc, $1002
        jr      @draw_snake_tail

@draw_snake_tail:
        ld      hl, (RAM_SNAKE_TAIL_MEM_POS)
        call    f_draw_tile

        ; Draw apple.
        ld      hl, (RAM_APPLE_MEM_POS)
        ld      bc, $0400
        call    f_draw_tile

        ; We finished the VDP taff.
        ld      a, $01
        ld      (RAM_VDP_ROUTINE_DONE), a

@f_vdp_iHandler_end:
        ; set back registers from the stack
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret


;===============================================================================
; Function to draw a tile in VRAM.
; in    hl:     VRAM Addr
; in    b:      Tile ID
; in    c:      Tile properties
;===============================================================================
f_draw_tile:
        ld      a, l
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, h
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, b
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, c
        out     (SMS_PORTS_VDP_DATA), a
        ret


;===============================================================================
; Function to handle what's going on when player press Pause button.
;===============================================================================
f_pause_iHandler:
        ld      a, (RAM_PALETTE_SWITCH)
        cp      $00
        jp      z, @load_nmi_plt

        ld      a, $00
        ld      (RAM_PALETTE_SWITCH), a

        ld      hl, plt_SnakeTiles
        ld      b, plt_SnakeTilesSize
        ld      a, 0
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a
        @loop_load_plt:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     b
                jp      nz, @loop_load_plt
        jp      @end_pauseHandler

@load_nmi_plt:
        ld      a, $01
        ld      (RAM_PALETTE_SWITCH), a

        ; ====== Load palette.
        ld      hl, plt_SnakeNmi
        ld      b, plt_SnakeNmiSize
        ld      a, 0
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a
        @loop_load_plt_nmi:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     b
                jp      nz, @loop_load_plt_nmi

@end_pauseHandler:
        retn


;===============================================================================
; VDP Initialisation function.
;===============================================================================
f_VDPInitialisation:
;===============================================================================
; Use to set all VDP registers to default values.
; For register => page 16 to 19 from official guide.
;-------------------------------------------------------------------------------
        ld      hl, @vdp_default_registers
        ld      b, (@vdp_default_registers_end - @vdp_default_registers)
@loop_init_vdp:
        ld      a, (hl)
        out     (SMS_PORTS_VDP_COMMAND), a
        inc     hl
        dec     b
        jp      nz, @loop_init_vdp
        ret

@vdp_default_registers:
        .byte   %00000100               ; VDP Reg#0
                ;X|||||||               ; Disable vertical scrolling for columns 24-31.
                ; X||||||               ; Disable horizontal scrolling for rows 0-1.
                ;  X|||||               ; Mask column 0 with overscan color from register #7.
                ;   X||||               ; (IE1) HBlank Interrupt enable.
                ;    X|||               ; (EC) Shift sprites left by 8 pixels.
                ;     X||               ; (M4)  1= Use Mode 4, 0= Use TMS9918 modes (selected with M1, M2, M3).
                ;      X|               ; (M2) Must be 1 for M1/M3 to change screen height in Mode 4.
                ;       X               ; 1= No sync, display is monochrome, 0= Normal display.
        .byte   SMS_VDP_REGISTER_0
        .byte   %10100000               ; VDP Reg#1
                ;X|||||||               ; Always to 1 (no effect).
                ; X||||||               ; (BLK) 1= Display visible, 0= display blanked.
                ;  X|||||               ; (IE) VBlank Interrupt enable.
                ;   X||||               ; (M1) Selects 224-line screen for Mode 4 if M2=1, else has no effect.
                ;    X|||               ; (M3) Selects 240-line screen for Mode 4 if M2=1, else has no effect.
                ;     X||               ; No effect.
                ;      X|               ; Sprites are 1=16x16,0=8x8 (TMS9918), Sprites are 1=8x16,0=8x8 (Mode 4).
                ;       X               ; Sprite pixels are doubled in size.
        .byte   SMS_VDP_REGISTER_1
        .byte   %11111111               ; VDP Reg#2 Screen Map Base Address $3800.
        .byte   SMS_VDP_REGISTER_2
        .byte   %11111111               ; VDP Reg#3 Always set to $FF.
        .byte   SMS_VDP_REGISTER_3
        .byte   %11111111               ; VDP Reg#4 Always set to $FF.
        .byte   SMS_VDP_REGISTER_4
        .byte   %11111111               ; VDP Reg#5 Base Address for Sprite Attribute Table.
        .byte   SMS_VDP_REGISTER_5
        .byte   %11111111               ; VDP Reg#6 Base Address for Sprite Pattern.
        .byte   SMS_VDP_REGISTER_6
        .byte   %00000000               ; VDP Reg#7 Border Color from second bank.
        .byte   SMS_VDP_REGISTER_7
        .byte   %00000000               ; VDP Reg#8 Horizontal Scroll Value.
        .byte   SMS_VDP_REGISTER_8
        .byte   %00000000               ; VDP Reg#9 Vertical Scroll Value.
        .byte   SMS_VDP_REGISTER_9
        .byte   %11111111               ; VDP Reg#10 Raster Line Interrupt.
        .byte   SMS_VDP_REGISTER_10
@vdp_default_registers_end:


;===============================================================================
; FIELD DATA
;
; field_corners: vdp address, tile property
; field_borders: VDP address, tile number, tile property, addr increment.
;===============================================================================
addr_field_corners:
.dw     $38CE, $0000
.dw     $38F0, $0002
.dw     $3D0E, $0004
.dw     $3D30, $0006

addr_field_borders:
.dw     $38D0, $0003, $0000, $0002
.dw     $3D10, $0003, $0004, $0002
.dw     $390E, $0002, $0000, $0040
.dw     $3930, $0002, $0002, $0040


;===============================================================================
; ASSETS DATA
;===============================================================================
plt_SnakeTiles:
.INCBIN "assets/palettes/snakeTiles.plt.bin" fsize plt_SnakeTilesSize

plt_SnakeNmi:
.INCBIN "assets/palettes/snake_nmi.plt.bin" fsize plt_SnakeNmiSize

tiles_snake:
.INCBIN "assets/tiles/snake.tileset.bin" fsize tiles_snakeSize
