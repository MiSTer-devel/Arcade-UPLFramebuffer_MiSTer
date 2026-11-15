//  Copyright (C) 2026 Rodimus

module uplframebuffer_dispatcher
(
    input                reset,
    input                por_reset,
    input                clk_60m,

    input          [7:0] keycoin,
    input          [7:0] pad1,
    input          [7:0] pad2,
    input          [7:0] dsw1,
    input          [7:0] dsw2,

    output               video_hsync, video_vsync,
    output               video_hblank, video_vblank,
    output               ce_pix,
    output         [7:0] video_r, video_g, video_b,

    output signed [15:0] sound_l,
    output signed [15:0] sound_r,

    input         [24:0] ioctl_addr,
    input          [7:0] ioctl_data,
    input                ioctl_wr,
    input          [7:0] ioctl_index,
    input                ioctl_download,
    output               ioctl_wait,

    output         [7:0] set_id,

    input                crt_flip,
    input  signed  [3:0] h_adj,
    input  signed  [3:0] v_adj,
    input                pause,

    input                rd_auto,
    input          [1:0] rd_mode,
    input                rd_recal,
    input                ph_auto,
    input                ld_hold,
    output         [6:0] ph_req_val,
    output               ph_req_tgl,
    output               cal_hold,

    inout  [15:0] SDRAM_DQ,
    output [12:0] SDRAM_A,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output  [1:0] SDRAM_BA,
    output        SDRAM_nCS,
    output        SDRAM_nWE,
    output        SDRAM_nRAS,
    output        SDRAM_nCAS,
    output        SDRAM_CKE,
    output        SDRAM_CLK
);

//////////////////// Clock enables /////////////////////////////////////////////////////////////////////////////////////

reg [3:0] div10 = 4'd0;
reg [3:0] div12 = 4'd0;
reg [1:0] div4  = 2'd0;

always_ff @(posedge clk_60m) begin
    div10 <= (div10 == 4'd9)  ? 4'd0 : div10 + 4'd1;
    div12 <= (div12 == 4'd11) ? 4'd0 : div12 + 4'd1;
    if (div10 == 4'd9) div4 <= (div4 == 2'd3) ? 2'd0 : div4 + 2'd1;
end

wire cen_cpu = (div10 == 4'd0);
wire cen_pix = (div10 == 4'd0);
wire cen_snd = (div12 == 4'd0);
wire cen_ym  = (div10 == 4'd0) && (div4 == 2'd0);

wire       is_xx      = (set_id == 8'h1A);
wire       is_nova    = (set_id >= 8'h10) && (set_id <= 8'h19);
wire [1:0] nv_variant = (set_id <= 8'h12) ? 2'd0 : (set_id <= 8'h15) ? 2'd1 : (set_id == 8'h16) ? 2'd2 : 2'd3;
assign ce_pix = is_xx ? ((div10 == 4'd0) || (div10 == 4'd5)) : cen_pix;

//////////////////// Shared ROM blocks /////////////////////////////////////////////////////////////////////////////////

// upl_rom: SDRAM regions (chars, tiles 1-3, sprites, PCM) + BRAM CPU ROMs / gfx bank image. nv_prom: palette PROM.
wire [15:0] maincpu_addr;   wire [3:0] maincpu_bank;   wire [7:0] maincpu_data;
wire [15:0] nk_maincpu_addr, nv_maincpu_addr, xx_maincpu_addr;
wire [17:0] nv_gfx_addr, xx_gfx_addr;  wire [7:0] gfx_data;
wire [15:0] audiocpu_addr;  wire audiocpu_m1;          wire [7:0] audiocpu_data;
wire [15:0] nk_audiocpu_addr, nv_aux_addr, xx_aux_addr; wire nk_audiocpu_m1;
wire [14:0] char_addr;      wire char_req, char_ack;   wire [7:0] char_data;
wire [18:0] tile1_addr;     wire tile1_req, tile1_ack; wire [7:0] tile1_data;
wire [18:0] nk_tile1_addr, xx_tile1_addr;              wire nk_tile1_req, xx_tile1_req;
wire [18:0] tile2_addr;     wire tile2_req, tile2_ack; wire [7:0] tile2_data;
wire [18:0] tile3_addr;     wire tile3_req, tile3_ack; wire [7:0] tile3_data;
wire [17:0] spr_addr;       wire spr_req, spr_ack;     wire [7:0] spr_data;
wire [15:0] pcm_addr;       wire pcm_req, pcm_ack;     wire [7:0] pcm_data;
wire  [4:0] nv_prom_addr;   wire [7:0] nv_prom_data;

assign maincpu_addr  = is_xx ? xx_maincpu_addr : is_nova ? nv_maincpu_addr : nk_maincpu_addr;
assign audiocpu_addr = is_xx ? xx_aux_addr : is_nova ? nv_aux_addr : nk_audiocpu_addr;
assign audiocpu_m1   = (is_nova | is_xx) ? 1'b0 : nk_audiocpu_m1;
assign tile1_addr    = is_xx ? xx_tile1_addr : nk_tile1_addr;
assign tile1_req     = is_xx ? xx_tile1_req  : nk_tile1_req;

upl_rom rom
(
    .clk(clk_60m),
    .por_reset(por_reset),
    .rd_auto(rd_auto),
    .rd_mode(rd_mode),
    .recal(rd_recal),
    .ph_auto(ph_auto),
    .ld_hold(ld_hold),
    .ph_req_val(ph_req_val),
    .ph_req_tgl(ph_req_tgl),
    .cal_hold(cal_hold),

    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr),
    .ioctl_data(ioctl_data),
    .ioctl_wr(ioctl_wr),
    .ioctl_wait(ioctl_wait),

    .set_id(set_id),

    .maincpu_addr(maincpu_addr), .maincpu_bank(maincpu_bank), .maincpu_data(maincpu_data),
    .gfx_sel(is_nova | is_xx), .gfx_addr(is_xx ? xx_gfx_addr : nv_gfx_addr), .gfx_data(gfx_data),
    .audiocpu_addr(audiocpu_addr), .audiocpu_m1(audiocpu_m1), .audiocpu_data(audiocpu_data),

    .char_addr(char_addr),  .char_req(char_req),  .char_ack(char_ack),  .char_data(char_data),
    .spr_addr(spr_addr), .spr_req(spr_req), .spr_ack(spr_ack), .spr_data(spr_data),
    .tile1_addr(tile1_addr), .tile1_req(tile1_req), .tile1_ack(tile1_ack), .tile1_data(tile1_data),
    .tile2_addr(tile2_addr), .tile2_req(tile2_req), .tile2_ack(tile2_ack), .tile2_data(tile2_data),
    .tile3_addr(tile3_addr), .tile3_req(tile3_req), .tile3_ack(tile3_ack), .tile3_data(tile3_data),
    .pcm_addr(pcm_addr), .pcm_req(pcm_req), .pcm_ack(pcm_ack), .pcm_data(pcm_data),

    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
    .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK)
);

reg [7:0] nv_prom [0:31];
always_ff @(posedge clk_60m)
    if (ioctl_wr && (((ioctl_index == 8'd0)  && (ioctl_addr[24:5] == 20'h00800)) ||
                     ((ioctl_index == 8'd11) && (ioctl_addr[24:5] == 20'h00000))))
        nv_prom[ioctl_addr[4:0]] <= ioctl_data;
assign nv_prom_data = nv_prom[nv_prom_addr];

//////////////////// Shared CPU / sound chip pool //////////////////////////////////////////////////////////////////////

// z80r_0: ninjakd2 main, nova2001 CPU 1, xxmissio main
chip_pool_pkg::z80r_i_t nk_z80r_0_i, nv_z80r_0_i, xx_z80r_0_i, z80r_0_i;
chip_pool_pkg::z80_o_t  z80r_0_o;
assign z80r_0_i = is_xx ? xx_z80r_0_i : is_nova ? nv_z80r_0_i : nk_z80r_0_i;

wire [15:0] z80r_0_a;
wire  [7:0] z80r_0_do;
wire        z80r_0_m1_n, z80r_0_mreq_n, z80r_0_iorq_n, z80r_0_rd_n, z80r_0_wr_n, z80r_0_rfsh_n;

t80sv_T80s z80r_0
(
    .RESET_n(z80r_0_i.reset_n), .CLK(clk_60m), .CEN(z80r_0_i.ce), .WAIT_n(1'b1),
    .INT_n(z80r_0_i.int_n), .NMI_n(z80r_0_i.nmi_n), .BUSRQ_n(1'b1), .OUT0(1'b0),
    .M1_n(z80r_0_m1_n), .MREQ_n(z80r_0_mreq_n), .IORQ_n(z80r_0_iorq_n), .RD_n(z80r_0_rd_n),
    .WR_n(z80r_0_wr_n), .RFSH_n(z80r_0_rfsh_n), .HALT_n(), .BUSAK_n(),
    .A(z80r_0_a), .DI(z80r_0_i.di), .DO(z80r_0_do)
);

assign z80r_0_o.a = z80r_0_a;           assign z80r_0_o.dout = z80r_0_do;
assign z80r_0_o.m1_n = z80r_0_m1_n;     assign z80r_0_o.mreq_n = z80r_0_mreq_n; assign z80r_0_o.iorq_n = z80r_0_iorq_n;
assign z80r_0_o.rd_n = z80r_0_rd_n;     assign z80r_0_o.wr_n = z80r_0_wr_n;     assign z80r_0_o.rfsh_n = z80r_0_rfsh_n;

// z80r_1: ninjakd2 sound, nova2001 CPU 2 (Ninjakun / Raiders5), xxmissio sub
chip_pool_pkg::z80r_i_t nk_z80r_1_i, nv_z80r_1_i, xx_z80r_1_i, z80r_1_i;
chip_pool_pkg::z80_o_t  z80r_1_o;
assign z80r_1_i = is_xx ? xx_z80r_1_i : is_nova ? nv_z80r_1_i : nk_z80r_1_i;

wire [15:0] z80r_1_a;
wire  [7:0] z80r_1_do;
wire        z80r_1_m1_n, z80r_1_mreq_n, z80r_1_iorq_n, z80r_1_rd_n, z80r_1_wr_n, z80r_1_rfsh_n;

t80sv_T80s z80r_1
(
    .RESET_n(z80r_1_i.reset_n), .CLK(clk_60m), .CEN(z80r_1_i.ce), .WAIT_n(1'b1),
    .INT_n(z80r_1_i.int_n), .NMI_n(z80r_1_i.nmi_n), .BUSRQ_n(1'b1), .OUT0(1'b0),
    .M1_n(z80r_1_m1_n), .MREQ_n(z80r_1_mreq_n), .IORQ_n(z80r_1_iorq_n), .RD_n(z80r_1_rd_n),
    .WR_n(z80r_1_wr_n), .RFSH_n(z80r_1_rfsh_n), .HALT_n(), .BUSAK_n(),
    .A(z80r_1_a), .DI(z80r_1_i.di), .DO(z80r_1_do)
);

assign z80r_1_o.a = z80r_1_a;           assign z80r_1_o.dout = z80r_1_do;
assign z80r_1_o.m1_n = z80r_1_m1_n;     assign z80r_1_o.mreq_n = z80r_1_mreq_n; assign z80r_1_o.iorq_n = z80r_1_iorq_n;
assign z80r_1_o.rd_n = z80r_1_rd_n;     assign z80r_1_o.wr_n = z80r_1_wr_n;     assign z80r_1_o.rfsh_n = z80r_1_rfsh_n;

// ym2203[0] / ym2203[1]: ninjakd2 sound board, nova2001 AY pair (SSG only), xxmissio
chip_pool_pkg::ym2203_i_t [1:0] nk_ym2203_i, nv_ym2203_i, xx_ym2203_i, ym2203_i;
chip_pool_pkg::ym2203_o_t [1:0] ym2203_o;
assign ym2203_i = is_xx ? xx_ym2203_i : is_nova ? nv_ym2203_i : nk_ym2203_i;

genvar yi;
generate
    for (yi = 0; yi < 2; yi = yi + 1) begin : ym
        wire signed [15:0] snd;
        wire         [9:0] psg_snd;
        wire         [7:0] dout, ioa_out, iob_out;
        wire               irq_n, ioa_oe, iob_oe;

        jt03 ym2203
        (
            .rst    (ym2203_i[yi].rst),
            .clk    (clk_60m),
            .cen    (ym2203_i[yi].ce),
            .din    (ym2203_i[yi].din),
            .addr   (ym2203_i[yi].addr),
            .cs_n   (ym2203_i[yi].cs_n),
            .wr_n   (ym2203_i[yi].wr_n),
            .dout   (dout),
            .irq_n  (irq_n),
            .IOA_in (ym2203_i[yi].ioa_in),
            .IOB_in (ym2203_i[yi].iob_in),
            .IOA_out(ioa_out), .IOB_out(iob_out), .IOA_oe(ioa_oe), .IOB_oe(iob_oe),
            .psg_A  (), .psg_B  (), .psg_C  (),
            .fm_snd (), .psg_snd(psg_snd),
            .snd    (snd),
            .snd_sample(),
            .debug_view()
        );

        assign ym2203_o[yi].dout    = dout;
        assign ym2203_o[yi].irq_n   = irq_n;
        assign ym2203_o[yi].ioa_out = ioa_out;
        assign ym2203_o[yi].iob_out = iob_out;
        assign ym2203_o[yi].ioa_oe  = ioa_oe;
        assign ym2203_o[yi].iob_oe  = iob_oe;
        assign ym2203_o[yi].psg_snd = psg_snd;
        assign ym2203_o[yi].snd     = snd;
    end
endgenerate

//////////////////// Shared RAM pool ///////////////////////////////////////////////////////////////////////////////////

//   block size    ninjakd2                    nova2001                                    xxmissio
//   0    2K x 8   fg VRAM                     fg VRAM                                     fg VRAM
//   1    8K x 8   bg VRAM layer 0             bg VRAM                                     bg VRAM
//   2    8K x 8   bg VRAM layer 1             sprite RAM                                  sprite RAM
//   3    8K x 8   bg VRAM layer 2             shared CPU RAM 0x000, palette RAM 0x800     palette RAM
//   4    8K x 8   work RAM incl. sprite list  work RAM                                    work RAM x2
//   5-8 16K x 8   sprite framebuffer lanes    sprite framebuffer lanes                    sprite line buffer lanes
//   9    2K x 8   sound CPU work RAM          -                                           -
//   10-11 1K x 8  palette RAM low / high      -                                           -
localparam int RAM_BLOCKS = 12;

function automatic int ram_aw(input int n);
    case (n)
        0, 9:        ram_aw = 11;
        1, 2, 3, 4:  ram_aw = 13;
        10, 11:      ram_aw = 10;
        default:     ram_aw = 14;
    endcase
endfunction

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] nk_pr_i, nv_pr_i, xx_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;
assign pool_i = is_xx ? xx_pr_i : is_nova ? nv_pr_i : nk_pr_i;

genvar ri;
generate
    for (ri = 0; ri < RAM_BLOCKS; ri = ri + 1) begin : rpool
        localparam int AW = ram_aw(ri);
        wire [7:0] qa, qb;

        dpram_dc #(.widthad_a(AW), .width_a(8)) ram
        (
            .clock_a(clk_60m), .address_a(pool_i[ri].a_addr[AW-1:0]), .data_a(pool_i[ri].a_d),
            .wren_a(pool_i[ri].a_we), .q_a(qa),
            .clock_b(clk_60m), .address_b(pool_i[ri].b_addr[AW-1:0]), .data_b(pool_i[ri].b_d),
            .wren_b(pool_i[ri].b_we), .q_b(qb)
        );

        assign pool_o[ri].a_q = qa;
        assign pool_o[ri].b_q = qb;
    end
endgenerate

//////////////////// Boards ////////////////////////////////////////////////////////////////////////////////////////////

wire signed [15:0] nk_sound, nv_sound, xx_sound;
wire        nk_hsync, nk_vsync, nk_hblank, nk_vblank, nv_hsync, nv_vsync, nv_hblank, nv_vblank;
wire        xx_hsync, xx_vsync, xx_hblank, xx_vblank;
wire  [7:0] nk_r, nk_g, nk_b, nv_r, nv_g, nv_b, xx_r, xx_g, xx_b;

ninjakd2_board #(.RAM_BLOCKS(RAM_BLOCKS)) ninjakd2_b
(
    .clk(clk_60m),
    .cen_cpu(cen_cpu), .cen_pix(cen_pix), .cen_snd(cen_snd), .cen_ym(cen_ym),
    .reset(reset | is_nova | is_xx),
    .pause(pause),

    .set_id(set_id),

    .keycoin(keycoin), .pad1(pad1), .pad2(pad2), .dsw1(dsw1), .dsw2(dsw2),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),

    .maincpu_addr(nk_maincpu_addr), .maincpu_bank(maincpu_bank), .maincpu_data(maincpu_data),
    .audiocpu_addr(nk_audiocpu_addr), .audiocpu_m1(nk_audiocpu_m1), .audiocpu_data(audiocpu_data),
    .char_addr(char_addr),  .char_req(char_req),  .char_ack(char_ack),  .char_data(char_data),
    .tile1_addr(nk_tile1_addr), .tile1_req(nk_tile1_req), .tile1_ack(tile1_ack), .tile1_data(tile1_data),
    .tile2_addr(tile2_addr), .tile2_req(tile2_req), .tile2_ack(tile2_ack), .tile2_data(tile2_data),
    .tile3_addr(tile3_addr), .tile3_req(tile3_req), .tile3_ack(tile3_ack), .tile3_data(tile3_data),
    .spr_addr(spr_addr), .spr_req(spr_req), .spr_ack(spr_ack), .spr_data(spr_data),
    .pcm_addr(pcm_addr), .pcm_req(pcm_req), .pcm_ack(pcm_ack), .pcm_data(pcm_data),

    .HSync(nk_hsync), .VSync(nk_vsync),
    .HBlank(nk_hblank), .VBlank(nk_vblank),
    .R(nk_r), .G(nk_g), .B(nk_b),
    .sound(nk_sound),

    .z80r_0_i(nk_z80r_0_i), .z80r_0_o(z80r_0_o),
    .z80r_1_i(nk_z80r_1_i), .z80r_1_o(z80r_1_o),
    .ym2203_i(nk_ym2203_i), .ym2203_o(ym2203_o),
    .pr_i(nk_pr_i), .pr_o(pool_o)
);

nova2001_board #(.RAM_BLOCKS(RAM_BLOCKS)) nova2001_b
(
    .clk(clk_60m),
    .pix_ph(div10),
    .reset(reset | ~is_nova),
    .pause(pause),
    .variant(nv_variant),

    .keycoin(keycoin), .pad1(pad1), .pad2(pad2), .dsw1(dsw1), .dsw2(dsw2),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),

    .maincpu_addr(nv_maincpu_addr), .maincpu_data(maincpu_data),
    .aux_addr(nv_aux_addr), .aux_data(audiocpu_data),
    .gfx_addr(nv_gfx_addr), .gfx_data(gfx_data),
    .prom_addr(nv_prom_addr), .prom_data(nv_prom_data),

    .HSync(nv_hsync), .VSync(nv_vsync),
    .HBlank(nv_hblank), .VBlank(nv_vblank),
    .R(nv_r), .G(nv_g), .B(nv_b),
    .sound(nv_sound),

    .z80_i(nv_z80r_0_i), .z80_o(z80r_0_o),
    .z80b_i(nv_z80r_1_i), .z80b_o(z80r_1_o),
    .ym_i(nv_ym2203_i), .ym_o(ym2203_o),
    .pr_i(nv_pr_i), .pr_o(pool_o)
);

xxmissio_board #(.RAM_BLOCKS(RAM_BLOCKS)) xxmissio_b
(
    .clk(clk_60m),
    .pix_ph(div10),
    .cen_ym(cen_ym),
    .reset(reset | ~is_xx),
    .pause(pause),

    .keycoin(keycoin), .pad1(pad1), .pad2(pad2), .dsw1(dsw1), .dsw2(dsw2),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),

    .maincpu_addr(xx_maincpu_addr), .maincpu_data(maincpu_data),
    .aux_addr(xx_aux_addr), .aux_data(audiocpu_data),
    .gfx_addr(xx_gfx_addr), .gfx_data(gfx_data),
    .tile_addr(xx_tile1_addr), .tile_req(xx_tile1_req), .tile_ack(tile1_ack), .tile_data(tile1_data),

    .HSync(xx_hsync), .VSync(xx_vsync),
    .HBlank(xx_hblank), .VBlank(xx_vblank),
    .R(xx_r), .G(xx_g), .B(xx_b),
    .sound(xx_sound),

    .z80_i(xx_z80r_0_i), .z80_o(z80r_0_o),
    .z80b_i(xx_z80r_1_i), .z80b_o(z80r_1_o),
    .ym_i(xx_ym2203_i), .ym_o(ym2203_o),
    .pr_i(xx_pr_i), .pr_o(pool_o)
);

assign video_hsync  = is_xx ? xx_hsync  : is_nova ? nv_hsync  : nk_hsync;
assign video_vsync  = is_xx ? xx_vsync  : is_nova ? nv_vsync  : nk_vsync;
assign video_hblank = is_xx ? xx_hblank : is_nova ? nv_hblank : nk_hblank;
assign video_vblank = is_xx ? xx_vblank : is_nova ? nv_vblank : nk_vblank;
assign video_r      = is_xx ? xx_r      : is_nova ? nv_r      : nk_r;
assign video_g      = is_xx ? xx_g      : is_nova ? nv_g      : nk_g;
assign video_b      = is_xx ? xx_b      : is_nova ? nv_b      : nk_b;
assign sound_l      = is_xx ? xx_sound  : is_nova ? nv_sound  : nk_sound;
assign sound_r      = is_xx ? xx_sound  : is_nova ? nv_sound  : nk_sound;

endmodule
