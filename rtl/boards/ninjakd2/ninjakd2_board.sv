//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module ninjakd2_board #(parameter RAM_BLOCKS = 12)
(
    input                clk,
    input                cen_cpu,
    input                cen_pix,
    input                cen_snd,
    input                cen_ym,
    input                reset,
    input                pause,

    input          [7:0] set_id,

    input          [7:0] keycoin,
    input          [7:0] pad1,
    input          [7:0] pad2,
    input          [7:0] dsw1,
    input          [7:0] dsw2,

    input                crt_flip,
    input  signed  [3:0] h_adj,
    input  signed  [3:0] v_adj,

    output        [15:0] maincpu_addr,  output  [3:0] maincpu_bank, input  [7:0] maincpu_data,
    output        [15:0] audiocpu_addr, output        audiocpu_m1,  input  [7:0] audiocpu_data,
    output        [14:0] char_addr,     output char_req,  input char_ack,  input [7:0] char_data,
    output        [18:0] tile1_addr,    output tile1_req, input tile1_ack, input [7:0] tile1_data,
    output        [18:0] tile2_addr,    output tile2_req, input tile2_ack, input [7:0] tile2_data,
    output        [18:0] tile3_addr,    output tile3_req, input tile3_ack, input [7:0] tile3_data,
    output        [17:0] spr_addr,      output spr_req,   input spr_ack,   input [7:0] spr_data,
    output        [15:0] pcm_addr,      output pcm_req,   input pcm_ack,   input [7:0] pcm_data,

    output               HSync, VSync,
    output               HBlank, VBlank,
    output         [7:0] R, G, B,
    output signed [15:0] sound,

    output chip_pool_pkg::z80r_i_t         z80r_0_i,
    input  chip_pool_pkg::z80_o_t          z80r_0_o,
    output chip_pool_pkg::z80r_i_t         z80r_1_i,
    input  chip_pool_pkg::z80_o_t          z80r_1_o,
    output chip_pool_pkg::ym2203_i_t [1:0] ym2203_i,
    input  chip_pool_pkg::ym2203_o_t [1:0] ym2203_o,
    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pr_o
);

ram_pool_pkg::pram_i_t       fg_i,  snd_ram_i;
ram_pool_pkg::pram_i_t [3:0] r8_i,  fb_i;
ram_pool_pkg::pram_i_t [1:0] pal_i;
assign pr_i[0]     = fg_i;
assign pr_i[4:1]   = r8_i;
assign pr_i[8:5]   = fb_i;
assign pr_i[9]     = snd_ram_i;
assign pr_i[11:10] = pal_i;

wire [15:0] fb_raddr;       wire [7:0] fb_rdata;       wire spr_draw_window;
wire  [7:0] pcm_cmd;        wire pcm_cmd_wr;

wire [7:0] sound_latch;
wire       sound_latch_wr;
wire       snd_reset;
wire        flip_screen, sprite_overdraw;
wire  [2:0] bg_layer_en;
wire [15:0] bg0_scrollx, bg0_scrolly, bg1_scrollx, bg1_scrolly, bg2_scrollx, bg2_scrolly;

wire [10:0] fg_vram_addr;  wire [7:0] fg_vram_data;
wire [12:0] bg0_vram_addr; wire [7:0] bg0_vram_data;
wire [12:0] bg1_vram_addr; wire [7:0] bg1_vram_data;
wire [12:0] bg2_vram_addr; wire [7:0] bg2_vram_data;
wire [12:0] work_addr;     wire [7:0] work_data;
wire  [9:0] pal_index;     wire [15:0] pal_rgb;

UPLFramebuffer_MAIN main_board
(
    .clk(clk),
    .cen_cpu(cen_cpu),
    .reset(reset),
    .pause(pause),

    .set_id(set_id),

    .keycoin(keycoin), .pad1(pad1), .pad2(pad2), .dsw1(dsw1), .dsw2(dsw2),

    .maincpu_addr(maincpu_addr), .maincpu_bank(maincpu_bank), .maincpu_data(maincpu_data),

    .sound_latch(sound_latch), .sound_latch_wr(sound_latch_wr), .snd_reset(snd_reset),

    .crt_flip(crt_flip),
    .flip_screen(flip_screen),
    .sprite_overdraw(sprite_overdraw),
    .bg0_scrollx(bg0_scrollx), .bg0_scrolly(bg0_scrolly),
    .bg1_scrollx(bg1_scrollx), .bg1_scrolly(bg1_scrolly),
    .bg2_scrollx(bg2_scrollx), .bg2_scrolly(bg2_scrolly),
    .bg_layer_en(bg_layer_en),

    .fg_vram_addr(fg_vram_addr), .fg_vram_data(fg_vram_data),
    .bg0_vram_addr(bg0_vram_addr), .bg0_vram_data(bg0_vram_data),
    .bg1_vram_addr(bg1_vram_addr), .bg1_vram_data(bg1_vram_data),
    .bg2_vram_addr(bg2_vram_addr), .bg2_vram_data(bg2_vram_data),
    .work_addr(work_addr),       .work_data(work_data),
    .pal_index(pal_index),       .pal_rgb(pal_rgb),

    .vblank(VBlank),

    .z80_i(z80r_0_i), .z80_o(z80r_0_o),
    .fg_i(fg_i), .fg_o(pr_o[0]),
    .r8_i(r8_i), .r8_o(pr_o[4:1]),
    .pal_i(pal_i), .pal_o(pr_o[11:10])
);

wire bg_mnight  = (set_id >= 8'h06) && (set_id <= 8'h08);
wire is_robokid = (set_id >= 8'h09) && (set_id <= 8'h0C);
wire is_omegaf  = (set_id >= 8'h0D) && (set_id <= 8'h0F);

wire gfx_robokid = is_robokid | is_omegaf;

UPLFramebuffer_VIDEO video
(
    .clk(clk),
    .cen_pix(cen_pix),
    .reset(reset),

    .flip_screen(flip_screen),
    .h_adj(h_adj), .v_adj(v_adj),
    .bg_mnight(bg_mnight),
    .gfx_robokid(gfx_robokid),
    .is_omegaf(is_omegaf),

    .fg_vram_addr(fg_vram_addr), .fg_vram_data(fg_vram_data),
    .bg0_vram_addr(bg0_vram_addr), .bg0_vram_data(bg0_vram_data),
    .bg1_vram_addr(bg1_vram_addr), .bg1_vram_data(bg1_vram_data),
    .bg2_vram_addr(bg2_vram_addr), .bg2_vram_data(bg2_vram_data),
    .bg0_scrollx(bg0_scrollx), .bg0_scrolly(bg0_scrolly),
    .bg1_scrollx(bg1_scrollx), .bg1_scrolly(bg1_scrolly),
    .bg2_scrollx(bg2_scrollx), .bg2_scrolly(bg2_scrolly),
    .bg_layer_en(bg_layer_en),
    .char_addr(char_addr), .char_req(char_req), .char_ack(char_ack), .char_data(char_data),
    .tile1_addr(tile1_addr), .tile1_req(tile1_req), .tile1_ack(tile1_ack), .tile1_data(tile1_data),
    .tile2_addr(tile2_addr), .tile2_req(tile2_req), .tile2_ack(tile2_ack), .tile2_data(tile2_data),
    .tile3_addr(tile3_addr), .tile3_req(tile3_req), .tile3_ack(tile3_ack), .tile3_data(tile3_data),
    .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .spr_draw_window(spr_draw_window),
    .pal_index(pal_index), .pal_rgb(pal_rgb),

    .HSync(HSync), .VSync(VSync),
    .HBlank(HBlank), .VBlank(VBlank),
    .R(R), .G(G), .B(B)
);

UPLFramebuffer_SPRITE sprites
(
    .clk(clk),
    .reset(reset),

    .flip_screen(flip_screen),
    .gfx_robokid(gfx_robokid),
    .is_omegaf(is_omegaf),
    .overdraw(sprite_overdraw),
    .draw_window(spr_draw_window),

    .spr_ram_addr(work_addr), .spr_ram_data(work_data),
    .spr_addr(spr_addr), .spr_req(spr_req), .spr_ack(spr_ack), .spr_data(spr_data),

    .fb_raddr(fb_raddr), .fb_rdata(fb_rdata),
    .busy(),

    .fb_i(fb_i), .fb_o(pr_o[8:5])
);

wire signed [15:0] snd_mono;

UPLFramebuffer_SND snd_board
(
    .clk(clk),
    .cen_cpu(cen_snd),
    .cen_ym(cen_ym),
    .reset(reset | snd_reset),
    .pause(pause),

    .sound_latch(sound_latch),
    .sound_latch_wr(sound_latch_wr),

    .rom_addr(audiocpu_addr),
    .rom_data(audiocpu_data),
    .rom_m1(audiocpu_m1),
    .pcm_cmd(pcm_cmd),
    .pcm_cmd_wr(pcm_cmd_wr),

    .sound_out(snd_mono),

    .z80_i(z80r_1_i), .z80_o(z80r_1_o),
    .ym_i(ym2203_i), .ym_o(ym2203_o),
    .ram_i(snd_ram_i), .ram_o(pr_o[9])
);

wire signed [15:0] pcm_snd;

UPLFramebuffer_PCM pcm_player
(
    .clk(clk),
    .reset(reset),
    .pause(pause),
    .cmd(pcm_cmd),
    .cmd_wr(pcm_cmd_wr),
    .rom_addr(pcm_addr),
    .rom_req(pcm_req),
    .rom_ack(pcm_ack),
    .rom_data(pcm_data),
    .sample_out(pcm_snd)
);

wire signed [16:0] snd_mix = {snd_mono[15], snd_mono} + {pcm_snd[15], pcm_snd};
wire signed [15:0] snd_sat = (snd_mix >  17'sd32767) ?  16'sd32767 :
                             (snd_mix < -17'sd32768) ? -16'sd32768 : snd_mix[15:0];

assign sound = snd_sat;

endmodule
