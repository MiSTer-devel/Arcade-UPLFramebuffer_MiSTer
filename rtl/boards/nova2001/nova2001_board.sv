//  Based on MAME nova2001.cpp (Howie Cohen, Frank Palazzolo, Alex Pasadyn, David Haywood, Phil Stroffolino, Uki, Stephane Humbert, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module nova2001_board #(parameter RAM_BLOCKS = 12)
(
    input                clk,
    input          [3:0] pix_ph,         // top's mod-10 phase; 0 = 6 MHz pixel enable
    input                reset,
    input                pause,
    input          [1:0] variant,

    input          [7:0] keycoin,
    input          [7:0] pad1,
    input          [7:0] pad2,
    input          [7:0] dsw1,
    input          [7:0] dsw2,

    input                crt_flip,
    input  signed  [3:0] h_adj,
    input  signed  [3:0] v_adj,

    output        [15:0] maincpu_addr,
    input          [7:0] maincpu_data,
    output        [15:0] aux_addr,
    input          [7:0] aux_data,
    output        [17:0] gfx_addr,
    input          [7:0] gfx_data,

    output         [4:0] prom_addr,
    input          [7:0] prom_data,

    output reg           HSync, VSync,
    output reg           HBlank, VBlank,
    output reg     [7:0] R, G, B,
    output signed [15:0] sound,

    output chip_pool_pkg::z80r_i_t         z80_i,
    input  chip_pool_pkg::z80_o_t          z80_o,
    output chip_pool_pkg::z80r_i_t         z80b_i,
    input  chip_pool_pkg::z80_o_t          z80b_o,
    output chip_pool_pkg::ym2203_i_t [1:0] ym_i,      // 0 = ay1, 1 = ay2
    input  chip_pool_pkg::ym2203_o_t [1:0] ym_o,
    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pr_o
);

ram_pool_pkg::pram_i_t fg_i, bg_i, spr_i, sh_i, work_i;
ram_pool_pkg::pram_o_t fg_o, bg_o, spr_o, sh_o, work_o;
assign pr_i[0] = fg_i;   assign fg_o   = pr_o[0];
assign pr_i[1] = bg_i;   assign bg_o   = pr_o[1];
assign pr_i[2] = spr_i;  assign spr_o  = pr_o[2];
assign pr_i[3] = sh_i;   assign sh_o   = pr_o[3];
assign pr_i[4] = work_i; assign work_o = pr_o[4];
assign pr_i[RAM_BLOCKS-1:9] = '0;

wire v_nova = (variant == 2'd0);
wire pkw    = (variant == 2'd1);
wire v_nk   = (variant == 2'd2);
wire v_r5   = (variant == 2'd3);
wire dual   = v_nk | v_r5;
wire pk_spr = pkw | v_r5;

wire cen_pix = (pix_ph == 4'd0);

reg h0 = 1'b0;
always_ff @(posedge clk) if (cen_pix) h0 <= ~h0;
wire cen_cpu  = cen_pix &  h0;
wire cen_cpu2 = cen_pix & ~h0 & dual;

wire [4:0] ay_div = v_nova ? 5'd14 : v_nk ? 5'd9 : 5'd19;
reg  [4:0] div_ay = 5'd0;
always_ff @(posedge clk) div_ay <= (div_ay >= ay_div) ? 5'd0 : div_ay + 5'd1;
wire cen_ay = (div_ay == 5'd0);

localparam [8:0] V_LOAD = 9'd248;

reg [8:0] hc = 9'd0;
reg [8:0] v9 = 9'd256;

always_ff @(posedge clk) begin
    if (cen_pix) begin
        hc <= (hc == 9'd383) ? 9'd0 : hc + 9'd1;
        if (hc == 9'd319) v9 <= (v9 == 9'd511) ? V_LOAD : v9 + 9'd1;
    end
end

wire [7:0] v8      = v9[7:0];
wire       vsync_l = ~v9[8];
wire       vblank  = ~v9[8] | (v8 < 8'd32) | (v8 >= 8'd224);
wire       hblank  = hc[8];
wire       hsync   = (hc >= 9'd320) && (hc < 9'd352);

wire [8:0] hs_on   = 9'd320 - {{4{h_adj[3]}}, h_adj, 1'b0};
wire       hsync_o = (hc >= hs_on) && (hc < hs_on + 9'd32);
wire [9:0] vs_ln   = {1'b0, v9} - {1'b0, V_LOAD} + {{6{v_adj[3]}}, v_adj} + 10'd264;
wire       vsync_o = ((vs_ln >= 10'd264) ? (vs_ln - 10'd264) : vs_ln) < 10'd8;
wire       disp    = ~vblank & ~hblank;

wire who2 = dual & ~h0;

wire [15:0] A        = who2 ? z80b_o.a    : z80_o.a;
wire  [7:0] cpu_dout = who2 ? z80b_o.dout : z80_o.dout;
wire        mreq     = who2 ? (~z80b_o.mreq_n & z80b_o.rfsh_n) : (~z80_o.mreq_n & z80_o.rfsh_n);
wire        rd       = who2 ? ~z80b_o.rd_n   : ~z80_o.rd_n;
wire        wr       = who2 ? ~z80b_o.wr_n   : ~z80_o.wr_n;
wire        iorq     = who2 ? ~z80b_o.iorq_n : ~z80_o.iorq_n;
wire        int_ack  = who2 ? (~z80b_o.m1_n & ~z80b_o.iorq_n) : (~z80_o.m1_n & ~z80_o.iorq_n);

wire cen_bus = dual ? cen_pix : cen_cpu;
wire wr_cen  = cen_bus & wr;

wire r5c1 = v_r5 & ~who2;
wire r5c2 = v_r5 &  who2;

wire cs_rom   = mreq & (v_nk ? (~A[15] & (~who2 | (A[14:13] != 2'b00))) : r5c2 ? (A[15:14] == 2'b00) : ~A[15]);
wire cs_aux   = mreq & ((pkw & (A[15:13] == 3'b111)) | (v_nk & who2 & (A[15:13] == 3'b000)));
wire cs_stnpd = mreq & v_nova & (A[15:13] == 3'b100);
wire cs_fg    = mreq & ((v_nova & (A[15:11] == 5'b10100)) | (v_nk & (A[15:11] == 5'b11000)) | (r5c1 & (A[15:11] == 5'b10001)));
wire cs_bg    = mreq & ((v_nova & (A[15:11] == 5'b10101)) | (pkw  & (A[15:11] == 5'b10001)) |
                        (v_nk   & (A[15:11] == 5'b11001)) | (r5c1 & (A[15:11] == 5'b10010)));
wire cs_spr   = mreq & ((v_nova & (A[15:11] == 5'b10110)) | (pkw  & (A[15:11] == 5'b10000)) |
                        (v_nk   & (A[15:11] == 5'b11010)) | (r5c1 & (A[15:11] == 5'b10000)));
wire cs_flip  = mreq & v_nova & (A[15:11] == 5'b10111);
wire cs_io    = mreq & v_nova & (A[15:13] == 3'b110);
wire cs_pay   = mreq & ((pkw & (A[15:2] == 14'h2800)) | (v_nk & (A[15:2] == 14'h2000)) |
                        (r5c1 & (A[15:2] == 14'h3000)) | (r5c2 & (A[15:2] == 14'h2000)));
wire cs_work  = mreq & ((pkw & (A[15:11] == 5'b11000)) | (v_nova & (A[15:13] == 3'b111)));
wire cs_share = mreq & (((v_nk | r5c1) & (A[15:11] == 5'b11100)) | (r5c2 & (A[15:11] == 5'b10100)));
wire cs_pal   = mreq & ((v_nk & (A[15:9] == 7'b1101100)) | (r5c1 & (A[15:9] == 7'b1101000)));
wire cs_nkio  = mreq & v_nk & (A[15:2] == 14'h2800);
wire cs_r5reg = mreq & ((r5c1 & (A[15:2] == 14'h2800)) | (r5c2 & (A[15:2] == 14'h3800)));

wire io_ay_d  = (cs_io & (A[2:1] == 2'b00)) | (cs_pay &  A[0]);
wire io_ay_a  = (cs_io & (A[2:1] == 2'b01)) | (cs_pay & ~A[0]);
wire ay_chip  = v_nova ? A[0] : A[1];
wire io_ack   = cs_io & (A[2:1] == 2'b10);
wire io_in    = cs_io & (A[2:1] == 2'b11);

assign maincpu_addr = r5c2 ? {2'b01, A[13:0]} : {1'b0, A[14:13], A[12] & (~v_nova | ~(A[14] & A[13])), A[11:0]};
assign aux_addr     = {3'd0, A[12:0]};

reg flip = 1'b0;
always_ff @(posedge clk) begin
    if (wr_cen & cs_flip)                                    flip <= ~cpu_dout[0];
    if (wr_cen & pkw & iorq & ~int_ack & (A[7:0] == 8'h00))  flip <=  cpu_dout[0];
    if (wr_cen & cs_r5reg & (A[1:0] == 2'd2))                flip <=  cpu_dout[0];
    if (wr_cen & cs_nkio & (A[1:0] == 2'd3))                 flip <=  cpu_dout[0] ^ who2;
end
wire flip_screen = flip ^ crt_flip;

reg [1:0] nk_ctrl = 2'd0;
always_ff @(posedge clk) begin
    if (reset) nk_ctrl <= 2'd0;
    else if (wr_cen & cs_nkio & (A[1:0] == 2'd2)) begin
        if (~who2) begin
            if (cpu_dout == 8'h80) nk_ctrl[0] <= 1'b1;
            if (cpu_dout == 8'h40) nk_ctrl[1] <= 1'b0;
        end else begin
            if (cpu_dout == 8'h40) nk_ctrl[1] <= 1'b1;
            if (cpu_dout == 8'h80) nk_ctrl[0] <= 1'b0;
        end
    end
end

reg [7:0] r5_sx = 8'd0, r5_sy = 8'd0;
always_ff @(posedge clk) begin
    if (wr_cen & cs_r5reg & (A[1:0] == 2'd0)) r5_sx <= cpu_dout;
    if (wr_cen & cs_r5reg & (A[1:0] == 2'd1)) r5_sy <= cpu_dout;
end

reg vbl_d = 1'b0;
reg irq   = 1'b0;
always_ff @(posedge clk) begin
    vbl_d <= vblank;
    if (reset)                                         irq <= 1'b0;
    else if (cen_cpu & io_ack & (rd | wr))             irq <= 1'b0;
    else if (cen_cpu & ~v_nova & ~who2 & int_ack)      irq <= 1'b0;
    else if (vblank & ~vbl_d)                          irq <= 1'b1;
end

wire line_start = cen_pix && (hc == 9'd319);
wire irq2_line  = v9[8] && (v8[5:0] == 6'd31);
reg  irq2 = 1'b0;
always_ff @(posedge clk) begin
    if (reset | ~dual)              irq2 <= 1'b0;
    else if (cen_cpu2 & int_ack)    irq2 <= 1'b0;
    else if (line_start & irq2_line & ~pause) irq2 <= 1'b1;
end

// watchdog frozen while paused: the stopped CPU cannot acknowledge, so pause must not trip it
reg [3:0] wdog = 4'd8;
always_ff @(posedge clk) begin
    if (reset | ~v_nova)                wdog <= 4'd8;
    else if (pause)                     ;
    else if (cs_stnpd)                  wdog <= 4'd0;
    else if (~vblank & vbl_d)           wdog <= irq ? wdog + 4'd1 : 4'd8;
end
wire cpu_reset = reset | ~wdog[3];

wire       coin_btn = ~keycoin[6];
reg        coin_btn_d = 1'b0;
reg  [2:0] coin_cnt   = 3'd0;
always_ff @(posedge clk) begin
    coin_btn_d <= coin_btn;
    if (reset)                                 coin_cnt <= 3'd0;
    else if (coin_btn & ~coin_btn_d)           coin_cnt <= v_r5 ? 3'd5 : 3'd4;
    else if (~pause & vblank & ~vbl_d & (coin_cnt != 3'd0)) coin_cnt <= coin_cnt - 3'd1;
end
wire coin_n = ~(coin_cnt != 3'd0);

wire [7:0] in0 = {pad1[4], pad1[5], 2'b11, pad1[0], pad1[1], pad1[2], pad1[3]};
wire [7:0] in1 = {pad2[4], pad2[5], 2'b11, pad2[0], pad2[1], pad2[2], pad2[3]};
wire [7:0] in2 = {~vblank, 4'b1111, keycoin[1], keycoin[0], coin_n};

wire [7:0] pk_in0 = {~vblank, 1'b1, keycoin[0], 2'b11, pad1[4], pad1[0], pad1[1]};
wire [7:0] pk_in1 = {keycoin[6], keycoin[3], keycoin[1], 2'b11, pad2[4], pad2[0], pad2[1]};

wire [7:0] nk_in0 = {2'b00, keycoin[0], 1'b1, pad1[4], pad1[5], pad1[0], pad1[1]};
wire [7:0] nk_in1 = {~keycoin[6], ~keycoin[3], keycoin[1], 1'b1, pad2[4], pad2[5], pad2[0], pad2[1]};
wire [7:0] nk_in2 = {4'b0000, nk_ctrl, ~vblank, 1'b0};

wire [7:0] r5_in0 = {~vblank, 1'b1, keycoin[0], pad1[4], pad1[3], pad1[2], pad1[0], pad1[1]};
wire [7:0] r5_in1 = {coin_n, keycoin[3], keycoin[1], pad2[4], pad2[3], pad2[2], pad2[0], pad2[1]};

reg [7:0] cpu_din;
always_comb begin
    if      (int_ack)            cpu_din = 8'hFF;
    else if (cs_rom)             cpu_din = maincpu_data;
    else if (cs_aux)             cpu_din = aux_data;
    else if (cs_fg)              cpu_din = fg_o.a_q;
    else if (cs_bg)              cpu_din = bg_o.a_q;
    else if (cs_spr)             cpu_din = spr_o.a_q;
    else if (cs_work)            cpu_din = work_o.a_q;
    else if (cs_share | cs_pal)  cpu_din = sh_o.a_q;
    else if (io_ay_d)            cpu_din = ay_chip ? ym_o[1].dout : ym_o[0].dout;
    else if (io_in)              cpu_din = (A[3:0] == 4'h6) ? in0 : (A[3:0] == 4'h7) ? in1 :
                                           (A[3:0] == 4'hE) ? in2 : 8'hFF;
    else if (cs_nkio)            cpu_din = (A[1:0] == 2'd0) ? nk_in0 : (A[1:0] == 2'd1) ? nk_in1 :
                                           (A[1:0] == 2'd2) ? nk_in2 : 8'hFF;
    else                         cpu_din = 8'hFF;
end

assign z80_i.reset_n = ~cpu_reset;
assign z80_i.ce      = cen_cpu & ~pause;
assign z80_i.int_n   = ~irq;
assign z80_i.nmi_n   = 1'b1;
assign z80_i.di      = cpu_din;

assign z80b_i.reset_n = ~(reset | ~dual);
assign z80b_i.ce      = cen_cpu2 & ~pause;
assign z80b_i.int_n   = ~irq2;
assign z80b_i.nmi_n   = 1'b1;
assign z80b_i.di      = cpu_din;

wire ay_sel = (io_ay_d | io_ay_a) & wr;
reg  ay_sel_d = 1'b0;
always_ff @(posedge clk) ay_sel_d <= ay_sel;

reg [1:0] ay_done = 2'b00;
always_ff @(posedge clk) begin
    if (cen_cpu)  ay_done[0] <= ay_sel;
    if (cen_cpu2) ay_done[1] <= ay_sel;
end
wire ay_wr = (dual ? (cen_bus & ay_sel & ~ay_done[who2]) : (ay_sel & ~ay_sel_d)) & ~cpu_reset;

genvar ai;
generate
    for (ai = 0; ai < 2; ai = ai + 1) begin : ay
        wire sel = ay_chip ? (ai == 1) : (ai == 0);
        assign ym_i[ai].rst    = cpu_reset;
        assign ym_i[ai].ce     = cen_ay;
        assign ym_i[ai].cs_n   = ~(ay_wr & sel);
        assign ym_i[ai].wr_n   = ~(ay_wr & sel);
        assign ym_i[ai].addr   = ~io_ay_a;
        assign ym_i[ai].din    = cpu_dout;
    end
endgenerate

assign ym_i[0].ioa_in = pkw ? pk_in0 : v_r5 ? r5_in0 : v_nk ? dsw1 : 8'hFF;
assign ym_i[0].iob_in = pkw ? pk_in1 : v_r5 ? r5_in1 : v_nk ? dsw2 : 8'hFF;
assign ym_i[1].ioa_in = (pkw | v_r5) ? dsw2 : v_nk ? 8'hFF : dsw1;
assign ym_i[1].iob_in = (pkw | v_r5) ? dsw1 : v_nk ? 8'hFF : dsw2;

wire [7:0] ay_sx = v_nk ? (ym_o[1].ioa_oe ? ym_o[1].ioa_out : 8'hFF) : (ym_o[0].ioa_oe ? ym_o[0].ioa_out : 8'hFF);
wire [7:0] ay_sy = v_nk ? (ym_o[1].iob_oe ? ym_o[1].iob_out : 8'hFF) : (ym_o[0].iob_oe ? ym_o[0].iob_out : 8'hFF);
wire [7:0] scroll_x = pkw ? 8'd0 : v_r5 ? r5_sx : ay_sx;
wire [7:0] scroll_y = pkw ? 8'd0 : v_r5 ? r5_sy : ay_sy;

wire [10:0] ay_sum = {1'b0, ym_o[0].psg_snd} + {1'b0, ym_o[1].psg_snd};
assign sound = pause ? 16'sd0 : $signed({1'b0, ay_sum, 4'd0}) - 16'sd16384;

wire [10:0] a11 = A[10:0];

wire [9:0]  bg_win  = a11[9:0] + {scroll_y[7:3], scroll_x[7:3]};
wire [10:0] bg_cpu  = dual ? {a11[10], bg_win} : a11;

wire [12:0] sh_cpu  = cs_pal ? {4'b0100, A[8:0]} : {2'b00, a11[10] ^ (v_nk & who2), a11[9:0]};

assign fg_i.a_addr   = {5'd0, a11};     assign fg_i.a_we   = wr_cen & cs_fg;
assign bg_i.a_addr   = {5'd0, bg_cpu};  assign bg_i.a_we   = wr_cen & cs_bg;
assign spr_i.a_addr  = {5'd0, a11};     assign spr_i.a_we  = wr_cen & cs_spr;
assign work_i.a_addr = {5'd0, a11};     assign work_i.a_we = wr_cen & cs_work;
assign sh_i.a_addr   = {3'b00, sh_cpu}; assign sh_i.a_we   = wr_cen & (cs_share | cs_pal);

assign fg_i.a_d   = cpu_dout;
assign bg_i.a_d   = cpu_dout;
assign spr_i.a_d  = cpu_dout;
assign work_i.a_d = cpu_dout;
assign sh_i.a_d   = cpu_dout;

assign fg_i.b_we   = 1'b0;  assign fg_i.b_d   = 8'd0;
assign bg_i.b_we   = 1'b0;  assign bg_i.b_d   = 8'd0;
assign spr_i.b_we  = 1'b0;  assign spr_i.b_d  = 8'd0;
assign work_i.b_we = 1'b0;  assign work_i.b_d = 8'd0;
assign sh_i.b_we   = 1'b0;  assign sh_i.b_d   = 8'd0;
assign work_i.b_addr = 16'd0;

function automatic [17:0] gfx_map(input gfx2, input [15:0] g);
    gfx_map = {2'b00, g[15] | gfx2, g[14], g[0], g[13:1]};
endfunction

wire [7:0] xf = hc[7:0] ^ {8{flip_screen}};
wire [7:0] yf = v8      ^ {8{flip_screen}};

wire [7:0] bx = xf + scroll_x - (dual ? 8'd7 : 8'd0);
wire [7:0] by = yf + scroll_y;

wire [9:0] fg_idx = {yf[7:3], xf[7:3]};
wire [9:0] bg_idx = {by[7:3], bx[7:3]};

reg  [7:0] fg_code, fg_attr, bg_code, bg_attr, fg_byte, bg_byte;
reg [31:0] fb_word;
wire [31:0] fb_q;

wire attr_ph = (pix_ph >= 4'd2);
assign fg_i.b_addr = {5'd0, attr_ph, fg_idx};
assign bg_i.b_addr = {5'd0, attr_ph, bg_idx};

wire [10:0] fg_code11 = v_nk ? {2'b00, fg_attr[5], fg_code} : {3'b000, fg_code};
wire [10:0] bg_code11 = pkw  ? {bg_attr[2:0], bg_code} : v_nk ? {1'b0, bg_attr[7:6], bg_code} :
                        v_r5 ? {2'b00, bg_attr[0], bg_code} : {3'b010, bg_code};
wire [15:0] fg_g = {fg_code11, yf[2:0], xf[2:1]};
wire [15:0] bg_g = {bg_code11, by[2:0], bx[2:1]};

always_ff @(posedge clk) begin
    case (pix_ph)
        4'd2: begin fg_code <= fg_o.b_q; bg_code <= bg_o.b_q; fb_word <= fb_q; end
        4'd3: begin fg_attr <= fg_o.b_q; bg_attr <= bg_o.b_q; end
        4'd4: fg_byte <= gfx_data;
        4'd5: bg_byte <= gfx_data;
        default: ;
    endcase
end

wire [3:0] fg_pen = xf[0] ? fg_byte[3:0] : fg_byte[7:4];
wire [3:0] bg_pen = bx[0] ? bg_byte[3:0] : bg_byte[7:4];
wire [3:0] sp_pen = fb_word[{xf[1:0], 3'b000} +: 4];

wire [3:0] fg_col = v_r5 ? fg_attr[7:4] : fg_attr[3:0];
wire [3:0] bg_col = (pkw | v_r5) ? bg_attr[7:4] : bg_attr[3:0];

wire [3:0] fg_pix = (fg_pen == 4'd1) ? fg_col : fg_pen;
wire [3:0] bg_pix = (bg_pen == 4'd1) ? bg_col : bg_pen;

wire        fg_op  = ~pkw & (fg_pen != 4'd0);
wire        fg_lo  = v_nk & fg_attr[4];
wire        bg_hi  = pkw & bg_attr[3] & (bg_pen != 4'd0);
wire        sp_op  = (sp_pen != 4'd0) & ~bg_hi;
wire [1:0]  layer  = (fg_op & ~fg_lo) ? 2'd0 : sp_op ? 2'd1 : fg_op ? 2'd0 : 2'd2;

wire [4:0]  pal_a  = (layer == 2'd0) ? {1'b0, fg_pix} : (layer == 2'd1) ? {1'b0, sp_pen} : {1'b1, bg_pix};
wire [8:0]  pal_r  = (layer == 2'd0) ? {1'b0, fg_col, fg_pen} : (layer == 2'd1) ? {5'd0, sp_pen} : {1'b1, bg_col, bg_pen};
assign sh_i.b_addr = {5'b00001, 2'b00, pal_r};
assign prom_addr = pal_a;
wire [7:0]  pal_q  = dual ? sh_o.b_q : prom_data;

wire [3:0] r4 = {pal_q[3:2], pal_q[1:0]};
wire [3:0] g4 = {pal_q[5:4], pal_q[1:0]};
wire [3:0] b4 = {pal_q[7:6], pal_q[1:0]};

always_ff @(posedge clk) begin
    if (pix_ph == 4'd9) begin
        R <= disp ? {r4, r4} : 8'd0;
        G <= disp ? {g4, g4} : 8'd0;
        B <= disp ? {b4, b4} : 8'd0;
        HBlank <= hblank;
        VBlank <= vblank;
        HSync  <= hsync_o;
        VSync  <= vsync_o;
    end
end

localparam [2:0] S_IDLE = 3'd0, S_REC = 3'd1, S_ATTR = 3'd2, S_FETCH = 3'd3, S_WAIT = 3'd4, S_PIX0 = 3'd5, S_PIX1 = 3'd6;

reg  [2:0] s_st = S_IDLE;
reg  [1:0] s_byte = 2'd0;
reg  [7:0] s_code, s_x, s_y, s_attr;
reg  [7:0] s_r_c;
reg  [7:0] s_gbyte;
reg        s_lane;

wire [5:0] s_idx = {~v8[5], v8[4:0]};
assign spr_i.b_addr = {5'd0, s_idx, 3'b000, s_byte};

wire [8:0] s_code9 = pk_spr ? {s_attr[2:0] & {~v_r5, 2'b11}, s_code[7:2]} : {1'b0, s_code};
wire       s_fx    = pk_spr ? s_code[0] : s_attr[4];
wire       s_fy    = pk_spr ? s_code[1] : s_attr[5];
wire [3:0] s_color = pk_spr ? s_attr[7:4] : s_attr[3:0];
wire       s_off   = pk_spr ? s_attr[3] : s_attr[7];

wire [3:0] s_row  = s_r_c[7:4];
wire [2:0] s_pair = s_r_c[2:0];
wire [3:0] s_ry   = s_fy ? ~s_row : s_row;
wire [3:0] s_col  = {s_pair, s_lane};
wire [3:0] s_cx   = s_fx ? ~s_col : s_col;

wire [3:0]  s_cx_pair = s_fx ? ~{s_pair, 1'b0} : {s_pair, 1'b0};
wire [15:0] s_g = {s_code9, s_ry[3], s_cx_pair[3], s_ry[2:0], s_cx_pair[2:1]};

wire [3:0] s_pen  = s_cx[0] ? s_gbyte[3:0] : s_gbyte[7:4];
wire [3:0] s_pix  = (s_pen == 4'd1) ? s_color : s_pen;
wire [8:0] s_px   = {1'b0, s_x} + {5'd0, s_col};
wire [7:0] s_py   = s_y + {4'd0, s_row};
wire       s_we   = (s_pen != 4'd0) && (pk_spr || (s_px[8] == s_attr[6])) && !s_off && !vsync_l;

wire s_start = cen_pix && (hc == 9'd0) && vblank;

always_ff @(posedge clk) begin
    if (reset) begin
        s_st <= S_IDLE;
    end else begin
        case (s_st)
            S_IDLE: if (s_start) begin s_byte <= 2'd0; s_st <= S_REC; end
            S_REC: begin
                case (s_byte)
                    2'd1: s_code <= spr_o.b_q;
                    2'd2: s_x    <= spr_o.b_q;
                    2'd3: s_y    <= spr_o.b_q;
                    default: ;
                endcase
                s_byte <= s_byte + 2'd1;
                if (s_byte == 2'd3) s_st <= S_ATTR;
            end
            S_ATTR:  begin s_attr <= spr_o.b_q; s_r_c <= 8'd0; s_st <= S_FETCH; end
            S_FETCH: s_st <= S_WAIT;
            S_WAIT:  begin s_gbyte <= gfx_data; s_lane <= 1'b0; s_st <= S_PIX0; end
            S_PIX0:  begin s_lane <= 1'b1; s_st <= S_PIX1; end
            S_PIX1: begin
                if (s_r_c == 8'hF7) s_st <= S_IDLE;
                else begin
                    s_r_c <= (s_r_c[2:0] == 3'd7) ? {s_r_c[7:4] + 4'd1, 4'd0} : s_r_c + 8'd1;
                    s_st  <= S_FETCH;
                end
            end
            default: s_st <= S_IDLE;
        endcase
    end
end

wire disp_bg_ph = (pix_ph >= 4'd4);
assign gfx_addr = gfx_map(~vblank & disp_bg_ph & dual, vblank ? s_g : disp_bg_ph ? bg_g : fg_g);

wire s_wr_now = (s_st == S_PIX0 || s_st == S_PIX1) && s_we;

wire erase = disp && (pix_ph == 4'd6) && (xf[1:0] == (flip_screen ? 2'd0 : 2'd3));

genvar fl;
generate
    for (fl = 0; fl < 4; fl = fl + 1) begin : fb_lane
        assign pr_i[5 + fl].a_addr = {2'b0, s_py, s_px[7:2]};
        assign pr_i[5 + fl].a_we   = s_wr_now & (s_px[1:0] == fl);
        assign pr_i[5 + fl].a_d    = {4'd0, s_pix};
        assign pr_i[5 + fl].b_addr = {2'b0, yf, xf[7:2]};
        assign pr_i[5 + fl].b_we   = erase;
        assign pr_i[5 + fl].b_d    = 8'd0;
    end
endgenerate
assign fb_q = {pr_o[8].b_q, pr_o[7].b_q, pr_o[6].b_q, pr_o[5].b_q};

endmodule
