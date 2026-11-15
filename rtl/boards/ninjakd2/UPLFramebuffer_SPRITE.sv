//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)

module UPLFramebuffer_SPRITE
(
    input               clk,
    input               reset,

    input               flip_screen,
    input               gfx_robokid,
    input               is_omegaf,
    input               overdraw,
    input               draw_window,

    output       [12:0] spr_ram_addr,
    input         [7:0] spr_ram_data,

    output       [17:0] spr_addr,
    output              spr_req,
    input               spr_ack,
    input         [7:0] spr_data,

    input        [15:0] fb_raddr,
    output        [7:0] fb_rdata,

    output              busy,

    output ram_pool_pkg::pram_i_t [3:0] fb_i,
    input  ram_pool_pkg::pram_o_t [3:0] fb_o
);

    localparam [12:0] SPR_BASE = 13'h1A00;

    reg  [13:0] fb_waddr;
    reg  [31:0] fb_wdata;
    reg   [3:0] fb_wbe;
    reg         fb_we;

    reg  [13:0] erase_addr;
    wire [13:0] fb_baddr = draw_window ? erase_addr : fb_raddr[15:2];
    wire [31:0] fb_bq;

    wire st0 = is_omegaf ? 1'b1 : gfx_robokid ? (fb_bq[ 7: 4] < 4'hE) : (fb_bq[ 7: 4] == 4'hF);
    wire st1 = is_omegaf ? 1'b1 : gfx_robokid ? (fb_bq[15:12] < 4'hE) : (fb_bq[15:12] == 4'hF);
    wire st2 = is_omegaf ? 1'b1 : gfx_robokid ? (fb_bq[23:20] < 4'hE) : (fb_bq[23:20] == 4'hF);
    wire st3 = is_omegaf ? 1'b1 : gfx_robokid ? (fb_bq[31:28] < 4'hE) : (fb_bq[31:28] == 4'hF);

    // the byte select must lag the address by the BRAM's one clock
    reg [1:0] fb_rsel;
    always_ff @(posedge clk) fb_rsel <= fb_raddr[1:0];

    assign fb_rdata = (fb_rsel == 2'd0) ? fb_bq[7:0]
                    : (fb_rsel == 2'd1) ? fb_bq[15:8]
                    : (fb_rsel == 2'd2) ? fb_bq[23:16]
                                        : fb_bq[31:24];

    genvar fl;
    generate
        for (fl = 0; fl < 4; fl = fl + 1) begin : fb_lane
            assign fb_i[fl].a_addr = {2'b0, fb_waddr};
            assign fb_i[fl].a_we   = fb_we & fb_wbe[fl];
            assign fb_i[fl].a_d    = fb_wdata[fl*8 +: 8];
            assign fb_i[fl].b_addr = {2'b0, fb_baddr};
            assign fb_i[fl].b_we   = 1'b0;
            assign fb_i[fl].b_d    = 8'd0;
        end
    endgenerate
    assign fb_bq = {fb_o[3].b_q, fb_o[2].b_q, fb_o[1].b_q, fb_o[0].b_q};

    reg  [6:0] spr_idx;
    reg  [6:0] drawn;
    reg  [7:0] b_sy, b_sxlo, b_ctrl, b_code, b_col;

    wire        e_enable = b_ctrl[1];
    wire        e_big    = b_ctrl[2];
    wire        e_flipx  = b_ctrl[4];
    wire        e_flipy  = b_ctrl[5];
    wire  [3:0] e_color  = b_col[3:0];
    wire [10:0] e_code   = {b_ctrl[3], b_ctrl[7], b_ctrl[6], b_code};
    wire signed [9:0] e_sx = {2'b00, b_sxlo} - {b_ctrl[0], 9'd0};
    wire signed [9:0] e_sy = {2'b00, b_sy};

    wire signed [9:0] big_off = e_big ? 10'sd16 : 10'sd0;
    wire signed [9:0] f_sx = flip_screen ? (10'sd240 - big_off - e_sx) : e_sx;
    wire signed [9:0] f_sy = flip_screen ? (10'sd240 - big_off - e_sy) : e_sy;
    wire        f_flipx = e_flipx ^ flip_screen;
    wire        f_flipy = e_flipy ^ flip_screen;

    reg  [1:0] qx, qy;
    wire [1:0] flip_xor = gfx_robokid ? {f_flipx, f_flipy} : {f_flipy, f_flipx};
    wire [1:0] quad_xor = gfx_robokid ? {qx[0], qy[0]}     : {qy[0], qx[0]};
    wire [10:0] base_code = e_big ? {e_code[10:2], 2'b00} ^ {9'd0, flip_xor}
                                  :  e_code;
    wire [10:0] cur_code  = base_code ^ {9'd0, quad_xor};

    wire signed [9:0] cur_x0 = f_sx + (qx[0] ? 10'sd16 : 10'sd0);
    wire signed [9:0] cur_y0 = f_sy + (qy[0] ? 10'sd16 : 10'sd0);

    reg  [3:0] row;
    reg  [2:0] rj;
    reg [63:0] rowbits;
    reg  [3:0] col;

    wire [3:0] ty = f_flipy ? ~row : row;
    wire [3:0] tx = f_flipx ? ~col : col;

    reg  [17:0] spr_addr_r;
    reg         spr_req_r;
    assign spr_addr = spr_addr_r;
    assign spr_req  = spr_req_r;

    wire sub_hi = gfx_robokid ? rj[2] : ty[3];
    wire sub_lo = gfx_robokid ? ty[3] : rj[2];
    wire [17:0] rom_addr = {cur_code, sub_hi, sub_lo, ty[2:0], rj[1:0]};

    wire [5:0] pshift = {2'd0, ~tx} << 2;
    wire [3:0] pen    = (rowbits >> pshift) & 64'hF;

    wire signed [9:0] px = cur_x0 + {6'd0, col};
    wire signed [9:0] py = cur_y0 + {6'd0, row};
    wire in_frame = (px >= 0) && (px <= 10'sd255) && (py >= 0) && (py <= 10'sd255);

    localparam S_IDLE = 4'd0, S_ERASE = 4'd1, S_REC   = 4'd2, S_DECIDE = 4'd3,
               S_ROWREQ= 4'd4, S_ROWACK= 4'd5, S_WRITE = 4'd6, S_NEXTROW= 4'd7,
               S_NEXTQ = 4'd8, S_NEXTSP= 4'd9, S_DONE  = 4'd10;

    reg [3:0] st;
    reg [2:0] rec;
    reg       rec_ph;
    reg       dw_d;

    reg [13:0] er_prev;
    reg        er_pv;

    assign busy = (st != S_IDLE) && (st != S_DONE);

    assign spr_ram_addr = SPR_BASE + {2'd0, spr_idx, 4'd0} + 13'd11 + {10'd0, rec};

    always_ff @(posedge clk) begin
        fb_we <= 1'b0;
        dw_d  <= draw_window;

        if (reset) begin
            st <= S_IDLE; spr_req_r <= 1'b0; drawn <= 7'd0; spr_idx <= 7'd0; er_pv <= 1'b0;
        end else begin
            case (st)
                S_IDLE: if (draw_window && !dw_d) begin
                            erase_addr <= 14'd0;
                            er_pv      <= 1'b0;
                            st         <= S_ERASE;
                        end

                S_ERASE: begin
                    er_prev <= erase_addr;
                    er_pv   <= 1'b1;
                    if (er_pv) begin
                        fb_waddr <= er_prev;
                        fb_wdata <= 32'h0F0F0F0F;
                        fb_wbe   <= overdraw ? {st3, st2, st1, st0} : 4'b1111;
                        fb_we    <= overdraw ? |{st3, st2, st1, st0} : 1'b1;
                    end
                    if (er_pv && (er_prev == 14'h3FFF)) begin
                        spr_idx <= 7'd0; drawn <= 7'd0; rec <= 3'd0; rec_ph <= 1'b0;
                        st <= S_REC;
                    end else begin
                        erase_addr <= erase_addr + 14'd1;
                    end
                end

                S_REC: begin
                    if (!rec_ph) rec_ph <= 1'b1;
                    else begin
                        case (rec)
                            3'd0: b_sy   <= spr_ram_data;
                            3'd1: b_sxlo <= spr_ram_data;
                            3'd2: b_ctrl <= spr_ram_data;
                            3'd3: b_code <= spr_ram_data;
                            default: b_col <= spr_ram_data;
                        endcase
                        rec_ph <= 1'b0;
                        if (rec == 3'd4) st  <= S_DECIDE;
                        else             rec <= rec + 3'd1;
                    end
                end

                S_DECIDE: begin
                    qx <= 2'd0; qy <= 2'd0; row <= 4'd0; rj <= 3'd0;
                    if (!e_enable) begin
                        drawn <= drawn + 7'd1;
                        st <= (drawn == 7'd95) ? S_DONE : S_NEXTSP;
                    end else st <= S_ROWREQ;
                end

                S_ROWREQ: begin spr_addr_r <= rom_addr; spr_req_r <= 1'b1; st <= S_ROWACK; end
                S_ROWACK: if (spr_ack) begin
                              rowbits   <= {rowbits[55:0], spr_data};
                              spr_req_r <= 1'b0;
                              if (rj == 3'd7) begin col <= 4'd0; st <= S_WRITE; end
                              else begin rj <= rj + 3'd1; st <= S_ROWREQ; end
                          end

                S_WRITE: begin
                    if (in_frame && (pen != 4'hF)) begin
                        fb_waddr <= {py[7:0], px[7:2]};
                        fb_wdata <= {4{{e_color, pen}}};
                        fb_wbe   <= 4'b0001 << px[1:0];
                        fb_we    <= 1'b1;
                    end
                    if (col == 4'd15) st  <= S_NEXTROW;
                    else              col <= col + 4'd1;
                end

                S_NEXTROW: begin
                    rj <= 3'd0;
                    if (row == 4'd15) st <= S_NEXTQ;
                    else begin row <= row + 4'd1; st <= S_ROWREQ; end
                end

                S_NEXTQ: begin
                    row <= 4'd0; rj <= 3'd0;
                    drawn <= drawn + 7'd1;
                    if (drawn == 7'd95)                   st <= S_DONE;
                    else if (!e_big)                      st <= S_NEXTSP;
                    else if (qx == 2'd0)                  begin qx <= 2'd1; st <= S_ROWREQ; end
                    else if (qy == 2'd0)                  begin qx <= 2'd0; qy <= 2'd1; st <= S_ROWREQ; end
                    else                                  st <= S_NEXTSP;
                end

                S_NEXTSP: if (spr_idx == 7'd95) st <= S_DONE;
                          else begin
                              spr_idx <= spr_idx + 7'd1;
                              rec <= 3'd0; rec_ph <= 1'b0;
                              st  <= S_REC;
                          end

                S_DONE: if (!draw_window) st <= S_IDLE;

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
