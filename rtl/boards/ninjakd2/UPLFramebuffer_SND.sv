//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)

module UPLFramebuffer_SND
(
    input                clk,
    input                cen_cpu,
    input                cen_ym,
    input                reset,
    input                pause,

    input         [7:0]  sound_latch,
    input                sound_latch_wr,

    output       [15:0]  rom_addr,
    input         [7:0]  rom_data,
    output               rom_m1,

    output        [7:0]  pcm_cmd,
    output               pcm_cmd_wr,

    output signed [15:0] sound_out,

    output chip_pool_pkg::z80r_i_t         z80_i,
    input  chip_pool_pkg::z80_o_t          z80_o,
    output chip_pool_pkg::ym2203_i_t [1:0] ym_i,
    input  chip_pool_pkg::ym2203_o_t [1:0] ym_o,
    output ram_pool_pkg::pram_i_t          ram_i,
    input  ram_pool_pkg::pram_o_t          ram_o
);

    wire [15:0] A        = z80_o.a;
    wire  [7:0] cpu_dout = z80_o.dout;
    wire        mreq_n   = z80_o.mreq_n;
    wire        iorq_n   = z80_o.iorq_n;
    wire        rd_n     = z80_o.rd_n;
    wire        wr_n     = z80_o.wr_n;
    wire        m1_n     = z80_o.m1_n;

    wire mem_wr = ~mreq_n & ~wr_n;
    wire io_wr  = ~iorq_n & ~wr_n & m1_n;
    wire io_rd  = ~iorq_n & ~rd_n & m1_n;

    wire cs_rom   = (A[15:14] != 2'b11);
    wire cs_ram   = (A[15:11] == 5'b11000);
    wire cs_latch = (A == 16'hE000);
    wire cs_pcm   = (A == 16'hF000);

    assign rom_addr = A;
    assign rom_m1   = ~m1_n;

    // not cleared by the sound CPU reset: a command written while it is held must survive
    reg [7:0] latch_reg = 8'd0;

    always_ff @(posedge clk) begin
        if (sound_latch_wr) latch_reg <= sound_latch;
    end

    reg [7:0] pcm_reg = 8'd0;
    reg       pcm_wr  = 1'b0;

    always_ff @(posedge clk) begin
        pcm_wr <= 1'b0;
        if (cen_cpu & mem_wr & cs_pcm) begin
            pcm_reg <= cpu_dout;
            pcm_wr  <= 1'b1;
        end
    end

    assign pcm_cmd    = pcm_reg;
    assign pcm_cmd_wr = pcm_wr;

    wire [7:0] ram_dout;

    assign ram_i.a_addr = {5'd0, A[10:0]};
    assign ram_i.a_d    = cpu_dout;
    assign ram_i.a_we   = cen_cpu & mem_wr & cs_ram;
    assign ram_i.b_addr = 16'd0;
    assign ram_i.b_d    = 8'd0;
    assign ram_i.b_we   = 1'b0;
    assign ram_dout     = ram_o.a_q;

    // jt12_mmr's register block is not cen-gated: the write strobe must be exactly one clk wide
    wire ym1_sel = io_wr & (A[7:1] == 7'b0000000);
    wire ym2_sel = io_wr & (A[7:1] == 7'b1000000);

    reg ym1_sel_d = 1'b0, ym2_sel_d = 1'b0;
    always_ff @(posedge clk) begin
        ym1_sel_d <= ym1_sel;
        ym2_sel_d <= ym2_sel;
    end

    wire ym1_wr = ym1_sel & ~ym1_sel_d & ~reset;
    wire ym2_wr = ym2_sel & ~ym2_sel_d & ~reset;

    assign ym_i[0].rst    = reset;
    assign ym_i[0].ce     = cen_ym;
    assign ym_i[0].cs_n   = ~ym1_wr;
    assign ym_i[0].wr_n   = ~ym1_wr;
    assign ym_i[0].addr   = A[0];
    assign ym_i[0].din    = cpu_dout;
    assign ym_i[0].ioa_in = 8'hFF;
    assign ym_i[0].iob_in = 8'hFF;

    assign ym_i[1].rst    = reset;
    assign ym_i[1].ce     = cen_ym;
    assign ym_i[1].cs_n   = ~ym2_wr;
    assign ym_i[1].wr_n   = ~ym2_wr;
    assign ym_i[1].addr   = A[0];
    assign ym_i[1].din    = cpu_dout;
    assign ym_i[1].ioa_in = 8'hFF;
    assign ym_i[1].iob_in = 8'hFF;

    wire  [7:0] ym1_dout  = ym_o[0].dout;
    wire  [7:0] ym2_dout  = ym_o[1].dout;
    wire        ym1_irq_n = ym_o[0].irq_n;
    wire signed [15:0] ym1_snd = ym_o[0].snd;
    wire signed [15:0] ym2_snd = ym_o[1].snd;

    wire signed [16:0] snd_sum = {ym1_snd[15], ym1_snd} + {ym2_snd[15], ym2_snd};

    assign sound_out = pause ? 16'sd0 : snd_sum[16:1];

    reg [7:0] cpu_din;

    always_comb begin
        if      (io_rd & (A[7:1] == 7'b0000000)) cpu_din = ym1_dout;
        else if (io_rd & (A[7:1] == 7'b1000000)) cpu_din = ym2_dout;
        else if (io_rd)                          cpu_din = 8'hFF;
        else if (cs_rom)                         cpu_din = rom_data;
        else if (cs_ram)                         cpu_din = ram_dout;
        else if (cs_latch)                       cpu_din = latch_reg;
        else                                     cpu_din = 8'hFF;
    end

    assign z80_i.reset_n = ~reset;
    assign z80_i.ce      = cen_cpu & ~pause;
    assign z80_i.int_n   = ym1_irq_n;
    assign z80_i.nmi_n   = 1'b1;
    assign z80_i.di      = cpu_din;

endmodule
