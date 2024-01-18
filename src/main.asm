.INCDIR         "./src/"
.INCLUDE        "include/mem.wla"
.INCLUDE        "include/ram.wla"
.INCLUDE        "include/constants.asm"
.INCLUDE        "include/ascii.asm"


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


.BANK 0 SLOT 0
;===============================================================================
; Z-80 starts here
;===============================================================================
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
        ; Save registers.
        push    af
        push    bc
        push    de
        push    hl

        ; Check if we are already in pause.
        ld      a, (RAM_PAUSE)
        cp      TRUE
        jr      z, @already_in_pause
        call    f_pause_iHandler

@already_in_pause:
        ; Restaure registers.
        pop     hl
        pop     de
        pop     bc
        pop     af
        retn                            ; Return and acquit NMI.


;===============================================================================
; INIT
;===============================================================================
.ORG $0100
f_init:
        ld      sp, $DFF0               ; Init stack pointer.

        ; ====== Clear RAM.
        xor     a
        ld      (SMS_RAM_ADDRESS), a    ; Load the value 0 to the RAM at $C000
        ld      hl, SMS_RAM_ADDRESS     ; Starting cleaning at $C000
        ld      de, SMS_RAM_ADDRESS + 1 ; Destination: next address in RAM.
        ld      bc, $1FFF               ; Copy 8191 bytes. $C000 to $DFFF.
        ldir

        ; ====== Clear VRAM.
        xor     a                       ; VRAM write address to 0.
        out     (SMS_PORTS_VDP_COMMAND), a
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      bc, $4000               ; Output 16KB of zeroes.
@loop_clear_vram:
                xor     a               ; Value to write.
                out     (SMS_PORTS_VDP_DATA), a ; Auto-incremented after each write.
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_clear_vram

        ; ====== Init VDP Registers (screen disabled).
        call    f_VDPInitialisation

        ; ====== Setup Menu.
        jp      f_setup_menu_title


;===============================================================================
; Function to load asset for screen title.
;===============================================================================
f_setup_menu_title:
        ; ====== Init variables.
        xor     a
        ld      (RAM_MENU_CHOICE), a
        ld      (RAM_FRAME_COUNTER), a

        ; ====== Load Snake_Title tileset.
        ld      hl, tileset_snake_title
        ld      bc, tileset_snake_title_size
        ld      de, $0000
        call    f_load_asset

        ; ====== Load Snake_Title tilemap.
        ld      hl, tilemap_snake_title
        ld      bc, tilemap_snake_title_size
        ld      de, $3800
        call    f_load_asset

        ; ====== Draw Best score.
        ld      de, RAM_BEST_SCORE_THOUSANDS
        ld      hl, $3D26
        call    f_draw_score

        call    f_enable_screen         ; Enable screen and interrupt.

        ; ====== Load palette with fading effect.
        ld      hl, plt_snake_title
        ld      c, plt_snake_title_size
        call    f_fadeInScreen

        ; ====== Go menu loop.
        call    f_menu_loop


;===============================================================================
; Main loop for the main screen title.
;===============================================================================
f_menu_loop:
        ; ====== Waiting a new frame.
        halt

        ; ====== Read joypad input.
        call    f_read_joypad
        ld      a, (RAM_JOYPAD_INPUT)

        bit     JOYPAD_P1_UP, a
        jr      z, @joypad_up_pressed

        bit     JOYPAD_P1_DOWN, a
        jr      z, @joypad_down_pressed

        bit     JOYPAD_P1_B1, a
        jr      z, @joypad_b1_pressed

        jr      @end_read_joypad

@joypad_up_pressed:
        xor     a
        ld      (RAM_MENU_CHOICE), a
        jr      @end_read_joypad

@joypad_down_pressed:
        ld      a, $01
        ld      (RAM_MENU_CHOICE), a
        jr      @end_read_joypad

@joypad_b1_pressed:
        ld      hl, plt_snake_title
        ld      c, plt_snake_title_size
        call    f_fadeOutScreen

        ; Setup a little delay before loading the game.
        ld      b, 15
 -:     halt
        djnz    -

        ; Setup life here, before cleaning the RAM.
        ld      a, DEFAULT_LIFE
        ld      (RAM_LIFE), a

        call    f_setup_snake_game
@end_read_joypad:

        ; ====== Draw arrow on menu.
        ld      a, (RAM_MENU_CHOICE)
        cp      TRUE
        jr      nz, @menu_hard_mode

@menu_normal_mode:
        ld      hl, $3C96
        ld      bc, $4200
        halt
        call    f_draw_tile
        ld      hl, $3C16
        ld      bc, $0000
        halt
        call    f_draw_tile
        jr      @end_menu_choice

@menu_hard_mode:
        ld      hl, $3C16
        ld      bc, $4200
        halt
        call    f_draw_tile
        ld      hl, $3C96
        ld      bc, $0000
        halt
        call    f_draw_tile

@end_menu_choice:
        jp      f_menu_loop


;===============================================================================
; Function to load asset for the game.
;===============================================================================
f_setup_snake_game:
        call    f_disable_screen        ; Disable screen and interrupt.

        ; ====== Cleaning in-game variables (in case of a game over).
        xor     a
        ld      ($C00C), a      ; Load the value 0 to the RAM at $C00B
        ld      hl, $C00C       ; Starting cleaning at $C00B
        ld      de, $C00D       ; Destination: next address in RAM.
        ld      bc, $0121       ; Copy 289 bytes. $C00B to $C12C.
        ldir

        ; ====== Reset stack pointer.
        ld      sp, $DFF0

        ; ====== Load Snake tileset.
        ld      hl, tileset_snake
        ld      bc, tileset_snake_size
        ld      de, $0000
        call    f_load_asset

        ; ====== Load Snake tilemap.
        ld      hl, tilemap_snake
        ld      bc, tilemap_snake_size
        ld      de, $3800
        call    f_load_asset

        call    f_enable_screen

        ; ====== Load palette with fading effect.
        ld      hl, plt_snake
        ld      c, plt_snake_size
        call    f_fadeInScreen

        ; ====== Waiting for user's input.
        ld      hl, str_ready
        ld      b, str_ready_size
        call    f_draw_text
        call    f_wait_b1_pressed
        call    f_clean_draw_text

        ; ====== Init variables.
        ld      a, (RAM_FRAME_COUNTER)
        ld      (RAM_RNG_VALUE), a

        ld      a, (RAM_MENU_CHOICE)
        cp      TRUE
        jr      z, @hard_mode

@normal_mode:
        ld      a, SNAKE_DEFAULT_SPEED
        ld      (RAM_SNAKE_SPEED), a
        ld      a, NORMAL_MODE_POINT
        ld      (RAM_POINT_TO_ADD), a
        jr      @end_mode_choice

@hard_mode:
        ld      a, SNAKE_HARD_SPEED
        ld      (RAM_SNAKE_SPEED), a
        ld      a, HARD_MODE_POINT
        ld      (RAM_POINT_TO_ADD), a

@end_mode_choice:
        ld      hl, $3950               ; snake tail starting position in VRAM.
        ld      (RAM_SNAKE_TAIL_MEM_POS), hl
        ld      (RAM_SNAKE_HEAD_OLD_MEM_POS), hl

        ld      hl, $3952               ; snake head starting position in VRAM.
        ld      (RAM_SNAKE_HEAD_MEM_POS), hl

        xor     a
        ld      (RAM_SNAKE_TAIL_X_POS), a
        ld      (RAM_SNAKE_TAIL_Y_POS), a
        ld      (RAM_SNAKE_HEAD_Y_POS), a
        ld      (RAM_APPLE_EATEN), a
        ld      (RAM_FRAME_COUNTER), a

        ld      a, $01
        ld      (RAM_SNAKE_HEAD_X_POS), a
        ld      (RAM_INGAME), a

        ld      a, GOING_RIGHT
        ld      (RAM_SNAKE_NEXT_DIRECTION), a
        ld      (RAM_SNAKE_DIRECTION), a
        ld      (RAM_SNAKE_OLD_DIRECTION), a
        ld      (RAM_SNAKE_TAIL_DIRECTION), a

        call    f_make_apple

        call    f_main_game_loop


;===============================================================================
; Function for the main game looping.
;===============================================================================
f_main_game_loop:

        ; ====== Wait until new frame occure.
        halt

        ; ====== Read joypad input.
        call    f_read_joypad
        ld      a, (RAM_JOYPAD_INPUT)

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
        ; ====== Move snake if timer is reached.
        ld      a, (RAM_FRAME_COUNTER)
        ld      hl, RAM_SNAKE_SPEED
        cp      (hl)
        jp      nz, @end_main_game_loop
        call    f_move_snake
        xor     a
        ld      (RAM_FRAME_COUNTER), a  ; Flush frame counter.

@end_main_game_loop:
        ; end of the main loop.
        ld      a, $01
        ld      (RAM_GAME_ROUTINE_DONE), a
        jp      f_main_game_loop


;===============================================================================
; Function to move the snake.
;===============================================================================
f_move_snake:
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

        ; ====== Move the tail.
        call    f_move_snake_tail

        ; ====== Check collision for the next movement.
        call    f_detect_collision

        ; ====== Move the head.
        call    f_move_snake_head

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

        ; ====== Generate a new apple if we've eaten one.
        ld      a, (RAM_APPLE_EATEN)
        cp      $01
        jp      nz, @no_apple_eaten
        xor     a
        ld      (RAM_APPLE_EATEN), a
        call    f_make_apple
        ld      a, (RAM_POINT_TO_ADD)
        ld      b, a
        call    f_increase_score

        ; and increase snake's speed.
        ld      hl, RAM_SNAKE_SPEED
        ld      a, (hl)
        cp      SNAKE_MAX_SPEED
        jp      c, @no_apple_eaten
        dec     (hl)
@no_apple_eaten:
        ret


;===============================================================================
; Function to read joypad inputs for snake direction.
;===============================================================================
f_read_joypad:
        in      a, (SMS_PORT_JOY1)
        ld      (RAM_JOYPAD_INPUT), a
        ret


;===============================================================================
; Function to wait until B1 pressed.
;===============================================================================
f_wait_b1_pressed:
        call    f_read_joypad
        ld      a, (RAM_JOYPAD_INPUT)

        bit     JOYPAD_P1_B1, a
        jr      z, @b1_pressed
        jr      f_wait_b1_pressed

@b1_pressed:
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
; Function to move snake's head.
;===============================================================================
f_move_snake_head:
        ; The current head position is now the old position.
        ld      a, (RAM_SNAKE_HEAD_X_POS)
        ld      (RAM_SNAKE_HEAD_OLD_X_POS), a
        ld      a, (RAM_SNAKE_HEAD_Y_POS)
        ld      (RAM_SNAKE_HEAD_OLD_Y_POS), a
        ld      de, (RAM_SNAKE_HEAD_MEM_POS)
        ld      (RAM_SNAKE_HEAD_OLD_MEM_POS), de

        ; Update snake array with the current direction.
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
; Function to move snake's tail.
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

@end_f_move_snake_tail:
        ret


;===============================================================================
; Function to detect a collision.
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

        ; Detecte snake collision.
        cp      $00
        jr      nz, @collision_triggered

        ret

@apple_eaten:
        ld      a, $01
        ld      (RAM_APPLE_EATEN), a
        ret

@collision_triggered:
        ; Draws a cross where the collision occurs
        ld      hl, (RAM_SNAKE_HEAD_NEXT_MEM_POS)
        ld      bc, $5000
        call    f_draw_tile
        call    f_game_over


;===============================================================================
; Function to generate a new apple.
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
        cp      $FF
        jr      z, @no_more_space

        ; ====== Check if the position is empty (no snake body).
        ld      hl, $0000
        ld      a, (RAM_RNG_VALUE)
        ld      l, a
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)
        cp      $00
        jr      nz, @search_random_empty_space

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
        call    f_game_over


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
        jr      c, @end_compute_index
        sub     16
        inc     c
        jr      @start_compute_index
@end_compute_index:
        ld      b, a
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
        xor     $1D                     ; best taps for lfsr on 8 bits.
@loop_lfsr_no_xor:
        ld      (hl), a
        ret


;===============================================================================
; Function to compute VDP address based on X and Y position.
; in    B: Position X
; in    C: Position Y
; out   HL = VDP VRAM ADDR
;            $3800 + ((Y+5) * 32 + (X + 8)) * 2 bytes
;===============================================================================
f_compute_vdp_memory_addr:
        ld      a, c
        add     a, $05

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
; Function called when the player dies.
;===============================================================================
f_game_over:
        ; Disable game logic.
        xor     a
        ld      (RAM_GAME_ROUTINE_DONE), a
        ld      (RAM_INGAME), a


        ; Draw game over.
        call    f_clean_draw_text
        ld      hl, str_lose
        ld      b, str_lose_size
        call    f_draw_text
        call    f_wait_b1_pressed

        ; Perform screen fadeOut.
        ld      hl, plt_snake
        ld      c, plt_snake_size
        call    f_fadeOutScreen
        call    f_disable_screen

        ; Check if we still have a life.
        ld      hl, RAM_LIFE
        ld      a, (hl)
        cp      0
        jp      z, @no_life_left
        dec     (hl)
        jp      f_setup_snake_game

@no_life_left:
        ; Save Score as the best if it's true.
        ld      a, (RAM_SCORE_THOUSANDS)
        ld      hl, RAM_BEST_SCORE_THOUSANDS
        ld      b, (hl)
        cp      b
        jr      z, @check_hundreds
        jr      c, @end_save_score
        jr      @save_score

@check_hundreds:
        ld      a, (RAM_SCORE_HUNDREDS)
        ld      hl, RAM_BEST_SCORE_HUNDREDS
        ld      b, (hl)
        cp      b
        jr      z, @check_tens
        jr      c, @end_save_score
        jr      @save_score

@check_tens:
        ld      a, (RAM_SCORE_TENS)
        ld      hl, RAM_BEST_SCORE_TENS
        ld      b, (hl)
        cp      b
        jr      z, @end_save_score
        jr      c, @end_save_score

@save_score:
        ld      a, (RAM_SCORE_THOUSANDS)
        ld      (RAM_BEST_SCORE_THOUSANDS), a
        ld      a, (RAM_SCORE_HUNDREDS)
        ld      (RAM_BEST_SCORE_HUNDREDS), a
        ld      a, (RAM_SCORE_TENS)
        ld      (RAM_BEST_SCORE_TENS), a
@end_save_score:

        ; reset in-game score.
        xor     a
        ld      (RAM_SCORE_THOUSANDS), a
        ld      (RAM_SCORE_HUNDREDS), a
        ld      (RAM_SCORE_TENS), a

        jp      f_setup_menu_title


;===============================================================================
; Function to draw text for player.
; in    hl:     Text addr.
; in    b:      Text size.
;===============================================================================
f_draw_text:
        call    f_disable_screen
        push    bc

        ; ====== Draw frame corner.
        ; first line.
        ld      a, $D4
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3A
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $75
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $00
        out     (SMS_PORTS_VDP_DATA), a

        ld      b, 10
 -:     ld      a, $76
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $00
        out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        ld      a, $75
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $02
        out     (SMS_PORTS_VDP_DATA), a

        ; last line.
        ld      a, $94
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $75
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $04
        out     (SMS_PORTS_VDP_DATA), a

        ld      b, 10
 -:     ld      a, $76
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $04
        out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        ld      a, $75
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $06
        out     (SMS_PORTS_VDP_DATA), a

        ; first column.
        ld      a, $14
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $77
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $00
        out     (SMS_PORTS_VDP_DATA), a

        ld      a, $54
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $77
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $00
        out     (SMS_PORTS_VDP_DATA), a

        ; last column.
        ld      a, $2A
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $77
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $02
        out     (SMS_PORTS_VDP_DATA), a

        ld      a, $6A
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $77
        out     (SMS_PORTS_VDP_DATA), a
        ld      a, $02
        out     (SMS_PORTS_VDP_DATA), a

        ; ====== Draw text.
        ld      a, $16
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        pop     bc
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        ; ====== Draw text press button.
        ld      a, $56
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      hl, str_press_button
        ld      b, str_press_button_size
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        call    f_enable_screen

        ret


;===============================================================================
; Function to clean text drew.
;===============================================================================
f_clean_draw_text:
        call    f_disable_screen

        ld      a, $D4
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3A
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        xor     a
-:      out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        ld      a, $14
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        xor     a
-:      out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        ld      a, $54
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        xor     a
-:      out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        ld      a, $94
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        xor     a
-:      out     (SMS_PORTS_VDP_DATA), a
        djnz    -

        call    f_enable_screen

        ret


;===============================================================================
; Function to increase the score.
; in    b:      POINT to add.
;===============================================================================
f_increase_score:
        ld      a, (RAM_SCORE_TENS)
        add     a, b
        cp      100
        jr      z, @increase_hundreds
        jr      @no_increase_hundreds

@increase_hundreds:
        xor     a
        ld      (RAM_SCORE_TENS), a
        ld      a, (RAM_SCORE_HUNDREDS)
        inc     a
        cp      10
        jr      z, @increase_thousands
        jr      @no_increase_thousands

@increase_thousands:
        xor     a
        ld      (RAM_SCORE_HUNDREDS), a
        ld      a, (RAM_SCORE_THOUSANDS)
        inc     a
        ld      (RAM_SCORE_THOUSANDS), a

        ; for each thousands, we add a life.
        ld      hl, RAM_LIFE
        ld      a, (hl)
        cp      MAX_LIFE        ; don't get more than 3 lifes.
        jr      c, @add_new_life
        jr      @end_increase_score

@add_new_life:
        inc     (hl)
        jr      @end_increase_score

@no_increase_hundreds:
        ld      (RAM_SCORE_TENS), a
        jr      @end_increase_score

@no_increase_thousands:
        ld      (RAM_SCORE_HUNDREDS), a
        jr      @end_increase_score

@end_increase_score:
        ret


;===============================================================================
; Function to draw score.
; in:   hl      VRAM Addr
; in:   de      Score address start
;===============================================================================
f_draw_score:
        ; Set instruction to write in VRAM
        ld      a, l
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, h
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ; Draw thousands.
        ld      h, d
        ld      l, e
        ld      a, (hl)
        call    f_hexToBCD
        push    af

        and     %11110000
        ld      b, 4
-:      srl     a
        djnz    -
        inc     a
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a

        pop     af
        and     %00001111
        inc     a
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a

        ; Draw hundreds.
        inc     hl
        ld      a, (hl)
        call    f_hexToBCD
        push    af

        pop     af
        and     %00001111
        inc     a
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a

        ; Draw tens.
        inc     hl
        ld      a, (hl)
        call    f_hexToBCD
        push    af

        and     %11110000
        ld      b, 4
-:      srl     a
        djnz    -
        inc     a
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a

        pop     af
        and     %00001111
        inc     a
        out     (SMS_PORTS_VDP_DATA), a
        xor     a
        out     (SMS_PORTS_VDP_DATA), a

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
; Function to load palette in CRAM.
; in    hl:     palette asset Addr
; in    b:      palette size
; in    c:      Bank selection
;===============================================================================
f_load_palette:
        xor     a
        or      c
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a
@loop_loading_colors:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     b
                jp      nz, @loop_loading_colors
        ret


;===============================================================================
; Function to load tileset in VRAM.
; in    hl:     asset addr
; in    bc:     asset size
; in    de:     VRAM Addr
;===============================================================================
f_load_asset:
        ld      a, e
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, d
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a
@loop_loading_asset:
                ld      a, (hl)
                out     (SMS_PORTS_VDP_DATA), a
                inc     hl
                dec     bc
                ld      a, b
                or      c
                jr      nz, @loop_loading_asset
        ret


;===============================================================================
; Function to tell the VDP to disable screen.
;===============================================================================
f_disable_screen:
        ; Change VDP register.
        ld      a, %10100000
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_REGISTER_1
        out     (SMS_PORTS_VDP_COMMAND), a

        di      ; Disable interrupt.

        ret


;===============================================================================
; Function to tell the VDP to enable screen.
;===============================================================================
f_enable_screen:
        ; Change VDP register.
        ld      a, %11100000
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, SMS_VDP_REGISTER_1
        out     (SMS_PORTS_VDP_COMMAND), a

        ei      ; Enable interrupt.

        ret


;===============================================================================
; Function to fadeout the screen.
; From  https://www.smspower.org/Development/ScreenFading
;
; in    hl:     palette asset Addr
; in    c:      palette size
;===============================================================================
f_fadeOutScreen:
        push    hl
        push    hl
        push    hl
        halt                            ; Wait for Vblank.

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette write identifier.

        ld      b, c                    ; Number of palette entries.
        pop     hl
 -:     ld      a, (hl)                 ; Load raw palette data.
        and     %00101010               ; Modify color values: 3 becomes 2, 1 becomes 0
        out     (SMS_PORTS_VDP_DATA), a ; Write modified data to CRAM.
        inc     hl
        djnz    -

        ld      b, 4                    ; Delay 6 frames.
 -:     halt
        djnz    -

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette write identifier.

        ld      b, c                    ; Number of palette entries.
        pop     hl
 -:     ld      a, (hl)                 ; Load raw palette data
        and     %00101010               ; Modify color values: 3 becomes 2, 1 becomes 0
        srl     a                       ; Modify color values: 2 becomes 1
        out     (SMS_PORTS_VDP_DATA), a ; Write modified data to CRAM.
        inc     hl
        djnz    -

        ld      b, 4                    ; Delay 4 frames.
 -:     halt
        djnz    -

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; Palette write identifier.

        ld      b, c                    ; Number of palette entries.
        xor     a                       ; we want to blacken the palette, so a is set to 0
 -:     out     (SMS_PORTS_VDP_DATA), a ; write zeros to CRAM, palette fade complete
        djnz    -

        ret


;===============================================================================
; Function to fadein the screen.
; From  https://www.smspower.org/Development/ScreenFading
;
; in    hl:     palette asset Addr
; in    c:      palette size
;===============================================================================
f_fadeInScreen:
        push    hl
        push    hl
        push    hl
        halt                    ; wait for Vblank

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; palette write identifier.

        ld      b, c                    ; Number of palette entries.
        pop     hl
 -:     ld      a, (hl)                 ; Load raw palette data.
        and     %00101010               ; Modify color values: 3 becomes 2, 1 becomes 0
        srl     a                       ; Modify color values: 2 becomes 1
        out     (SMS_PORTS_VDP_DATA), a ; Write modified data to CRAM.
        inc     hl
        djnz    -

        ld      b, 4                    ; Delay 4 frames.
 -:     halt
        djnz    -

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; palette write identifier.

        ld      b, c                    ; Number of palette entries.
        pop     hl
 -:     ld      a, (hl)                 ; Load raw palette data.
        and     %00101010               ; Modify color values: 3 becomes 2, 1 becomes 0
        out     (SMS_PORTS_VDP_DATA), a ; Write modified data to CRAM.
        inc     hl
        djnz    -

        ld      b, 4                    ; delay 4 frames
 -:     halt
        djnz     -

        xor     a
        out     (SMS_PORTS_VDP_COMMAND), a ; palette index (0).
        xor     SMS_VDP_WRITE_CRAM
        out     (SMS_PORTS_VDP_COMMAND), a ; palette write identifier.

        ld      b, c                    ; Number of palette entries.
        pop     hl
 -:     ld      a, (hl)                 ; Load raw palette data.
        out     (SMS_PORTS_VDP_DATA), a ; Write unfodified data to CRAM, palette load complete.
        inc     hl
        djnz    -

        ret


;===============================================================================
; Function to convert Hex to BCD representation
; From  https://www.smspower.org/Development/HexToBCD
;
; in    a:      hex number
; out   a:      BCD number
;===============================================================================
f_hexToBCD:
        ld      c, a    ; Original (hex) number
        ld      b, 8    ; How many bits
        xor     a       ; Output (BCD) number, starts at 0
-:      sla     c       ; shift c into carry
        adc     a, a
        daa             ; Decimal adjust a, so shift = BCD x2 plus carry
        djnz    -       ; Repeat for 8 bits
        ret


;===============================================================================
; Function to handle what's going on when player press Pause button.
;===============================================================================
f_pause_iHandler:
        ; Check if we are in game or in menu.
        ld      a, (RAM_INGAME)
        cp      TRUE
        jp      z, @ingame_pause
        ret

@ingame_pause:
        call    f_disable_screen

        ; Stop game logic.
        xor     a
        ld      (RAM_GAME_ROUTINE_DONE), a

        ; Set in pause.
        inc     a
        ld      (RAM_PAUSE), a

        ; Backup the VDP tiles before drawing on them.
        ; line 1
        ld      a, $D4
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3A
        and     SMS_VDP_READ_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_1
-:      in      a, (SMS_PORTS_VDP_DATA)
        ld      (hl), a
        inc     hl
        djnz    -

        ; line 2
        ld      a, $14
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        and     SMS_VDP_READ_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_2
-:      in      a, (SMS_PORTS_VDP_DATA)
        ld      (hl), a
        inc     hl
        djnz    -

        ; line 3
        ld      a, $54
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        and     SMS_VDP_READ_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_3
-:      in      a, (SMS_PORTS_VDP_DATA)
        ld      (hl), a
        inc     hl
        djnz    -

        ; line 4
        ld      a, $94
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        and     SMS_VDP_READ_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_4
-:      in      a, (SMS_PORTS_VDP_DATA)
        ld      (hl), a
        inc     hl
        djnz    -

        ; Draw pause text.
        call    f_clean_draw_text
        ld      hl, str_pause
        ld      b, str_pause_size
        call    f_draw_text

        ; Wait user input.
        call    f_wait_b1_pressed
        call    f_clean_draw_text

        ; Restaure VDP tiles.
        call    f_disable_screen

       ; line 1
        ld      a, $D4
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3A
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_1
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        ; line 2
        ld      a, $14
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_2
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        ; line 3
        ld      a, $54
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_3
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        ; line 4
        ld      a, $94
        out     (SMS_PORTS_VDP_COMMAND), a
        ld      a, $3B
        or      SMS_VDP_WRITE_RAM
        out     (SMS_PORTS_VDP_COMMAND), a

        ld      b, 24
        ld      hl, RAM_VDP_BAK_LIGNE_4
-:      ld      a, (hl)
        out     (SMS_PORTS_VDP_DATA), a
        inc     hl
        djnz    -

        ; Reset Frame counter.
        xor     a
        ld      (RAM_FRAME_COUNTER), a
        ld      (RAM_PAUSE), a

        call    f_enable_screen
        ret


;===============================================================================
; Function triggered when VDP sent interrupt signal.
;===============================================================================
f_vdp_iHandler:
        ; Saves registers on the stack.
        push    af
        push    bc
        push    de
        push    hl

        ; Read interrupt variables.
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

@vblank_handler:
        ; ====== Check if game routine is done.
        ld      a, (RAM_GAME_ROUTINE_DONE)
        cp      $01
        jp      nz, @f_vdp_iHandler_end
        xor     a
        ld      (RAM_GAME_ROUTINE_DONE), a

        ; ====== Flush old snake tail position.
        ld      hl, (RAM_SNAKE_TAIL_OLD_MEM_POS)
        ld      bc, $0000
        call    f_draw_tile

        ; ====== Draw snake head in VRAM.
        ; Check if an apple is digested here.
        ld      hl, RAM_SNAKE_HEAD_OLD_X_POS
        ld      b, (hl)
        ld      hl, RAM_SNAKE_HEAD_OLD_Y_POS
        ld      c, (hl)
        call    f_compute_array_index_from_position
        ld      de, RAM_SNAKE_ARRAY
        add     hl, de
        ld      a, (hl)

        ld      d, $00                  ; body tile index.
        bit     7, a                    ; if we eaten an apple, the 7th bit is set.
        jr      z, @no_apple_digested
        ld      d, $04                  ; body tile index + 4
@no_apple_digested:

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
                ld      bc, $4600
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_up
        @snake_moving_up_from_left:
                ld      bc, $4906
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_up
        @snake_moving_up_from_right:
                ld      bc, $4904
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_up

        @end_snake_moving_up:
                ld      bc, $4400
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
                ld      bc, $4604
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_down
        @snake_moving_down_from_left:
                ld      bc, $4902
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_down
        @snake_moving_down_from_right:
                ld      bc, $4900
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_down

        @end_snake_moving_down:
                ld      bc, $4404
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
                ld      bc, $4802
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_left
        @snake_moving_left_from_down:
                ld      bc, $4806
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_left
        @snake_moving_left_from_left:
                ld      bc, $4702
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_left

        @end_snake_moving_left:
                ld      bc, $4502
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
                ld      bc, $4800
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_right
        @snake_moving_right_from_down:
                ld      bc, $4804
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_right
        @snake_moving_right_from_right:
                ld      bc, $4700
                ; add body tile index.
                ld      a, b
                add     d
                ld      b, a
                call    f_draw_tile
                jr      @end_snake_moving_right

        @end_snake_moving_right:
                ld      bc, $4500
                jp      @draw_snake_head

@draw_snake_head:
        ld      hl, (RAM_SNAKE_HEAD_MEM_POS)
        call    f_draw_tile


        ; ====== Draw snake tail in VRAM.
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
        ld      bc, $4E00
        jr      @draw_snake_tail
@tail_going_down:
        ld      bc, $4E04
        jr      @draw_snake_tail
@tail_going_left:
        ld      bc, $4F00
        jr      @draw_snake_tail
@tail_going_right:
        ld      bc, $4F02
        jr      @draw_snake_tail

@draw_snake_tail:
        ld      hl, (RAM_SNAKE_TAIL_MEM_POS)
        call    f_draw_tile

        ; Draw apple.
        ld      hl, (RAM_APPLE_MEM_POS)
        ld      bc, $4300
        call    f_draw_tile

        ; Draw score.
        ld      de, RAM_SCORE_THOUSANDS
        ld      hl, $384E
        call    f_draw_score

        ; Draw life.
        ld      a, (RAM_LIFE)
        inc     a
        ld      b, a
        ld      c, $00
        ld      hl, $388E
        call    f_draw_tile

@f_vdp_iHandler_end:
        ; Update frame counter.
        ld      hl, RAM_FRAME_COUNTER
        inc     (hl)

        ; Set back registers from the stack.
        pop     hl
        pop     de
        pop     bc
        pop     af

        ret


;===============================================================================
; VDP Initialisation function.
;
; Use to set all VDP registers to default values.
; For register => page 16 to 19 from official guide.
;===============================================================================
f_VDPInitialisation:
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


.BANK 1 SLOT 1
.ORG $0000
;===============================================================================
; ASSETS DATA
;===============================================================================
plt_snake_title:
.INCBIN "assets/palettes/snake_title.plt.bin" fsize plt_snake_title_size

tileset_snake_title:
.INCBIN "assets/tiles/snake_title.tileset.bin" fsize tileset_snake_title_size

tilemap_snake_title:
.INCBIN "assets/tiles/snake_title.tilemap.bin" fsize tilemap_snake_title_size

plt_snake:
.INCBIN "assets/palettes/snake.plt.bin" fsize plt_snake_size

tileset_snake:
.INCBIN "assets/tiles/snake.tileset.bin" fsize tileset_snake_size

tilemap_snake:
.INCBIN "assets/tiles/snake.tilemap.bin" fsize tilemap_snake_size

str_ready:
.ASC "Ready ?"
.define str_ready_size 7

str_lose:
.ASC "You lose!"
.define str_lose_size 9

str_press_button:
.ASC "Press b1"
.define str_press_button_size 8

str_pause:
.ASC "Pause"
.define str_pause_size 5
