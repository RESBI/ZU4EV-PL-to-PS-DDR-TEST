`timescale 1ns / 1ps
`include "config.vh"

module uart_tx #(
    parameter CLK_HZ = `CFG_CLK_HZ,
    parameter BAUD = `CFG_UART_BAUD,
    parameter ACC_WIDTH = `CFG_UART_ACC_WIDTH
) (
    output reg          tx,
    input  wire         clk,
    input  wire [7:0]   data,
    input  wire         transmit_en,
    output reg          transmit_avail
);

    localparam IDLE      = 0;
    localparam START_BIT = 1;
    localparam DATA_BITS = 2;
    localparam STOP_BIT  = 3;

    reg [2:0]  state = IDLE;
    reg [7:0]  data_temp = 8'h00;
    reg [3:0]  bit_counter = 4'd0;
    reg [ACC_WIDTH-1:0] baud_acc = 0;

    localparam [ACC_WIDTH-1:0] BAUD_INC = ((BAUD * (64'd1 << ACC_WIDTH)) + (CLK_HZ / 2)) / CLK_HZ;
    wire [ACC_WIDTH:0] baud_sum = {1'b0, baud_acc} + {1'b0, BAUD_INC};
    wire baud_tick = baud_sum[ACC_WIDTH];

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                transmit_avail <= 1'b1;
                tx <= 1'b1;
                baud_acc <= 0;
                if (transmit_en) begin
                    data_temp <= data;
                    bit_counter <= 4'd0;
                    transmit_avail <= 1'b0;
                    state <= START_BIT;
                end
            end

            START_BIT: begin
                tx <= 1'b0;
                baud_acc <= baud_sum[ACC_WIDTH-1:0];
                if (baud_tick) begin
                    state <= DATA_BITS;
                end
            end

            DATA_BITS: begin
                tx <= data_temp[bit_counter];
                baud_acc <= baud_sum[ACC_WIDTH-1:0];
                if (baud_tick) begin
                    if (bit_counter == 4'd7) begin
                        state <= STOP_BIT;
                    end else begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
            end

            STOP_BIT: begin
                tx <= 1'b1;
                baud_acc <= baud_sum[ACC_WIDTH-1:0];
                if (baud_tick) begin
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end

endmodule
