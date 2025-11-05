`timescale 1ns/1ps

module accelerator_tb;

  // --- parameters
  localparam int IMG_W = 24;
  localparam int IMG_H = 24;
  localparam int PIXW  = 8;

  // --- DUT I/O
  logic clk, reset;
  logic [71:0] i_f;
  logic i_valid, i_ready;
  logic [PIXW-1:0] i_x;
  logic o_valid, o_ready;
  logic [PIXW-1:0] o_y;

  // --- Image storage
  logic [PIXW-1:0] image_mem [0:IMG_W*IMG_H-1];
  int out_file;

  // --- Instantiate DUT
  accelerator #(.IMG_W(IMG_W)) dut (
    .clk(clk), .reset(reset),
    .i_f(i_f),
    .i_valid(i_valid),
    .i_ready(i_ready),
    .i_x(i_x),
    .o_valid(o_valid),
    .o_ready(o_ready),
    .o_y(o_y)
  );

  // --- Clock
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // --- Test sequence
initial begin
  $display("Loading plus.txt...");
  $readmemb("C:/Users/reetr/OneDrive/Desktop/CNN_Accelerator/tests/plus.txt", image_mem);

  // Example 3x3 filter (edge-like)
  i_f = {8'sd1,8'sd0,-8'sd1,
         8'sd1,8'sd0,-8'sd1,
         8'sd1,8'sd0,-8'sd1};

  i_valid = 0;
  i_x = 0;
  i_ready = 1;
  reset = 1;
  repeat(5) @(posedge clk);
  reset = 0;
  $display("Reset deasserted at time %t", $time);

  // --- Feed all pixels
  $display("Feeding pixels...");
  for (int idx = 0; idx < IMG_W*IMG_H; idx++) begin
    @(posedge clk);
    i_valid <= 1;
    i_x     <= image_mem[idx];
    if (idx % 50 == 0) $display("Fed pixel %0d = %0d at time %t", idx, image_mem[idx], $time);
  end
  @(posedge clk);
  i_valid <= 0;
  $display("Finished feeding at time %t", $time);

  // --- Wait for any valid outputs
  $display("Waiting for accelerator outputs...");
  repeat(5000) @(posedge clk);
  $display("End of simulation at %t", $time);

  $fclose(out_file);
  $finish;
end

  // --- Capture and log outputs
  initial begin
    out_file = $fopen("rtl_output.txt","w");
    wait(!reset);
    forever begin
      @(posedge clk);
      if (o_valid) begin
        $fwrite(out_file,"%0d\n",o_y);
        $display("Output pixel: %0d", o_y);
      end
    end
  end

endmodule
