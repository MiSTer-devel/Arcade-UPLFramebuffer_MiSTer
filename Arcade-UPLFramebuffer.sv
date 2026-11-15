//============================================================================
//
// UPLFramebuffer for MiSTer
// Copyright (C) 2026 Rodimus
// Based on Tutankham core structure
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire CLK_60M;
wire [127:0] status;
wire        ioctl_download;
wire        pause_cpu;
wire signed [15:0] audio_l, audio_r;
assign AUDIO_L = pause_cpu ? 16'd0 : audio_l;
assign AUDIO_R = pause_cpu ? 16'd0 : audio_r;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

wire [1:0] ar = status[14:13];

wire [7:0] set_id;
wire is_xx       = (set_id == 8'h1A);
wire is_vertical = ((set_id >= 8'h0D) && (set_id <= 8'h0F)) | is_xx;

wire horz = ~is_vertical | status[12];

assign VIDEO_ARX = horz ? ((!ar) ? 12'd4 : (ar - 1'd1)) : ((!ar) ? 12'd3 : (ar - 1'd1));
assign VIDEO_ARY = horz ? ((!ar) ? 12'd3 : 12'd0) : ((!ar) ? 12'd4 : 12'd0);

`include "build_id.v"
localparam CONF_STR = {
	"UPLFRAMEBUFFER;;",
	"P1,Video Options;",
	"P1ODE,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1OFH,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1O[35:32],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[39:36],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"P2,Pause Options;",
	"P2OP,Pause when OSD is open,On,Off;",
	"P2OQ,Dim video after 10s,On,Off;",
	"-;",
	"P3,High Score Options;",
	"P3OR,Autosave Hiscores,Off,On;",
	"-;",
	"OJL,SDRAM Rd Latch,Auto,Normal,Early,Late,Later;",
	"OSV,SDRAM Clk Phase,Auto,0.0ns,1.0ns,2.1ns,3.1ns,4.2ns,5.2ns,6.3ns,7.3ns,8.3ns,9.4ns,10.4ns,11.5ns,12.5ns,13.5ns,14.6ns;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Attack,Jump,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [10:0] ps2_key;

wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire        ioctl_wait;

wire [15:0] joystick_0, joystick_1;

wire [21:0] gamma_bus;
wire        direct_video;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_60M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_wait(ioctl_wait),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire locked;

wire        CLK_SDRAM;
wire [63:0] reconfig_to_pll, reconfig_from_pll;

pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(CLK_60M),
    .outclk_1(CLK_SDRAM),
    .locked(locked),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);

wire        cfg_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;

pll_cfg pll_cfg
(
    .mgmt_clk(CLK_50M),
    .mgmt_reset(1'b0),
    .mgmt_waitrequest(cfg_waitrequest),
    .mgmt_read(1'b0),
    .mgmt_readdata(),
    .mgmt_write(cfg_write),
    .mgmt_address(cfg_address),
    .mgmt_writedata(cfg_data),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll)
);

wire        ph_auto = (status[31:28] == 4'd0);
wire  [6:0] cal_ph;
wire        cal_tgl, cal_hold;
wire        ph_tgl;

sdram_phase_ctl #(.CNT_SEL(5'd1), .MAN_STEP(7'd5)) phase_ctl
(
    .clk(CLK_50M),
    .sel(status[31:28]),
    .cal_val(cal_ph),
    .cal_tgl(cal_tgl),
    .ack_tgl(ph_tgl),
    .cfg_waitrequest(cfg_waitrequest),
    .cfg_write(cfg_write),
    .cfg_address(cfg_address),
    .cfg_data(cfg_data)
);

reg [2:0] ph_tgl_s = 3'd0;
always @(posedge CLK_60M) ph_tgl_s <= {ph_tgl_s[1:0], ph_tgl};
wire rd_recal = ph_tgl_s[2] ^ ph_tgl_s[1];

assign CLK_VIDEO = CLK_60M;

wire reset = RESET | status[0] | buttons[1] | ioctl_download | cal_hold;

// por_reset must exclude ioctl_download: with it the load FSM stays idle and no byte lands
reg  [3:0] por_cnt = 4'd0;
wire       por_reset = ~&por_cnt;
always @(posedge CLK_60M) if (por_reset) por_cnt <= por_cnt + 1'b1;

wire [12:0] kb;
wire  [0:0] kbx;
ctl_keyboard #(.NX(1), .NXO(1), .XKEYS({24'h10_12_00})) keyboard
	(.clk(CLK_60M), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx(kbx));
wire btn_up       = kb[0];
wire btn_down     = kb[1];
wire btn_left     = kb[2];
wire btn_right    = kb[3];
wire btn_attack   = kb[4];
wire btn_jump     = kbx[0];
wire btn_1p_start = kb[6];
wire btn_2p_start = kb[7];
wire btn_coin1    = kb[8];
wire btn_coin2    = kb[9];
wire btn_service  = kb[10];
wire btn_pause    = kb[12];

wire m_up1      = btn_up        | joystick_0[3];
wire m_down1    = btn_down      | joystick_0[2];
wire m_left1    = btn_left      | joystick_0[1];
wire m_right1   = btn_right     | joystick_0[0];
wire m_attack1  = btn_attack    | joystick_0[4];
wire m_jump1    = btn_jump      | joystick_0[5];

wire m_up2      = btn_up        | joystick_1[3];
wire m_down2    = btn_down      | joystick_1[2];
wire m_left2    = btn_left      | joystick_1[1];
wire m_right2   = btn_right     | joystick_1[0];
wire m_attack2  = btn_attack    | joystick_1[4];
wire m_jump2    = btn_jump      | joystick_1[5];

wire m_coin1    = btn_coin1     | joystick_0[6];
wire m_coin2    = btn_coin2     | joystick_1[6];
wire m_start1   = btn_1p_start  | joystick_0[7];
wire m_start2   = btn_2p_start  | joystick_0[8];
wire m_pause    = btn_pause     | joystick_0[9];

wire m_service  = btn_service                  ;

wire ctrl_flip_ud = 1'b0;

wire m_up1_c   = ctrl_flip_ud ? m_down1 : m_up1;
wire m_down1_c = ctrl_flip_ud ? m_up1   : m_down1;
wire m_up2_c   = ctrl_flip_ud ? m_down2 : m_up2;
wire m_down2_c = ctrl_flip_ud ? m_up2   : m_down2;

wire m_left1_c  = ctrl_flip_ud ? m_right1 : m_left1;
wire m_right1_c = ctrl_flip_ud ? m_left1  : m_right1;
wire m_left2_c  = ctrl_flip_ud ? m_right2 : m_left2;
wire m_right2_c = ctrl_flip_ud ? m_left2  : m_right2;

wire [7:0] keycoin_port = ~{m_coin2, m_coin1, 1'b0, m_service, 1'b0, 1'b0, m_start2, m_start1};
wire [7:0] pad1_port    = ~{2'b00, m_jump1, m_attack1, m_up1_c, m_down1_c, m_left1_c, m_right1_c};
wire [7:0] pad2_port    = ~{2'b00, m_jump2, m_attack2, m_up2_c, m_down2_c, m_left2_c, m_right2_c};

wire [15:0] hs_address      = 16'd0;
wire  [7:0] hs_data_in      = 8'd0;
wire  [7:0] hs_data_out     = 8'd0;
wire        hs_write_enable = 1'b0;
wire        hs_access_read  = 1'b0;
wire        hs_access_write = 1'b0;
wire        hs_pause        = 1'b0;
wire        hs_configured   = 1'b0;
assign      ioctl_din       = 8'd0;
assign      ioctl_upload_req = 1'b0;

wire [23:0] rgb_out;
pause #(8,8,8,60) pause
(
	.*,
	.clk_sys(CLK_60M),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[26:25])
);

wire hblank, vblank;
wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;

wire rotate_ccw  = ~is_xx;
wire no_rotate   = ~is_vertical | status[12] | direct_video;
wire flip        = status[11];
screen_rotate screen_rotate(.*);

arcade_video #(512,24) arcade_video
(
	.*,

	.clk_video(CLK_60M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[17:15])
);

reg [7:0] dip_sw[8] = '{8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_60M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end
wire [7:0] sw0 = dip_sw[0];

wire       rd_auto = (status[21:19] == 3'd0);
wire [1:0] rd_mode = (status[21:19] == 3'd2) ? 2'd0 :
                     (status[21:19] == 3'd3) ? 2'd2 :
                     (status[21:19] == 3'd4) ? 2'd3 : 2'd1;

uplframebuffer_dispatcher uplframebuffer_inst
(
	.reset(reset),
	.por_reset(por_reset),
	.clk_60m(CLK_60M),

	.keycoin(keycoin_port),
	.pad1(pad1_port),
	.pad2(pad2_port),
	.dsw1(dip_sw[0]),
	.dsw2(dip_sw[1]),

	.set_id(set_id),

	.video_hsync(hs),
	.video_vsync(vs),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.ce_pix(ce_pix),

	.video_r(r),
	.video_g(g),
	.video_b(b),

	.sound_l(audio_l),
	.sound_r(audio_r),

	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_index(ioctl_index),
	.ioctl_download(ioctl_download),
	.ioctl_wait(ioctl_wait),

	.crt_flip(status[22]),
	.h_adj(status[35:32]),
	.v_adj(status[39:36]),

	.pause(pause_cpu),

	.rd_auto(rd_auto),
	.rd_mode(rd_mode),
	.rd_recal(rd_recal),
	.ph_auto(ph_auto),
	.ld_hold(status[0]),
	.ph_req_val(cal_ph),
	.ph_req_tgl(cal_tgl),
	.cal_hold(cal_hold),

	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK()
);

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(CLK_SDRAM),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
