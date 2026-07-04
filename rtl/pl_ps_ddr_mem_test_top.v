`timescale 1ns / 1ps
`include "config.vh"

module pl_ps_ddr_mem_test_top #(
    parameter integer CLK_HZ = `CFG_CLK_HZ,
    parameter integer UART_BAUD = `CFG_UART_BAUD,
    parameter [63:0]  TEST_BASE_ADDR = 64'h0000_0000_1000_0000,
    parameter [31:0]  TEST_BYTES = 32'h0100_0000,
    parameter integer AXI_DATA_WIDTH = 64,
    parameter integer AXI_ADDR_WIDTH = 64,
    parameter integer BURST_BEATS = 16
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         uart_rx,
    output wire                         uart_tx,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0]                   m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0]                   m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0]                   m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *)
    output wire                         m_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *)
    output wire [3:0]                   m_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *)
    output wire [2:0]                   m_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *)
    output wire [3:0]                   m_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output reg                          m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire                         m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire                         m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output reg                          m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire                         m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0]                   m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire                         m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output reg                          m_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    output reg  [AXI_ADDR_WIDTH-1:0]    m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0]                   m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0]                   m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0]                   m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *)
    output wire                         m_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *)
    output wire [3:0]                   m_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *)
    output wire [2:0]                   m_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *)
    output wire [3:0]                   m_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output reg                          m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  wire                         m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  wire [1:0]                   m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  wire                         m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  wire                         m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output reg                          m_axi_rready
);

    localparam integer AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    localparam integer BURST_BYTES = AXI_STRB_WIDTH * BURST_BEATS;
    localparam FLAG_WRITE = 8'h01;
    localparam FLAG_READ_VERIFY = 8'h02;
    localparam RESP_OK = 8'h00;
    localparam RESP_BUSY = 8'h01;
    localparam RESP_BAD_ALIGN = 8'h02;
    localparam RESP_BAD_SIZE = 8'h03;

    assign m_axi_awlen   = BURST_BEATS - 1;
    assign m_axi_awsize  = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_wstrb   = {AXI_STRB_WIDTH{1'b1}};
    reg [AXI_DATA_WIDTH-1:0] wdata_r = {AXI_DATA_WIDTH{1'b0}};
    reg wlast_r = 1'b0;
    assign m_axi_wdata   = wdata_r;
    assign m_axi_wlast   = wlast_r;

    assign m_axi_arlen   = BURST_BEATS - 1;
    assign m_axi_arsize  = 3'd3;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;

    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart_rx (
        .rx         (uart_rx),
        .clk        (aclk),
        .data       (rx_data),
        .data_avail (rx_valid)
    );

    wire [7:0] tx_data;
    wire       tx_en;
    wire       tx_avail;
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart_tx (
        .tx             (uart_tx),
        .clk            (aclk),
        .data           (tx_data),
        .transmit_en    (tx_en),
        .transmit_avail (tx_avail)
    );

    wire        cmd_valid;
    wire [63:0] cmd_base;
    wire [31:0] cmd_bytes;
    wire [31:0] cmd_seed;
    wire [7:0]  cmd_flags;
    wire        proto_error;

    command_parser u_command_parser (
        .clk         (aclk),
        .rstn        (aresetn),
        .rx_data     (rx_data),
        .rx_valid    (rx_valid),
        .cmd_valid   (cmd_valid),
        .cmd_base    (cmd_base),
        .cmd_bytes   (cmd_bytes),
        .cmd_seed    (cmd_seed),
        .cmd_flags   (cmd_flags),
        .proto_error (proto_error)
    );

    reg        ack_req = 1'b0;
    reg [7:0]  ack_status = RESP_OK;
    reg        result_valid = 1'b0;
    wire       result_accepted;
    reg [63:0] active_base = TEST_BASE_ADDR;
    reg [31:0] active_bytes = TEST_BYTES;
    reg [31:0] active_seed = 32'h1357_9BDF;
    reg [7:0]  active_flags = FLAG_WRITE | FLAG_READ_VERIFY;
    reg [31:0] active_bursts = TEST_BYTES / BURST_BYTES;

    response_sender u_response_sender (
        .clk           (aclk),
        .rstn          (aresetn),
        .tx_avail      (tx_avail),
        .tx_data       (tx_data),
        .tx_en         (tx_en),
        .ack_req       (ack_req),
        .ack_status    (ack_status),
        .result_valid  (result_valid),
        .result_accept (result_accepted),
        .status        ((error_count == 0) ? RESP_OK : 8'h80),
        .base_addr     (active_base),
        .test_bytes    (active_bytes),
        .flags         (active_flags),
        .seed          (active_seed),
        .write_cycles  (write_cycles),
        .read_cycles   (read_cycles),
        .error_count   (error_count),
        .first_index   (first_error_index),
        .first_expected(first_error_expected),
        .first_actual  (first_error_actual)
    );

    function [63:0] pattern64;
        input [31:0] idx;
        input [31:0] seed;
        begin
            pattern64 = {32'hA5A5_0000 ^ idx ^ seed,
                         32'h5A5A_0000 ^ {idx[15:0], idx[31:16]} ^ 32'h3C6E_F35F ^ {seed[15:0], seed[31:16]}};
        end
    endfunction

    function [31:0] pattern32;
        input [31:0] idx;
        input [31:0] seed;
        begin
            pattern32 = 32'hA5A5_0000 ^ seed ^ idx;
        end
    endfunction

    function [63:0] pattern_lane_safe;
        input [31:0] idx;
        input [31:0] seed;
        reg [31:0] p;
        begin
            p = pattern32(idx >> 1, seed);
            pattern_lane_safe = {p, p};
        end
    endfunction

    reg [3:0] state = 4'd0;
    reg [31:0] burst_index = 32'd0;
    reg [31:0] write_beat_index = 32'd0;
    reg [31:0] read_beat_index = 32'd0;
    reg [7:0]  burst_beat = 8'd0;
    reg [63:0] write_cycles = 64'd0;
    reg [63:0] read_cycles = 64'd0;
    reg [31:0] error_count = 32'd0;
    reg [31:0] first_error_index = 32'd0;
    reg [63:0] first_error_expected = 64'd0;
    reg [63:0] first_error_actual = 64'd0;
    wire [63:0] expected_rdata = pattern_lane_safe(read_beat_index, active_seed);

    localparam ST_IDLE     = 4'd0;
    localparam ST_WRITE_AW = 4'd1;
    localparam ST_WRITE_W  = 4'd2;
    localparam ST_WRITE_B  = 4'd3;
    localparam ST_READ_AR  = 4'd4;
    localparam ST_READ_R   = 4'd5;
    localparam ST_REPORT   = 4'd6;

    wire busy = (state != ST_IDLE) || result_valid;
    wire bad_align = (cmd_base[6:0] != 7'd0);
    wire bad_size = (cmd_bytes == 32'd0) || (cmd_bytes[6:0] != 7'd0);
    wire [31:0] cmd_bursts = cmd_bytes >> 7;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= ST_IDLE;
            active_base <= TEST_BASE_ADDR;
            active_bytes <= TEST_BYTES;
            active_seed <= 32'h1357_9BDF;
            active_flags <= FLAG_WRITE | FLAG_READ_VERIFY;
            active_bursts <= TEST_BYTES / BURST_BYTES;
            burst_index <= 32'd0;
            write_beat_index <= 32'd0;
            read_beat_index <= 32'd0;
            burst_beat <= 8'd0;
            write_cycles <= 64'd0;
            read_cycles <= 64'd0;
            error_count <= 32'd0;
            first_error_index <= 32'd0;
            first_error_expected <= 64'd0;
            first_error_actual <= 64'd0;
            ack_req <= 1'b0;
            ack_status <= RESP_OK;
            result_valid <= 1'b0;
            m_axi_awaddr <= TEST_BASE_ADDR;
            m_axi_awvalid <= 1'b0;
            wdata_r <= {AXI_DATA_WIDTH{1'b0}};
            wlast_r <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            m_axi_araddr <= TEST_BASE_ADDR;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
        end else begin
            ack_req <= 1'b0;
            if (result_accepted) begin
                result_valid <= 1'b0;
            end

            if (proto_error) begin
                ack_req <= 1'b1;
                ack_status <= 8'h7F;
            end else if (cmd_valid) begin
                ack_req <= 1'b1;
                if (busy) begin
                    ack_status <= RESP_BUSY;
                end else if (bad_align) begin
                    ack_status <= RESP_BAD_ALIGN;
                end else if (bad_size) begin
                    ack_status <= RESP_BAD_SIZE;
                end else begin
                    ack_status <= RESP_OK;
                    active_base <= cmd_base;
                    active_bytes <= cmd_bytes;
                    active_seed <= cmd_seed;
                    active_flags <= (cmd_flags == 0) ? (FLAG_WRITE | FLAG_READ_VERIFY) : cmd_flags;
                    active_bursts <= cmd_bursts;
                    burst_index <= 32'd0;
                    write_beat_index <= 32'd0;
                    read_beat_index <= 32'd0;
                    burst_beat <= 8'd0;
                    write_cycles <= 64'd0;
                    read_cycles <= 64'd0;
                    error_count <= 32'd0;
                    first_error_index <= 32'd0;
                    first_error_expected <= 64'd0;
                    first_error_actual <= 64'd0;
                    m_axi_awaddr <= cmd_base;
                    m_axi_araddr <= cmd_base;
                    if ((cmd_flags & FLAG_WRITE) != 0 || cmd_flags == 0) begin
                        wdata_r <= pattern_lane_safe(32'd0, cmd_seed);
                        wlast_r <= (BURST_BEATS == 1);
                        m_axi_awvalid <= 1'b1;
                        state <= ST_WRITE_AW;
                    end else begin
                        m_axi_arvalid <= 1'b1;
                        state <= ST_READ_AR;
                    end
                end
            end

            case (state)
                ST_IDLE: begin
                    if (!cmd_valid) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b0;
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b0;
                    end
                end

                ST_WRITE_AW: begin
                    write_cycles <= write_cycles + 1'b1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid <= 1'b0;
                        burst_beat <= 8'd0;
                        wdata_r <= pattern_lane_safe(write_beat_index, active_seed);
                        wlast_r <= (BURST_BEATS == 1);
                        m_axi_wvalid <= 1'b1;
                        state <= ST_WRITE_W;
                    end
                end

                ST_WRITE_W: begin
                    write_cycles <= write_cycles + 1'b1;
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        if (m_axi_wlast) begin
                            m_axi_bready <= 1'b1;
                            state <= ST_WRITE_B;
                        end else begin
                            burst_beat <= burst_beat + 1'b1;
                            wdata_r <= pattern_lane_safe(write_beat_index + burst_beat + 1'b1, active_seed);
                            wlast_r <= (burst_beat + 1'b1 == BURST_BEATS - 1);
                            m_axi_wvalid <= 1'b1;
                        end
                    end
                end

                ST_WRITE_B: begin
                    write_cycles <= write_cycles + 1'b1;
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp != 2'b00 && error_count != 32'hFFFF_FFFF) begin
                            error_count <= error_count + 1'b1;
                        end
                        if (burst_index == active_bursts - 1) begin
                            burst_index <= 32'd0;
                            if ((active_flags & FLAG_READ_VERIFY) != 0) begin
                                m_axi_araddr <= active_base;
                                m_axi_arvalid <= 1'b1;
                                state <= ST_READ_AR;
                            end else begin
                                result_valid <= 1'b1;
                                state <= ST_REPORT;
                            end
                        end else begin
                            burst_index <= burst_index + 1'b1;
                            write_beat_index <= write_beat_index + BURST_BEATS;
                            m_axi_awaddr <= m_axi_awaddr + BURST_BYTES;
                            m_axi_awvalid <= 1'b1;
                            wdata_r <= pattern_lane_safe(write_beat_index + BURST_BEATS, active_seed);
                            wlast_r <= (BURST_BEATS == 1);
                            state <= ST_WRITE_AW;
                        end
                    end
                end

                ST_READ_AR: begin
                    read_cycles <= read_cycles + 1'b1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= ST_READ_R;
                    end
                end

                ST_READ_R: begin
                    read_cycles <= read_cycles + 1'b1;
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (((active_flags & FLAG_WRITE) != 0) && (m_axi_rdata != expected_rdata)) begin
                            if (error_count != 32'hFFFF_FFFF) begin
                                error_count <= error_count + 1'b1;
                            end
                            if (error_count == 32'd0) begin
                                first_error_index <= read_beat_index;
                                first_error_expected <= expected_rdata;
                                first_error_actual <= m_axi_rdata;
                            end
                        end
                        if (m_axi_rresp != 2'b00 && error_count != 32'hFFFF_FFFF) begin
                            error_count <= error_count + 1'b1;
                        end
                        read_beat_index <= read_beat_index + 1'b1;
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            if (burst_index == active_bursts - 1) begin
                                result_valid <= 1'b1;
                                state <= ST_REPORT;
                            end else begin
                                burst_index <= burst_index + 1'b1;
                                m_axi_araddr <= m_axi_araddr + BURST_BYTES;
                                m_axi_arvalid <= 1'b1;
                                state <= ST_READ_AR;
                            end
                        end
                    end
                end

                ST_REPORT: begin
                    if (result_accepted) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

module command_parser (
    input  wire        clk,
    input  wire        rstn,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         cmd_valid,
    output reg  [63:0] cmd_base,
    output reg  [31:0] cmd_bytes,
    output reg  [31:0] cmd_seed,
    output reg  [7:0]  cmd_flags,
    output reg         proto_error
);
    localparam TYPE_START = 8'h01;
    localparam LEN_START = 8'd17;
    localparam S_SYNC0 = 3'd0;
    localparam S_SYNC1 = 3'd1;
    localparam S_TYPE  = 3'd2;
    localparam S_LEN   = 3'd3;
    localparam S_PAY   = 3'd4;
    localparam S_CSUM  = 3'd5;

    reg [2:0] state = S_SYNC0;
    reg [7:0] frame_type = 8'd0;
    reg [7:0] frame_len = 8'd0;
    reg [7:0] idx = 8'd0;
    reg [7:0] sum = 8'd0;
    reg [135:0] payload = 136'd0;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_SYNC0;
            cmd_valid <= 1'b0;
            proto_error <= 1'b0;
            cmd_base <= 64'd0;
            cmd_bytes <= 32'd0;
            cmd_seed <= 32'd0;
            cmd_flags <= 8'd0;
            frame_type <= 8'd0;
            frame_len <= 8'd0;
            idx <= 8'd0;
            sum <= 8'd0;
            payload <= 136'd0;
        end else begin
            cmd_valid <= 1'b0;
            proto_error <= 1'b0;
            if (rx_valid) begin
                case (state)
                    S_SYNC0: state <= (rx_data == 8'h55) ? S_SYNC1 : S_SYNC0;
                    S_SYNC1: state <= (rx_data == 8'hAA) ? S_TYPE : ((rx_data == 8'h55) ? S_SYNC1 : S_SYNC0);
                    S_TYPE: begin
                        frame_type <= rx_data;
                        sum <= rx_data;
                        state <= S_LEN;
                    end
                    S_LEN: begin
                        frame_len <= rx_data;
                        sum <= sum + rx_data;
                        idx <= 8'd0;
                        payload <= 136'd0;
                        if (rx_data == 0) begin
                            state <= S_CSUM;
                        end else if (rx_data > LEN_START) begin
                            proto_error <= 1'b1;
                            state <= S_SYNC0;
                        end else begin
                            state <= S_PAY;
                        end
                    end
                    S_PAY: begin
                        case (idx)
                            8'd0:  payload[7:0]     <= rx_data;
                            8'd1:  payload[15:8]    <= rx_data;
                            8'd2:  payload[23:16]   <= rx_data;
                            8'd3:  payload[31:24]   <= rx_data;
                            8'd4:  payload[39:32]   <= rx_data;
                            8'd5:  payload[47:40]   <= rx_data;
                            8'd6:  payload[55:48]   <= rx_data;
                            8'd7:  payload[63:56]   <= rx_data;
                            8'd8:  payload[71:64]   <= rx_data;
                            8'd9:  payload[79:72]   <= rx_data;
                            8'd10: payload[87:80]   <= rx_data;
                            8'd11: payload[95:88]   <= rx_data;
                            8'd12: payload[103:96]  <= rx_data;
                            8'd13: payload[111:104] <= rx_data;
                            8'd14: payload[119:112] <= rx_data;
                            8'd15: payload[127:120] <= rx_data;
                            8'd16: payload[135:128] <= rx_data;
                        endcase
                        sum <= sum + rx_data;
                        idx <= idx + 1'b1;
                        if (idx == frame_len - 1) begin
                            state <= S_CSUM;
                        end
                    end
                    S_CSUM: begin
                        if ((sum + rx_data) == 8'd0 && frame_type == TYPE_START && frame_len == LEN_START) begin
                            cmd_base <= payload[63:0];
                            cmd_bytes <= payload[95:64];
                            cmd_seed <= payload[127:96];
                            cmd_flags <= payload[135:128];
                            cmd_valid <= 1'b1;
                        end else begin
                            proto_error <= 1'b1;
                        end
                        state <= S_SYNC0;
                    end
                    default: state <= S_SYNC0;
                endcase
            end
        end
    end
endmodule

module response_sender (
    input  wire        clk,
    input  wire        rstn,
    input  wire        tx_avail,
    output reg  [7:0]  tx_data,
    output reg         tx_en,
    input  wire        ack_req,
    input  wire [7:0]  ack_status,
    input  wire        result_valid,
    output reg         result_accept,
    input  wire [7:0]  status,
    input  wire [63:0] base_addr,
    input  wire [31:0] test_bytes,
    input  wire [7:0]  flags,
    input  wire [31:0] seed,
    input  wire [63:0] write_cycles,
    input  wire [63:0] read_cycles,
    input  wire [31:0] error_count,
    input  wire [31:0] first_index,
    input  wire [63:0] first_expected,
    input  wire [63:0] first_actual
);
    localparam TYPE_ACK = 8'h81;
    localparam TYPE_RESULT = 8'h82;
    localparam LEN_ACK = 8'd1;
    localparam LEN_RESULT = 8'd58;
    localparam S_IDLE = 3'd0;
    localparam S_SYNC0 = 3'd1;
    localparam S_SYNC1 = 3'd2;
    localparam S_TYPE = 3'd3;
    localparam S_LEN = 3'd4;
    localparam S_PAY = 3'd5;
    localparam S_CSUM = 3'd6;

    reg [2:0] state = S_IDLE;
    reg [7:0] frame_type = 8'd0;
    reg [7:0] frame_len = 8'd0;
    reg [7:0] idx = 8'd0;
    reg [7:0] sum = 8'd0;
    reg [463:0] payload = 464'd0;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            tx_data <= 8'hFF;
            tx_en <= 1'b0;
            result_accept <= 1'b0;
            frame_type <= 8'd0;
            frame_len <= 8'd0;
            idx <= 8'd0;
            sum <= 8'd0;
            payload <= 464'd0;
        end else begin
            tx_en <= 1'b0;
            result_accept <= 1'b0;
            if (state == S_IDLE) begin
                if (ack_req) begin
                    frame_type <= TYPE_ACK;
                    frame_len <= LEN_ACK;
                    payload <= {456'd0, ack_status};
                    idx <= 8'd0;
                    state <= S_SYNC0;
                end else if (result_valid) begin
                    frame_type <= TYPE_RESULT;
                    frame_len <= LEN_RESULT;
                    payload <= {first_actual, first_expected, first_index, error_count, read_cycles, write_cycles, seed, flags, test_bytes, base_addr, status};
                    idx <= 8'd0;
                    result_accept <= 1'b1;
                    state <= S_SYNC0;
                end
            end else if (tx_avail && !tx_en) begin
                case (state)
                    S_SYNC0: begin
                        tx_data <= 8'h55;
                        tx_en <= 1'b1;
                        state <= S_SYNC1;
                    end
                    S_SYNC1: begin
                        tx_data <= 8'hAA;
                        tx_en <= 1'b1;
                        state <= S_TYPE;
                    end
                    S_TYPE: begin
                        tx_data <= frame_type;
                        tx_en <= 1'b1;
                        sum <= frame_type;
                        state <= S_LEN;
                    end
                    S_LEN: begin
                        tx_data <= frame_len;
                        tx_en <= 1'b1;
                        sum <= sum + frame_len;
                        idx <= 8'd0;
                        state <= S_PAY;
                    end
                    S_PAY: begin
                        tx_data <= payload[7:0];
                        tx_en <= 1'b1;
                        sum <= sum + payload[7:0];
                        payload <= {8'd0, payload[463:8]};
                        idx <= idx + 1'b1;
                        if (idx == frame_len - 1) begin
                            state <= S_CSUM;
                        end
                    end
                    S_CSUM: begin
                        tx_data <= (~sum) + 1'b1;
                        tx_en <= 1'b1;
                        state <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
