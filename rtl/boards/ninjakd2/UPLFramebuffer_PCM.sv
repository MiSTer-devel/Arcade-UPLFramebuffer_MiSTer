//  Based on MAME ninjakd2.cpp (Roberto Ventura, Leandro Dardini, Yochizo, Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module UPLFramebuffer_PCM
(
    input                clk,
    input                reset,
    input                pause,

    input          [7:0] cmd,
    input                cmd_wr,

    output reg    [15:0] rom_addr,
    output reg           rom_req,
    input                rom_ack,
    input          [7:0] rom_data,

    output signed [15:0] sample_out
);

    localparam [11:0] RATE_TOP = 12'd3680;

    reg [11:0] rate_cnt = 12'd0;
    reg        playing  = 1'b0;
    reg        busy     = 1'b0;
    reg [15:0] addr     = 16'd0;
    reg  [7:0] cur      = 8'd0;

    wire rate_tick = (rate_cnt == RATE_TOP);

    always_ff @(posedge clk) begin
        if (reset) begin
            rate_cnt <= 12'd0;
            playing  <= 1'b0;
            busy     <= 1'b0;
            rom_req  <= 1'b0;
            cur      <= 8'd0;
            addr     <= 16'd0;
        end else begin
            rate_cnt <= rate_tick ? 12'd0 : rate_cnt + 12'd1;

            if (cmd_wr) begin
                addr    <= {cmd, 8'd0};
                playing <= 1'b1;
                busy    <= 1'b0;
                rom_req <= 1'b0;
            end else if (busy) begin
                if (rom_ack) begin
                    rom_req <= 1'b0;
                    busy    <= 1'b0;
                    if (rom_data == 8'd0) begin
                        playing <= 1'b0;
                        cur     <= 8'd0;
                    end else begin
                        cur  <= rom_data;
                        addr <= addr + 16'd1;
                        if (&addr) playing <= 1'b0;
                    end
                end
            end else if (playing && rate_tick && !pause) begin
                rom_addr <= addr;
                rom_req  <= 1'b1;
                busy     <= 1'b1;
            end
        end
    end

    wire signed [15:0] centred = $signed({1'b0, cur, 7'd0}) - 16'sd16384;

    assign sample_out = (pause || !playing) ? 16'sd0 : centred;

endmodule
