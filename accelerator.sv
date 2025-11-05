//============================================================
// accelerator.sv
// 3x3 Convolution → ReLU → 2x2 MaxPool
// Vivado-safe, with debug prints for simulation
//============================================================
`timescale 1ns/1ps

module accelerator #(
    parameter int PIXEL_DATAW = 8,
    parameter int COEFF_DATAW = 8,
    parameter int IMG_W       = 24
)(
    input  logic                          clk,
    input  logic                          reset,
    input  logic [9*COEFF_DATAW-1:0]      i_f,
    input  logic                          i_valid,
    input  logic                          i_ready,
    input  logic [PIXEL_DATAW-1:0]        i_x,
    output logic                          o_valid,
    output logic                          o_ready,
    output logic [PIXEL_DATAW-1:0]        o_y
);

    // ------------------------------
    // Parameters & State
    // ------------------------------
    localparam int FILTER_SIZE = 3;
    localparam int COLW = $clog2(IMG_W+1);

    logic signed [COEFF_DATAW-1:0] r_f [0:FILTER_SIZE-1][0:FILTER_SIZE-1];
    logic coeffs_loaded;

    logic [COLW-1:0] col;
    logic [31:0]     row;

    logic [PIXEL_DATAW-1:0] linebuf0 [0:IMG_W-1];
    logic [PIXEL_DATAW-1:0] linebuf1 [0:IMG_W-1];

    logic [PIXEL_DATAW-1:0] win_r0 [0:2];
    logic [PIXEL_DATAW-1:0] win_r1 [0:2];
    logic [PIXEL_DATAW-1:0] win_r2 [0:2];

    (* use_dsp = "yes" *) logic signed [COEFF_DATAW+PIXEL_DATAW-1:0] m [0:8];
    logic signed [COEFF_DATAW+PIXEL_DATAW+4:0] mac_sum;
    logic signed [COEFF_DATAW+PIXEL_DATAW+4:0] conv_out_raw;

    logic conv_valid, relu_valid, pool_valid;
    logic [PIXEL_DATAW-1:0] relu_narrow, pool_out;

    logic [PIXEL_DATAW-1:0] pool_a, pool_b, pool_c, pool_d;
    logic [PIXEL_DATAW-1:0] ab, cd;

    wire col_is_odd = (col[0] == 1'b1);
    wire row_is_odd = (row[0] == 1'b1);

    assign o_ready = 1'b1;

    // ------------------------------
    // Coefficients Load
    // ------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            coeffs_loaded <= 1'b0;
        end else if (!coeffs_loaded) begin
            r_f[0][0] <= i_f[ 7: 0];
            r_f[0][1] <= i_f[15: 8];
            r_f[0][2] <= i_f[23:16];
            r_f[1][0] <= i_f[31:24];
            r_f[1][1] <= i_f[39:32];
            r_f[1][2] <= i_f[47:40];
            r_f[2][0] <= i_f[55:48];
            r_f[2][1] <= i_f[63:56];
            r_f[2][2] <= i_f[71:64];
            coeffs_loaded <= 1'b1;
            $display("[%t] Coefficients loaded.", $time);
        end
    end

    // ------------------------------
    // Column/Row stepping + line buffers
    // ------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            col <= '0;
            row <= '0;
        end else if (i_valid && o_ready) begin
            linebuf0[col] <= i_x;
            if (col == IMG_W-1) begin
                col <= 0;
                row <= row + 1;
                for (int k = 0; k < IMG_W; k++) linebuf1[k] <= linebuf0[k];
            end else begin
                col <= col + 1;
            end
        end
    end

    // ------------------------------
    // 3x3 window builder
    // ------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i=0; i<3; i++) begin
                win_r0[i] <= 0;
                win_r1[i] <= 0;
                win_r2[i] <= 0;
            end
            conv_valid <= 0;
        end else if (i_valid && o_ready) begin
            win_r0[0] <= win_r0[1];
            win_r0[1] <= win_r0[2];
            win_r0[2] <= i_x;

            win_r1[0] <= win_r1[1];
            win_r1[1] <= win_r1[2];
            win_r1[2] <= linebuf0[col];

            win_r2[0] <= win_r2[1];
            win_r2[1] <= win_r2[2];
            win_r2[2] <= linebuf1[col];

            conv_valid <= (coeffs_loaded && (col >= 2) && (row >= 2));
            if (conv_valid)
                $display("[%t] Conv window valid at row=%0d col=%0d", $time, row, col);
        end
    end

    // ------------------------------
    // Convolution (DSP mults + adder tree)
    // ------------------------------
    always_comb begin
        m[0] = $signed(r_f[0][0]) * $signed({1'b0,win_r2[0]});
        m[1] = $signed(r_f[0][1]) * $signed({1'b0,win_r2[1]});
        m[2] = $signed(r_f[0][2]) * $signed({1'b0,win_r2[2]});
        m[3] = $signed(r_f[1][0]) * $signed({1'b0,win_r1[0]});
        m[4] = $signed(r_f[1][1]) * $signed({1'b0,win_r1[1]});
        m[5] = $signed(r_f[1][2]) * $signed({1'b0,win_r1[2]});
        m[6] = $signed(r_f[2][0]) * $signed({1'b0,win_r0[0]});
        m[7] = $signed(r_f[2][1]) * $signed({1'b0,win_r0[1]});
        m[8] = $signed(r_f[2][2]) * $signed({1'b0,win_r0[2]});
        mac_sum =  (m[0]+m[1]) + (m[2]+m[3]) + (m[4]+m[5]) + (m[6]+m[7]) + m[8];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            conv_out_raw <= 0;
        end else if (conv_valid) begin
            conv_out_raw <= mac_sum;
            $display("[%t] Conv result: %0d", $time, mac_sum);
        end
    end

    // ------------------------------
    // ReLU
    // ------------------------------
    function automatic [PIXEL_DATAW-1:0] clamp8(input signed [COEFF_DATAW+PIXEL_DATAW+4:0] x);
        if (x < 0)        clamp8 = 8'd0;
        else if (x > 255) clamp8 = 8'd255;
        else              clamp8 = x[7:0];
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            relu_valid <= 0;
            relu_narrow <= 0;
        end else begin
            relu_valid <= conv_valid;
            relu_narrow <= clamp8((conv_out_raw < 0) ? 0 : conv_out_raw);
            if (relu_valid)
                $display("[%t] ReLU output: %0d", $time, relu_narrow);
        end
    end

    // ------------------------------
    // 2x2 Max Pool
    // ------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            pool_valid <= 0;
            pool_out   <= 0;
            pool_a <= 0; pool_b <= 0; pool_c <= 0; pool_d <= 0;
        end else begin
            pool_valid <= 0;

            if (relu_valid) begin
                if (col_is_odd) begin
                    if (row_is_odd) begin
                        pool_d <= relu_narrow;
                        ab = (pool_a > pool_b) ? pool_a : pool_b;
                        cd = (pool_c > relu_narrow) ? pool_c : relu_narrow;
                        pool_out   <= (ab > cd) ? ab : cd;
                        pool_valid <= 1;
                        $display("[%t] Pool output: %0d", $time, pool_out);
                    end else begin
                        pool_b <= relu_narrow;
                    end
                end else begin
                    if (row_is_odd) begin
                        pool_c <= relu_narrow;
                    end else begin
                        pool_a <= relu_narrow;
                    end
                end
            end
        end
    end

    // ------------------------------
    // Output
    // ------------------------------
    assign o_valid = pool_valid; // no backpressure during debug
    assign o_y     = pool_out;

    always_ff @(posedge clk) begin
        if (o_valid)
            $display("[%t] >>> Output pixel: %0d", $time, o_y);
    end

endmodule
