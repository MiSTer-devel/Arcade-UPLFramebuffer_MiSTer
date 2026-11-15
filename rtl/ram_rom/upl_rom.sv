//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)
module upl_rom
(
    input                clk,
    // power-on only: must never include ioctl_download
    input                por_reset,

    input                rd_auto,       // 1 = use the detected latch when detection succeeded
    input          [1:0] rd_mode,       // 0 = Early, 1 = Normal, 2 = Late
    input                recal,
    input                ph_auto,
    input                ld_hold,       // status[0]: Main holds it across the whole MRA load
    output         [6:0] ph_req_val,
    output               ph_req_tgl,
    output               cal_hold,

    input                ioctl_download,
    input          [7:0] ioctl_index,
    input         [24:0] ioctl_addr,
    input          [7:0] ioctl_data,
    input                ioctl_wr,
    output               ioctl_wait,

    output reg     [7:0] set_id,

    input         [15:0] maincpu_addr,
    input          [3:0] maincpu_bank,
    output         [7:0] maincpu_data,

    input                gfx_sel,
    input         [17:0] gfx_addr,
    output         [7:0] gfx_data,

    input         [15:0] audiocpu_addr,
    input                audiocpu_m1,
    output         [7:0] audiocpu_data,

    input         [14:0] char_addr,   input char_req,   output char_ack,   output [7:0] char_data,
    input         [17:0] spr_addr,    input spr_req,    output spr_ack,    output [7:0] spr_data,
    input         [18:0] tile1_addr,  input tile1_req,  output tile1_ack,  output [7:0] tile1_data,
    input         [18:0] tile2_addr,  input tile2_req,  output tile2_ack,  output [7:0] tile2_data,
    input         [18:0] tile3_addr,  input tile3_req,  output tile3_ack,  output [7:0] tile3_data,
    input         [15:0] pcm_addr,    input pcm_req,    output pcm_ack,    output [7:0] pcm_data,

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

    // MRA index map, must match releases/*.mra
    localparam [7:0] IDX_MAIN = 8'd0,  IDX_SND  = 8'd1,  IDX_CHAR = 8'd2,
                     IDX_SET  = 8'd5,  IDX_SPR  = 8'd6,  IDX_TIL1 = 8'd7,
                     IDX_TIL2 = 8'd8,  IDX_TIL3 = 8'd9,  IDX_PCM  = 8'd10,
                     IDX_PROM = 8'd11, IDX_KEY  = 8'd12;

    localparam [23:0] SDR_CHAR = 24'h000000,
                      SDR_SPR  = 24'h040000,
                      SDR_TIL1 = 24'h080000,
                      SDR_TIL2 = 24'h100000,
                      SDR_TIL3 = 24'h180000,
                      SDR_PCM  = 24'h200000,
                      SDR_PROM = 24'h210000;

    wire in_sdram = (ioctl_index == IDX_CHAR) || (ioctl_index == IDX_SPR)  ||
                    (ioctl_index == IDX_TIL1) || (ioctl_index == IDX_TIL2) ||
                    (ioctl_index == IDX_TIL3) || (ioctl_index == IDX_PCM)  ||
                    (ioctl_index == IDX_PROM);

    reg [23:0] dl_base;
    always_comb begin
        case (ioctl_index)
            IDX_CHAR: dl_base = SDR_CHAR;
            IDX_SPR : dl_base = SDR_SPR;
            IDX_TIL1: dl_base = SDR_TIL1;
            IDX_TIL2: dl_base = SDR_TIL2;
            IDX_TIL3: dl_base = SDR_TIL3;
            IDX_PCM : dl_base = SDR_PCM;
            IDX_PROM: dl_base = SDR_PROM;
            default : dl_base = 24'd0;
        endcase
    end

    always_ff @(posedge clk)
        if (ioctl_wr && ioctl_index == IDX_SET) set_id <= ioctl_data;

    wire use_opcodes = (set_id == 8'h01) || (set_id == 8'h02);

    wire mc8123 = (set_id == 8'h00) || (set_id == 8'h03)
               || (set_id == 8'h04) || (set_id == 8'h05);

    wire [18:0] mc_off      = ioctl_addr[18:0];
    wire        mc_is_fixed = (mc_off < 19'h08000);
    wire [18:0] mc_bank_off = mc_off - 19'h08000;
    wire        mc_wr       = ioctl_wr && (ioctl_index == IDX_MAIN);

    wire [7:0] mc_fixed_q, mc_bank_q;

    dpram_dc #(.widthad_a(15), .width_a(8)) rom_main_fixed
    (
        .clock_a(clk), .address_a(maincpu_addr[14:0]),
        .data_a(8'd0), .wren_a(1'b0), .q_a(mc_fixed_q),
        .clock_b(clk), .address_b(mc_off[14:0]),
        .data_b(ioctl_data), .wren_b(mc_wr && mc_is_fixed), .q_b()
    );

    dpram_dc #(.widthad_a(18), .width_a(8)) rom_main_bank
    (
        .clock_a(clk), .address_a(gfx_sel ? gfx_addr : {maincpu_bank, maincpu_addr[13:0]}),
        .data_a(8'd0), .wren_a(1'b0), .q_a(mc_bank_q),
        .clock_b(clk), .address_b(mc_bank_off[17:0]),
        .data_b(ioctl_data), .wren_b(mc_wr && !mc_is_fixed), .q_b()
    );

    assign maincpu_data = maincpu_addr[15] ? mc_bank_q : mc_fixed_q;
    assign gfx_data     = mc_bank_q;

    wire [16:0] sc_off   = ioctl_addr[16:0];
    wire        sc_is_op = sc_off[16];
    wire        sc_wr    = ioctl_wr && (ioctl_index == IDX_SND);

    wire [7:0] sc_op_q, sc_lo_q, sc_hi_q;

    dpram_dc #(.widthad_a(15), .width_a(8)) rom_snd_lo
    (
        .clock_a(clk), .address_a(audiocpu_addr[14:0]),
        .data_a(8'd0), .wren_a(1'b0), .q_a(sc_lo_q),
        .clock_b(clk), .address_b(sc_off[14:0]),
        .data_b(ioctl_data), .wren_b(sc_wr && !sc_is_op && !sc_off[15]), .q_b()
    );

    dpram_dc #(.widthad_a(14), .width_a(8)) rom_snd_hi
    (
        .clock_a(clk), .address_a(audiocpu_addr[13:0]),
        .data_a(8'd0), .wren_a(1'b0), .q_a(sc_hi_q),
        .clock_b(clk), .address_b(sc_off[13:0]),
        .data_b(ioctl_data), .wren_b(sc_wr && !sc_is_op && (sc_off[15:14] == 2'b10)), .q_b()
    );

    wire [7:0] sc_data_q = audiocpu_addr[15] ? sc_hi_q : sc_lo_q;

    wire [10:0] tbl_num = {audiocpu_addr[14], audiocpu_addr[13], audiocpu_addr[12],
                           audiocpu_addr[11], audiocpu_addr[10], audiocpu_addr[8],
                           audiocpu_addr[6],  audiocpu_addr[4],  audiocpu_addr[2],
                           audiocpu_addr[1],  audiocpu_addr[0]};

    wire [14:0] sc_op_addr = mc8123 ? {3'd0, ~audiocpu_m1, tbl_num} : audiocpu_addr[14:0];
    wire        key_wr     = ioctl_wr && (ioctl_index == IDX_KEY);

    dpram_dc #(.widthad_a(15), .width_a(8)) rom_snd_opcodes
    (
        .clock_a(clk), .address_a(sc_op_addr),
        .data_a(8'd0), .wren_a(1'b0), .q_a(sc_op_q),
        .clock_b(clk),
        .address_b(key_wr ? {3'd0, ioctl_addr[11:0]} : sc_off[14:0]),
        .data_b(ioctl_data),
        // bit 15 must gate the write, or 0x18000+ aliases onto 0x0000
        .wren_b(key_wr || (sc_wr && sc_is_op && !sc_off[15])), .q_b()
    );

    wire [7:0] sc_dec;

    UPLFramebuffer_MC8123 mc8123_dec
    (
        .val   (sc_data_q),
        .key   (sc_op_q),
        .opcode(audiocpu_m1),
        .dec   (sc_dec)
    );

    assign audiocpu_data = mc8123 ? (audiocpu_addr[15] ? sc_data_q : sc_dec)
                         : (use_opcodes && audiocpu_m1 && !audiocpu_addr[15])
                           ? sc_op_q : sc_data_q;

    wire [5:0] req = {pcm_req, tile3_req, tile2_req, tile1_req, spr_req, char_req};

    reg  [2:0] rr    = 3'd0;
    reg  [2:0] cur   = 3'd0;
    reg  [5:0] ack_r = 6'd0;
    reg  [7:0] rd_q  = 8'd0;

    wire [5:0] req_eff = req & ~ack_r;

    reg [2:0] pick;
    reg       pick_v;
    reg [2:0] scan;
    integer   k;
    always_comb begin
        pick   = 3'd0;
        pick_v = 1'b0;
        scan   = rr;
        for (k = 0; k < 6; k = k + 1) begin
            if (!pick_v && req_eff[scan]) begin
                pick   = scan;
                pick_v = 1'b1;
            end
            scan = (scan == 3'd5) ? 3'd0 : (scan + 3'd1);
        end

        if (req_eff[3'd0]) begin
            pick   = 3'd0;
            pick_v = 1'b1;
        end
    end

    wire gfx_scr = (set_id <= 8'h08);

    wire [14:0] char_sa  = gfx_scr ? {char_addr[14],     char_addr[0],  char_addr[13:1]}   : char_addr;
    wire [17:0] spr_sa   = gfx_scr ? {spr_addr[17:15],   spr_addr[0],   spr_addr[14:1]}    : spr_addr;
    wire [18:0] tile1_sa = gfx_scr ? {tile1_addr[18:15], tile1_addr[0], tile1_addr[14:1]}  : tile1_addr;

    reg [23:0] cli_byte;
    always_comb begin
        case (pick)
            3'd0: cli_byte = SDR_CHAR + {9'd0,  char_sa};
            3'd1: cli_byte = SDR_SPR  + {6'd0,  spr_sa};
            3'd2: cli_byte = SDR_TIL1 + {5'd0,  tile1_sa};
            3'd3: cli_byte = SDR_TIL2 + {5'd0,  tile2_addr};
            3'd4: cli_byte = SDR_TIL3 + {5'd0,  tile3_addr};
            default: cli_byte = SDR_PCM + {8'd0, pcm_addr};
        endcase
    end

    localparam CACHE_EN = 1'b1;

    reg [22:0] c_tag [0:5][0:1];
    reg [15:0] c_dat [0:5][0:1];
    reg  [1:0] c_vld [0:5];
    reg        c_lru [0:5];
    integer    ci;

    wire [22:0] pick_wa = cli_byte[23:1];
    wire c_h0  = CACHE_EN && c_vld[pick][0] && (c_tag[pick][0] == pick_wa);
    wire c_h1  = CACHE_EN && c_vld[pick][1] && (c_tag[pick][1] == pick_wa);
    wire c_hit = pick_v && (c_h0 || c_h1);
    wire [15:0] c_word = c_h0 ? c_dat[pick][0] : c_dat[pick][1];

    reg  [26:1] sd_addr;
    reg  [15:0] sd_din;
    reg   [1:0] sd_bs;
    reg         sd_rd, sd_wr, sd_refresh, sd_busy, sd_was_rd, sd_lsb;
    reg         sd_old_ready;
    reg   [8:0] sd_refresh_cnt;

    reg         wr_pend;
    reg  [23:0] wr_addr;
    reg   [7:0] wr_data;

    reg         rd_pend = 1'b0;
    reg   [1:0] rd_cnt  = 2'd0;
    reg   [2:0] rd_cur  = 3'd0;
    reg         rd_lsbp = 1'b0;

    wire        sd_ready;
    wire [15:0] sd_dout;

    localparam [1:0] RD_EARLY = 2'd0, RD_NORMAL = 2'd1,
                     RD_LATE  = 2'd2, RD_LATER  = 2'd3;

    reg [15:0] sd_dout_d1;
    always_ff @(posedge clk) sd_dout_d1 <= sd_dout;

    wire [23:0] dl_a = dl_base + ioctl_addr[23:0];
    wire        dl_byte = ioctl_wr && in_sdram;

    reg [63:0] dl_blk;
    reg [22:0] blk_wa;
    reg        blk_rdy;
    always_ff @(posedge clk) begin
        if (dl_byte) dl_blk <= {dl_blk[55:0], ioctl_data};
        if (dl_byte && (dl_a[2:0] == 3'd7)) blk_wa <= {dl_a[23:3], 2'b00};
        blk_rdy <= dl_byte && (dl_a[2:0] == 3'd7);
    end

    wire [15:0] blk_w0 = {dl_blk[55:48], dl_blk[63:56]};
    wire [15:0] blk_w1 = {dl_blk[39:32], dl_blk[47:40]};
    wire [15:0] blk_w2 = {dl_blk[23:16], dl_blk[31:24]};
    wire [15:0] blk_w3 = {dl_blk[ 7: 0], dl_blk[15: 8]};
    wire blk_distinct = (blk_w0 != blk_w1) && (blk_w0 != blk_w2) && (blk_w0 != blk_w3)
                     && (blk_w1 != blk_w2) && (blk_w1 != blk_w3) && (blk_w2 != blk_w3);

    reg [22:0] ref_wa;
    reg [15:0] ref_w [0:3];
    reg        ref_vld;
    always_ff @(posedge clk) begin
        if (por_reset) ref_vld <= 1'b0;
        else if (blk_rdy && !ref_vld && blk_distinct) begin
            ref_wa   <= blk_wa;
            ref_w[0] <= blk_w0; ref_w[1] <= blk_w1;
            ref_w[2] <= blk_w2; ref_w[3] <= blk_w3;
            ref_vld  <= 1'b1;
        end
    end

    reg         probing, sd_probe, det_ok, dl_d, prb_req;
    reg   [1:0] prb_dly;
    reg   [1:0] prb_ph, rd_det;
    reg   [3:0] prb_ok;
    reg  [15:0] prb_wd, prb_e, prb_n, prb_l;
    reg  [15:0] prb_to;

    wire        cal_busy, cal_rd_go;
    wire [14:0] cal_rd_word;
    reg         sd_cal;
    wire        cal_take = !sd_busy && !wr_pend && cal_rd_go && !rd_pend;
    wire        cal_cpl  = sd_busy && sd_ready && !sd_rd && !sd_wr && sd_was_rd && sd_cal && !sd_probe;

    sdram_phase_cal #(.POS(7'd80), .LATCH_MASK(4'hF), .QUIET_BITS(21)) phase_cal
    (
        .clk(clk), .por_reset(por_reset),
        .ref_clr(dl_byte && (ioctl_index == IDX_CHAR) && (ioctl_addr[23:0] == 24'd0)),
        .ref_wd(dl_byte && (ioctl_index == IDX_CHAR) && ioctl_addr[0]),
        .ref_w({ioctl_data, dl_blk[7:0]}),
        .ph_auto(ph_auto), .ld_busy(ioctl_download | ld_hold), .dl_active(ioctl_download),
        .blocked(probing),
        .ph_req_val(ph_req_val), .ph_req_tgl(ph_req_tgl), .ph_ack(recal),
        .rd_go(cal_rd_go), .rd_word(cal_rd_word), .rd_take(cal_take), .rd_cpl(cal_cpl),
        .sd_dout(sd_dout), .sd_dout_d1(sd_dout_d1),
        .busy(cal_busy), .hold(cal_hold)
    );

    wire [3:0] prb_ok_nxt = {prb_ok[3] && (sd_dout == prb_wd),
                             prb_ok[2] && (prb_l   == prb_wd),
                             prb_ok[1] && (prb_n   == prb_wd),
                             prb_ok[0] && (prb_e   == prb_wd)};

    wire [1:0] rd_sel = (rd_auto && det_ok) ? rd_det : rd_mode;

    wire [15:0] sd_dout_sel = (rd_sel == RD_EARLY) ? sd_dout_d1 : sd_dout;

    assign ioctl_wait = sd_busy || (ioctl_wr && in_sdram) || cal_busy;

    wire sd_complete = sd_busy && sd_ready && !sd_rd && !sd_wr;
    wire comp_ack    = (sd_complete && sd_was_rd && (rd_sel < RD_LATE)) || rd_pend;
    wire serve_hit   = c_hit && !comp_ack && !ack_r[pick] && !ioctl_download && !probing && !cal_busy;

    always_ff @(posedge clk) begin
        if (por_reset) begin
            sd_rd <= 0; sd_wr <= 0; sd_refresh <= 0; sd_busy <= 0; sd_was_rd <= 0;
            sd_refresh_cnt <= 9'd0; sd_old_ready <= 1'b1; wr_pend <= 1'b0; ack_r <= 6'd0;
            rd_pend <= 1'b0;
            probing <= 1'b0; sd_probe <= 1'b0; prb_dly <= 2'd0; det_ok <= 1'b0;
            rd_cnt <= 2'd0; dl_d <= 1'b0; prb_req <= 1'b0;
            sd_cal <= 1'b0;
            rr <= 3'd0;
            for (ci = 0; ci < 6; ci = ci + 1) begin
                c_vld[ci] <= 2'd0;
                c_lru[ci] <= 1'b0;
            end
        end else begin
            dl_d <= ioctl_download;
            if ((dl_d && !ioctl_download) || recal) prb_req <= 1'b1;
            else if (prb_req && ref_vld && !probing && !ioctl_download && !cal_busy) begin
                prb_req <= 1'b0;
                probing <= 1'b1; prb_ph <= 2'd0; prb_ok <= 4'hF; prb_to <= 16'd0;
            end
            if (probing) begin
                prb_to <= prb_to + 16'd1;
                if (&prb_to) begin
                    probing <= 1'b0; sd_probe <= 1'b0; prb_dly <= 2'd0; det_ok <= 1'b0;
                end
            end

            if (sd_refresh_cnt == 9'd467) begin
                sd_refresh_cnt <= 9'd0;
                sd_refresh     <= ~sd_refresh;
            end else begin
                sd_refresh_cnt <= sd_refresh_cnt + 1'b1;
            end
            sd_old_ready   <= sd_ready;
            ack_r          <= 6'd0;

            if (ioctl_wr && in_sdram) begin
                wr_pend <= 1'b1;
                wr_addr <= dl_base + ioctl_addr[23:0];
                wr_data <= ioctl_data;
            end

            if (sd_old_ready && !sd_ready) begin
                sd_rd <= 0;
                sd_wr <= 0;
            end

            if (sd_busy) begin
                if (sd_ready && !sd_rd && !sd_wr) begin
                    if (sd_was_rd) begin
                        if (sd_probe) begin
                            prb_e <= sd_dout_d1; prb_n <= sd_dout;
                            prb_dly <= 2'd2; sd_probe <= 1'b0;
                        end else if (sd_cal) begin
                            sd_cal <= 1'b0;
                        end else if (rd_sel >= RD_LATE) begin
                            rd_pend <= 1'b1; rd_cur <= cur; rd_lsbp <= sd_lsb;
                            rd_cnt  <= (rd_sel == RD_LATER) ? 2'd2 : 2'd1;
                        end else begin
                            rd_q       <= sd_lsb ? sd_dout_sel[15:8] : sd_dout_sel[7:0];
                            ack_r[cur] <= 1'b1;
                            c_tag[cur][c_lru[cur]] <= sd_addr[23:1];
                            c_dat[cur][c_lru[cur]] <= sd_dout_sel;
                            c_vld[cur][c_lru[cur]] <= 1'b1;
                            c_lru[cur]             <= ~c_lru[cur];
                        end
                    end
                    sd_busy <= 0;
                end
            end else begin
                if (wr_pend) begin
                    sd_addr  <= {3'd0, wr_addr[23:1]};
                    sd_din   <= {wr_data, wr_data};
                    sd_bs    <= wr_addr[0] ? 2'b10 : 2'b01;
                    sd_wr    <= 1; sd_busy <= 1; sd_was_rd <= 0;
                    // a bare wr_pend <= 0 here would win as the last assignment and drop that byte
                    wr_pend  <= (ioctl_wr && in_sdram);
                end else if (cal_rd_go && !rd_pend) begin
                    sd_addr   <= {11'd0, cal_rd_word};
                    sd_rd     <= 1; sd_busy <= 1; sd_was_rd <= 1; sd_cal <= 1;
                end else if (probing && (prb_dly == 2'd0)) begin
                    sd_addr   <= {3'd0, ref_wa + {21'd0, prb_ph}};
                    prb_wd    <= ref_w[prb_ph];
                    sd_rd     <= 1; sd_busy <= 1; sd_was_rd <= 1; sd_probe <= 1;
                end else if (pick_v && !ioctl_download && !probing && !cal_busy && !rd_pend && !ack_r[pick] && !c_hit) begin
                    sd_addr   <= {3'd0, cli_byte[23:1]};
                    sd_lsb    <= cli_byte[0];
                    cur       <= pick;
                    rr        <= (pick == 3'd5) ? 3'd0 : (pick + 3'd1);
                    sd_rd     <= 1; sd_busy <= 1; sd_was_rd <= 1;
                end
            end

            if (rd_pend && (rd_cnt > 2'd1)) rd_cnt <= rd_cnt - 2'd1;
            else if (rd_pend) begin
                rd_q          <= rd_lsbp ? sd_dout[15:8] : sd_dout[7:0];
                ack_r[rd_cur] <= 1'b1;
                rd_pend       <= 1'b0;
                c_tag[rd_cur][c_lru[rd_cur]] <= sd_addr[23:1];
                c_dat[rd_cur][c_lru[rd_cur]] <= sd_dout;
                c_vld[rd_cur][c_lru[rd_cur]] <= 1'b1;
                c_lru[rd_cur]                <= ~c_lru[rd_cur];
            end

            if (prb_dly == 2'd2) begin
                prb_l   <= sd_dout;
                prb_dly <= 2'd1;
            end else if (prb_dly == 2'd1) begin
                prb_ok  <= prb_ok_nxt;
                prb_dly <= 2'd0;
                if (prb_ph == 2'd3) begin
                    probing <= 1'b0;
                    if      (prb_ok_nxt[1]) begin rd_det <= RD_NORMAL; det_ok <= 1'b1; end
                    else if (prb_ok_nxt[0]) begin rd_det <= RD_EARLY;  det_ok <= 1'b1; end
                    else if (prb_ok_nxt[2]) begin rd_det <= RD_LATE;   det_ok <= 1'b1; end
                    else if (prb_ok_nxt[3]) begin rd_det <= RD_LATER;  det_ok <= 1'b1; end
                    else                          det_ok <= 1'b0;
                end else prb_ph <= prb_ph + 2'd1;
            end

            if (serve_hit) begin
                rd_q        <= cli_byte[0] ? c_word[15:8] : c_word[7:0];
                ack_r[pick] <= 1'b1;
                rr          <= (pick == 3'd5) ? 3'd0 : (pick + 3'd1);
            end

            if (ioctl_download || recal)
                for (ci = 0; ci < 6; ci = ci + 1) c_vld[ci] <= 2'd0;
        end
    end

    assign {pcm_ack, tile3_ack, tile2_ack, tile1_ack, spr_ack, char_ack} = ack_r;
    assign char_data  = rd_q;
    assign spr_data   = rd_q;
    assign tile1_data = rd_q;
    assign tile2_data = rd_q;
    assign tile3_data = rd_q;
    assign pcm_data   = rd_q;

    sdram #(.sdram_startup_cycles(14'd6060), .cycles_per_refresh(14'd468)) sdram_i
    (
        .init       (por_reset),
        .clk        (clk),
        .SDRAM_DQ   (SDRAM_DQ),   .SDRAM_A   (SDRAM_A),   .SDRAM_DQML(SDRAM_DQML),
        .SDRAM_DQMH (SDRAM_DQMH), .SDRAM_BA  (SDRAM_BA),  .SDRAM_nCS (SDRAM_nCS),
        .SDRAM_nWE  (SDRAM_nWE),  .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
        .SDRAM_CKE  (SDRAM_CKE),  .SDRAM_CLK (SDRAM_CLK), .SDRAM_EN  (1'b1),
        .sel        (1'b1),
        .addr       (sd_addr),    .dout      (sd_dout),   .din       (sd_din),
        .wr         (sd_wr),      .bs        (sd_bs),     .rd        (sd_rd),
        .ready      (sd_ready),   .refresh   (sd_refresh),
        .cpsel(1'b0), .cpaddr(26'd0), .cpdin(16'd0), .cprd(), .cpreq(1'b0), .cpbusy()
    );

endmodule
