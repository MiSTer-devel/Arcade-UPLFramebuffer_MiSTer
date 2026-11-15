//  Based on MAME ninjakd2.cpp, xxmissio.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, Uki, BSD-3-Clause)

module UPLFramebuffer_BGLAYER #(
    parameter       HW      = 9,
    parameter [9:0] H_TOTAL = 10'd384,
    parameter [8:0] V_TOTAL = 9'd262,
    parameter [9:0] W_LAST  = 10'd255,
    parameter       XX      = 0
)
(
    input               clk,
    input               cen_pix,
    input               reset,
    // the raster-aligned fetch window and the untruncated 9-bit position are load-bearing: do not simplify
    input               fetch_en,
    // en gates fetching, not just output: a disabled layer must not spend SDRAM slots
    input               en,

    input  [HW-1:0]     h_cnt,
    input         [8:0] v_cnt,
    input               flip_screen,

    input               gfx_robokid,
    input               is_omegaf,
    input               bg_mnight,

    input        [15:0] scrollx,
    input        [15:0] scrolly,

    output       [12:0] vram_addr,
    input         [7:0] vram_data,

    output       [18:0] rom_addr,
    output              rom_req,
    input               rom_ack,
    input         [7:0] rom_data,

    output        [3:0] color,
    output        [3:0] pix
);

    wire [HW-1:0] fh = (h_cnt >= H_TOTAL - 10'd32) ? (h_cnt - (H_TOTAL - 10'd32)) : (h_cnt + 10'd32);
    wire    [8:0] fv = (h_cnt >= H_TOTAL - 10'd32) ? ((v_cnt == V_TOTAL - 1'd1) ? 9'd0 : v_cnt + 1'd1) : v_cnt;

    wire [HW-1:0] fsx = flip_screen ? (W_LAST - fh) : fh;
    wire [8:0] fsy = flip_screen ? (9'd255 - fv) : fv;

    wire [10:0] fmx = {{(11-HW){1'b0}}, fsx} + scrollx[10:0];
    wire  [8:0] fmy = fsy + scrolly[8:0];

    wire [HW-1:0] h_p1 = (h_cnt == H_TOTAL - 1'd1) ? {HW{1'b0}} : h_cnt + 1'd1;
    wire [HW-1:0] dsx  = flip_screen ? (W_LAST - h_cnt) : h_cnt;
    wire [HW-1:0] dsx1 = flip_screen ? (W_LAST - h_p1)  : h_p1;
    wire [10:0]   dmx  = {{(11-HW){1'b0}}, dsx}  + scrollx[10:0];
    wire [10:0]   dmx1 = {{(11-HW){1'b0}}, dsx1} + scrollx[10:0];

    wire [6:0] bg_fcol  = is_omegaf ? fmx[10:4]  : {2'b00, fmx[8:4]};
    wire [6:0] bg_dcol  = is_omegaf ? dmx[10:4]  : {2'b00, dmx[8:4]};
    wire [6:0] bg_dcol1 = is_omegaf ? dmx1[10:4] : {2'b00, dmx1[8:4]};
    wire [4:0] bg_frow  = XX ? fmy[7:3] : fmy[8:4];

    wire [11:0] bg_scan = gfx_robokid ? {bg_fcol[6:4], bg_frow, bg_fcol[3:0]}
                                      : {2'b00, bg_frow, bg_fcol[4:0]};

    wire bg_group_end = (h_cnt[3:0] == 4'd15);

    reg  [3:0] bst = 4'd0;
    reg  [2:0] bj  = 3'd0;
    reg  [7:0] blo = 8'd0, bhi = 8'd0;

    reg [11:0] bfetch_tidx = 12'd0;
    reg  [3:0] bfetch_my   = 4'd0;

    reg [63:0] bg_new_rowbits = 64'd0;  reg [3:0] bg_new_color = 4'd0;  reg bg_new_flipx = 1'b0;
    reg [63:0] bg_nxt_rowbits = 64'd0;  reg [3:0] bg_nxt_color = 4'd0;  reg bg_nxt_flipx = 1'b0;
    reg [63:0] bg_cur_rowbits = 64'd0;  reg [3:0] bg_cur_color = 4'd0;  reg bg_cur_flipx = 1'b0;
    reg  [6:0] bg_cur_col = 7'd0;

    reg [12:0] bg_addr_r;
    reg [18:0] rom_addr_r;
    reg        rom_req_r;

    assign vram_addr = bg_addr_r;
    assign rom_addr  = rom_addr_r;
    assign rom_req   = rom_req_r;

    wire [11:0] bg_tile  = gfx_robokid ? {bhi[4], bhi[5], bhi[7:6], blo}
                                      : {1'b0, bg_mnight & bhi[4], bhi[7:6], blo};
    wire        bg_flipy = (XX | gfx_robokid) ? 1'b0 : bhi[5];
    wire  [3:0] bg_ty    = bg_flipy ? ~bfetch_my : bfetch_my;

    wire bg_sub_hi = gfx_robokid ? bj[2]    : bg_ty[3];
    wire bg_sub_lo = gfx_robokid ? bg_ty[3] : bj[2];
    wire [18:0] bg_rom_addr = XX ? {3'b000, bg_tile[9:0], bg_ty[2:0], bj[2:0]}
                                 : {bg_tile, bg_sub_hi, bg_sub_lo, bg_ty[2:0], bj[1:0]};

    always_ff @(posedge clk) begin
        if (reset || !fetch_en || !en) begin
            bst <= 4'd0; rom_req_r <= 1'b0; bj <= 3'd0;
            if (reset) bg_cur_col <= 7'd0;
        end else begin
            if (cen_pix && bg_group_end) begin
                bg_cur_rowbits <= bg_nxt_rowbits;
                bg_cur_color   <= bg_nxt_color;
                bg_cur_flipx   <= bg_nxt_flipx;
                bg_cur_col     <= bg_dcol1;
                bg_nxt_rowbits <= bg_new_rowbits;
                bg_nxt_color   <= bg_new_color;
                bg_nxt_flipx   <= bg_new_flipx;
                bst <= 4'd0;
                bj  <= 3'd0;
            end else begin
                case (bst)
                    4'd0: begin
                        bfetch_tidx <= bg_scan;
                        bfetch_my   <= XX ? {1'b0, fmy[2:0]} : fmy[3:0];
                        bg_addr_r   <= XX ? {2'b00, 1'b0, bg_scan[9:0]} : {bg_scan, 1'b0};
                        bst         <= 4'd1;
                    end
                    4'd1: bst <= 4'd2;
                    4'd2: begin
                        blo <= vram_data;
                        bg_addr_r <= XX ? {2'b00, 1'b1, bfetch_tidx[9:0]} : {bfetch_tidx, 1'b1};
                        bst <= 4'd3;
                    end
                    4'd3: bst <= 4'd4;
                    4'd4: begin
                        bhi          <= vram_data;
                        bg_new_color <= vram_data[3:0];
                        bg_new_flipx <= (XX | gfx_robokid | bg_mnight) ? 1'b0 : vram_data[4];
                        bst          <= 4'd5;
                    end
                    4'd5: begin rom_addr_r <= bg_rom_addr; rom_req_r <= 1'b1; bst <= 4'd6; end
                    4'd6: if (rom_ack) begin
                              bg_new_rowbits <= {bg_new_rowbits[55:0], rom_data};
                              rom_req_r <= 1'b0;
                              if (bj == 3'd7) bst <= 4'd7;
                              else begin bj <= bj + 3'd1; bst <= 4'd5; end
                          end
                    default: ;
                endcase
            end
        end
    end

    wire        bg_use_nxt   = (bg_dcol != bg_cur_col);
    wire [63:0] bg_sel_bits  = bg_use_nxt ? bg_nxt_rowbits : bg_cur_rowbits;
    wire        bg_sel_flipx = bg_use_nxt ? bg_nxt_flipx   : bg_cur_flipx;

    wire [3:0] bg_tx  = bg_sel_flipx ? ~dmx[3:0] : dmx[3:0];
    wire [5:0] bshift = {2'd0, ~bg_tx} << 2;

    assign color = bg_use_nxt ? bg_nxt_color : bg_cur_color;
    assign pix   = (bg_sel_bits >> bshift) & 64'hF;

endmodule
