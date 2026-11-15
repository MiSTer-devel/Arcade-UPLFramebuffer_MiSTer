//============================================================================
//
//  board_template.sv
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports.
//  Copy this file to start a board (rtl/boards/<board>/<board>_board.sv), then replace the board's tie-off in
//  rtl/uplframebuffer_dispatcher.sv with its instance.
//
//============================================================================

module board_template #(parameter RAM_BLOCKS = 12)
(
    input                clk,            // 60 MHz
    input          [3:0] pix_ph,         // dispatcher mod-10 phase, 0 = 6 MHz enable
    input                cen_ym,         // 1.5 MHz
    input                reset,
    input                pause,

    input          [7:0] keycoin,
    input          [7:0] pad1,
    input          [7:0] pad2,
    input          [7:0] dsw1,
    input          [7:0] dsw2,

    input                crt_flip,
    input  signed  [3:0] h_adj,
    input  signed  [3:0] v_adj,

    // ---- Shared ROM blocks (upl_rom BRAM ports, SDRAM clients, palette PROM)
    output        [15:0] maincpu_addr,
    input          [7:0] maincpu_data,
    output        [15:0] aux_addr,
    input          [7:0] aux_data,
    output        [17:0] gfx_addr,
    input          [7:0] gfx_data,
    output        [18:0] tile_addr,
    output               tile_req,
    input                tile_ack,
    input          [7:0] tile_data,
    output         [4:0] prom_addr,
    input          [7:0] prom_data,

    // ---- video / audio
    output               HSync, VSync,
    output               HBlank, VBlank,
    output         [7:0] R, G, B,
    output signed [15:0] sound,

    // ---- Shared CPU / sound chip pool
    output chip_pool_pkg::z80r_i_t         z80r_0_i,
    input  chip_pool_pkg::z80_o_t          z80r_0_o,
    output chip_pool_pkg::z80r_i_t         z80r_1_i,
    input  chip_pool_pkg::z80_o_t          z80r_1_o,
    output chip_pool_pkg::ym2203_i_t [1:0] ym2203_i,
    input  chip_pool_pkg::ym2203_o_t [1:0] ym2203_o,

    // ---- Shared RAM pool
    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pr_o
);

endmodule
