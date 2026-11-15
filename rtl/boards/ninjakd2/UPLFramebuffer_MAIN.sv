//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)

module UPLFramebuffer_MAIN
(
    input                clk,
    input                cen_cpu,
    input                reset,
    input                pause,

    input          [7:0] set_id,

    input          [7:0] keycoin,
    input          [7:0] pad1,
    input          [7:0] pad2,
    input          [7:0] dsw1,
    input          [7:0] dsw2,

    output        [15:0] maincpu_addr,
    output         [3:0] maincpu_bank,
    input          [7:0] maincpu_data,

    output         [7:0] sound_latch,
    output               sound_latch_wr,
    output               snd_reset,

    input                crt_flip,
    output               flip_screen,
    output               sprite_overdraw,
    output        [15:0] bg0_scrollx, bg0_scrolly,
    output        [15:0] bg1_scrollx, bg1_scrolly,
    output        [15:0] bg2_scrollx, bg2_scrolly,
    output         [2:0] bg_layer_en,

    input         [10:0] fg_vram_addr,   output  [7:0] fg_vram_data,
    input         [12:0] bg0_vram_addr,  output  [7:0] bg0_vram_data,
    input         [12:0] bg1_vram_addr,  output  [7:0] bg1_vram_data,
    input         [12:0] bg2_vram_addr,  output  [7:0] bg2_vram_data,
    input         [12:0] work_addr,      output  [7:0] work_data,
    input          [9:0] pal_index,      output [15:0] pal_rgb,

    input                vblank,

    output chip_pool_pkg::z80r_i_t        z80_i,
    input  chip_pool_pkg::z80_o_t         z80_o,
    output ram_pool_pkg::pram_i_t         fg_i,
    input  ram_pool_pkg::pram_o_t         fg_o,
    output ram_pool_pkg::pram_i_t   [3:0] r8_i,
    input  ram_pool_pkg::pram_o_t   [3:0] r8_o,
    output ram_pool_pkg::pram_i_t   [1:0] pal_i,       // palette RAM, 0 = low byte, 1 = high byte
    input  ram_pool_pkg::pram_o_t   [1:0] pal_o
);

    wire [15:0] A        = z80_o.a;
    wire  [7:0] cpu_dout = z80_o.dout;
    wire        mreq_n   = z80_o.mreq_n;
    wire        iorq_n   = z80_o.iorq_n;
    wire        rd_n     = z80_o.rd_n;
    wire        wr_n     = z80_o.wr_n;
    wire        m1_n     = z80_o.m1_n;

    wire mem_wr = ~mreq_n & ~wr_n;
    wire mem_rd = ~mreq_n & ~rd_n;
    wire int_ack = ~m1_n & ~iorq_n;

    wire is_mnight  = (set_id >= 8'h06) && (set_id <= 8'h08);
    wire is_robokid = (set_id >= 8'h09) && (set_id <= 8'h0C);
    wire is_omegaf  = (set_id >= 8'h0D) && (set_id <= 8'h0F);

    wire cs_rom   = (A[15] == 1'b0);
    wire cs_bank  = (A[15:14] == 2'b10);

    wire cs_in    = is_omegaf  ? ((A[15:8] == 8'hC0) && (A[7:0] == 8'd0))
                  : is_robokid ? ((A[15:8] == 8'hDC) && (A[7:0] < 8'd5))
                  : is_mnight  ? ((A[15:8] == 8'hF8) && (A[7:0] < 8'd5))
                               : ((A[15:8] == 8'hC0) && (A[7:0] < 8'd5));
    wire cs_ctrl  = is_omegaf  ? ((A[15:8] == 8'hC0) && (A[7:0] <= 8'h06))
                  : is_robokid ? (A[15:8] == 8'hDC)
                  : is_mnight  ? (A[15:8] == 8'hFA)
                               : (A[15:8] == 8'hC2);
    wire cs_pal   = is_omegaf  ? (A[15:11] == 5'b11011)
                  : is_robokid ? ((A >= 16'hC000) && (A < 16'hC800))
                  : is_mnight  ? ((A >= 16'hF000) && (A < 16'hF600))
                               : ((A >= 16'hC800) && (A < 16'hCE00));
    wire cs_fg    = is_robokid ? (A[15:11] == 5'b11001)
                  : is_mnight  ? (A[15:11] == 5'b11101)
                               : (A[15:11] == 5'b11010);
    wire cs_bg    = (is_robokid || is_omegaf) ? 1'b0
                  : is_mnight  ? (A[15:11] == 5'b11100)
                               : (A[15:11] == 5'b11011);
    wire cs_work  = is_mnight  ? (A[15:13] == 3'b110)
                               : (A[15:13] == 3'b111);

    wire cs_bgb   = (is_robokid && (A[15:12] == 4'hD) && (A[11:10] != 2'b11))
                  || (is_omegaf  && (A[15:12] == 4'hC) && (A[11:10] != 2'b00));

    wire cs_bgctl = (is_robokid && (A[15:10] == 6'b110111) && (A[9:8] != 2'b00))
                  || (is_omegaf  && (A[15:12] == 4'hC) && (A[11:10] == 2'b00)
                                 && (A[9:8] != 2'b00) && (A[7:0] <= 8'h05));

    // C1E7 must read 0xFF or omegaf's small enemies never fire (the mux default does)
    wire cs_prot = is_omegaf && (A[15:8] == 8'hC0) && (A[7:0] >= 8'd1) && (A[7:0] <= 8'd3);

    assign maincpu_addr = A;

    reg  [3:0] bank_reg    = 4'd0;
    reg        flip_reg    = 1'b0;
    reg        sndrst_reg  = 1'b0;
    reg        overdraw    = 1'b0;
    reg [15:0] scrollx     = 16'd0;
    reg [15:0] scrolly     = 16'd0;
    reg        bgen        = 1'b1;
    reg  [7:0] latch_reg   = 8'd0;
    reg        latch_wr    = 1'b0;
    reg [15:0] bg_sx   [0:2];
    reg [15:0] bg_sy   [0:2];
    reg  [2:0] bg_bank [0:2];
    reg  [2:0] bg_en_l = 3'd0;
    integer    li;
    reg  [7:0] prot0       = 8'd0;
    reg  [7:0] prot1       = 8'd0;
    reg  [7:0] prot2       = 8'd0;
    reg  [7:0] prot_in     = 8'd0;
    reg        prot_tick   = 1'b0;

    wire [3:0] bank_mask = (set_id >= 8'h09) ? 4'hF : 4'h7;

    wire [2:0] bgbank_mask = is_omegaf ? 3'd7 : 3'd1;
    wire [1:0] ctl_lyr     = A[9:8] - 2'd1;

    wire ctrl_wr = cen_cpu & mem_wr & cs_ctrl;

    always_ff @(posedge clk) begin
        latch_wr <= 1'b0;
        if (reset) begin
            bank_reg <= 4'd0; flip_reg <= 1'b0; sndrst_reg <= 1'b0;
            overdraw <= 1'b0; bgen <= 1'b1; bg_en_l <= 3'd0;
            for (li = 0; li < 3; li = li + 1) begin
                bg_sx[li] <= 16'd0; bg_sy[li] <= 16'd0; bg_bank[li] <= 3'd0;
            end
            prot0 <= 8'd0; prot1 <= 8'd0; prot2 <= 8'd0; prot_in <= 8'd0;
        end else if (cen_cpu && mem_wr && cs_bgctl) begin
            case (A[7:0])
                8'h00: bg_sx[ctl_lyr][7:0]  <= cpu_dout;
                8'h01: bg_sx[ctl_lyr][15:8] <= cpu_dout;
                8'h02: bg_sy[ctl_lyr][7:0]  <= cpu_dout;
                8'h03: bg_sy[ctl_lyr][15:8] <= cpu_dout;
                8'h04: bg_en_l[ctl_lyr]     <= cpu_dout[0];
                8'h05: bg_bank[ctl_lyr]     <= cpu_dout[2:0] & bgbank_mask;
                default: ;
            endcase
        end else if (ctrl_wr) begin
            case (A[7:0])
                8'h00: begin latch_reg <= cpu_dout; latch_wr <= 1'b1; end
                8'h01: begin sndrst_reg <= cpu_dout[4]; flip_reg <= cpu_dout[7]; end
                8'h02: bank_reg <= cpu_dout[3:0] & bank_mask;
                8'h03: overdraw <= cpu_dout[0];
                8'h04: prot0 <= cpu_dout;
                8'h05: prot1 <= cpu_dout;
                8'h06: begin
                    if (cpu_dout[0] && !prot2[0]) prot_in <= prot0;
                    prot2 <= cpu_dout;
                end
                8'h08: scrollx[7:0]  <= cpu_dout;
                8'h09: scrollx[15:8] <= cpu_dout;
                8'h0A: scrolly[7:0]  <= cpu_dout;
                8'h0B: scrolly[15:8] <= cpu_dout;
                8'h0C: bgen <= cpu_dout[0];
                default: ;
            endcase
        end
    end

    wire [1:0] prot_mode = prot1[1:0];
    wire [1:0] prot_off  = A[1:0] - 2'd1;

    reg [7:0] prot_dout;
    always_comb begin
        prot_dout = 8'hFF;
        case (prot_mode)
            2'd0: if (prot_off == 2'd1)
                      case (prot0[7:5])
                          3'b000: prot_dout = prot_tick ? 8'h00
                                            : (prot_in == 8'h00) ? 8'h82
                                            : (prot_in == 8'h8C) ? 8'h9F
                                            : (prot_in == 8'h89) ? 8'h8B : 8'hFF;
                          3'b001: prot_dout = 8'hC7;
                          3'b011: prot_dout = 8'h00;
                          3'b100: prot_dout = {3'b001, prot_in[4:0]};
                          3'b110: prot_dout = {3'b011, prot_in[4:0]};
                          default: ;
                      endcase
            2'd1: prot_dout = (prot_off == 2'd0) ? dsw1 : (prot_off == 2'd1) ? dsw2 : 8'h02;
            2'd2: prot_dout = (prot_off == 2'd0) ? pad1 : (prot_off == 2'd1) ? pad2 : 8'h01;
            default: ;
        endcase
    end

    wire prot_tick_cond = cs_prot & mem_rd & (prot_mode == 2'd0)
                        & (prot_off == 2'd1) & (prot0[7:5] == 3'b000);
    reg  prot_tick_d;

    always_ff @(posedge clk) begin
        if (reset) begin
            prot_tick <= 1'b0; prot_tick_d <= 1'b0;
        end else begin
            prot_tick_d <= prot_tick_cond;
            if (prot_tick_cond && !prot_tick_d) prot_tick <= ~prot_tick;
        end
    end

    assign maincpu_bank    = bank_reg;
    assign sound_latch     = latch_reg;
    assign sound_latch_wr  = latch_wr;
    assign snd_reset       = sndrst_reg;
    assign flip_screen     = flip_reg ^ crt_flip;
    assign sprite_overdraw = overdraw;
    wire use_layer_ctrl    = is_robokid | is_omegaf;
    assign bg0_scrollx     = use_layer_ctrl ? bg_sx[0] : scrollx;
    assign bg0_scrolly     = use_layer_ctrl ? bg_sy[0] : scrolly;
    assign bg1_scrollx     = bg_sx[1];
    assign bg1_scrolly     = bg_sy[1];
    assign bg2_scrollx     = bg_sx[2];
    assign bg2_scrolly     = bg_sy[2];
    assign bg_layer_en     = use_layer_ctrl ? bg_en_l : {2'b00, bgen};

    wire [9:0]  pal_ent  = A[10:1];
    wire        pal_wr   = cen_cpu & mem_wr & cs_pal;
    wire [15:0] pal_q_a = {pal_o[1].a_q, pal_o[0].a_q};

    genvar pl;
    generate
        for (pl = 0; pl < 2; pl = pl + 1) begin : pal_lane
            assign pal_i[pl].a_addr = {6'd0, pal_ent};
            assign pal_i[pl].a_d    = cpu_dout;
            assign pal_i[pl].a_we   = pal_wr & (A[0] ? (pl == 0) : (pl == 1));
            assign pal_i[pl].b_addr = {6'd0, pal_index};
            assign pal_i[pl].b_d    = 8'd0;
            assign pal_i[pl].b_we   = 1'b0;
        end
    endgenerate
    assign pal_rgb = {pal_o[1].b_q, pal_o[0].b_q};

    wire [7:0] fg_q_a, bg0_q_a, bg1_q_a, bg2_q_a, work_q_a;

    assign fg_i.a_addr  = {5'd0, A[10:0]};
    assign fg_i.a_we    = cen_cpu & mem_wr & cs_fg;
    assign fg_i.a_d     = cpu_dout;
    assign fg_i.b_addr  = {5'd0, fg_vram_addr};
    assign fg_i.b_we    = 1'b0;
    assign fg_i.b_d     = 8'd0;
    assign fg_q_a       = fg_o.a_q;
    assign fg_vram_data = fg_o.b_q;

    // robokid window -> layer is reversed vs its DD/DE/DF control order
    wire [1:0]  bgb_lyr  = is_omegaf ? (A[11:10] - 2'd1) : (2'd2 - A[11:10]);
    wire [2:0]  bgb_bnk  = bg_bank[bgb_lyr];
    wire [12:0] bgb_addr = {bgb_bnk, A[9:0]};

    wire bgb_wr = cen_cpu & mem_wr & cs_bgb;
    wire bg0_wr = (cen_cpu & mem_wr & cs_bg) | (bgb_wr & (bgb_lyr == 2'd0));
    wire bg1_wr =                               bgb_wr & (bgb_lyr == 2'd1);
    wire bg2_wr =                               bgb_wr & (bgb_lyr == 2'd2);

    wire [12:0] bg0_addr = cs_bg ? {2'b00, A[10:0]} : bgb_addr;

    wire [7:0] bgb_q_a = (bgb_lyr == 2'd0) ? bg0_q_a :
                         (bgb_lyr == 2'd1) ? bg1_q_a : bg2_q_a;

    wire [12:0] r8_a_addr [0:3];
    wire        r8_a_we   [0:3];
    wire [12:0] r8_b_addr [0:3];
    assign r8_a_addr[0] = bg0_addr;  assign r8_a_we[0] = bg0_wr;                    assign r8_b_addr[0] = bg0_vram_addr;
    assign r8_a_addr[1] = bgb_addr;  assign r8_a_we[1] = bg1_wr;                    assign r8_b_addr[1] = bg1_vram_addr;
    assign r8_a_addr[2] = bgb_addr;  assign r8_a_we[2] = bg2_wr;                    assign r8_b_addr[2] = bg2_vram_addr;
    assign r8_a_addr[3] = A[12:0];   assign r8_a_we[3] = cen_cpu & mem_wr & cs_work; assign r8_b_addr[3] = work_addr;

    genvar ri;
    generate
        for (ri = 0; ri < 4; ri = ri + 1) begin : r8
            assign r8_i[ri].a_addr = {3'b00, r8_a_addr[ri]};
            assign r8_i[ri].a_we   = r8_a_we[ri];
            assign r8_i[ri].a_d    = cpu_dout;
            assign r8_i[ri].b_addr = {3'b00, r8_b_addr[ri]};
            assign r8_i[ri].b_we   = 1'b0;
            assign r8_i[ri].b_d    = 8'd0;
        end
    endgenerate

    assign bg0_q_a  = r8_o[0].a_q;   assign bg0_vram_data = r8_o[0].b_q;
    assign bg1_q_a  = r8_o[1].a_q;   assign bg1_vram_data = r8_o[1].b_q;
    assign bg2_q_a  = r8_o[2].a_q;   assign bg2_vram_data = r8_o[2].b_q;
    assign work_q_a = r8_o[3].a_q;   assign work_data     = r8_o[3].b_q;

    reg vbl_d = 1'b0;
    reg irq_pending = 1'b0;

    always_ff @(posedge clk) begin
        vbl_d <= vblank;
        if (reset)                        irq_pending <= 1'b0;
        else if (vblank && !vbl_d)        irq_pending <= 1'b1;
        else if (cen_cpu && int_ack)      irq_pending <= 1'b0;
    end

    reg [7:0] cpu_din;

    always_comb begin
        if      (int_ack)  cpu_din = 8'hD7;
        else if (cs_rom)   cpu_din = maincpu_data;
        else if (cs_bank)  cpu_din = maincpu_data;
        else if (cs_in)    cpu_din = (A[2:0] == 3'd0) ? keycoin :
                                     (A[2:0] == 3'd1) ? pad1    :
                                     (A[2:0] == 3'd2) ? pad2    :
                                     (A[2:0] == 3'd3) ? dsw1    : dsw2;
        else if (cs_prot)  cpu_din = prot_dout;
        else if (cs_pal)   cpu_din = A[0] ? pal_q_a[7:0] : pal_q_a[15:8];
        else if (cs_fg)    cpu_din = fg_q_a;
        else if (cs_bg)    cpu_din = bg0_q_a;
        else if (cs_bgb)   cpu_din = bgb_q_a;
        else if (cs_work)  cpu_din = work_q_a;
        else               cpu_din = 8'hFF;
    end

    assign z80_i.reset_n = ~reset;
    assign z80_i.ce      = cen_cpu & ~pause;
    assign z80_i.int_n   = ~irq_pending;
    assign z80_i.nmi_n   = 1'b1;
    assign z80_i.di      = cpu_din;

endmodule
