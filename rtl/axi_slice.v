
module axis_slice #(
    parameter DATA_W = 8
) (
    input                  clk,
    input                  rst,

    // Input interface: sender -> this stage
    input                  s_valid,
    output                 s_ready,
    input  [DATA_W-1:0]    s_data,
    input                  s_last,

    // Output interface: this stage -> receiver
    output reg             m_valid,
    input                  m_ready,
    output reg [DATA_W-1:0] m_data,
    output reg             m_last
);

    assign s_ready = ~m_valid | m_ready;
    reg [DATA_W:0] beat_reg;
    

    always @(posedge clk) begin
        
        if (rst) begin
        m_valid<=0;

        end
        else if (s_ready) begin
        m_valid<=s_valid;
        if (s_valid)
        beat_reg<={s_data,s_last};
        end

    end

always @ (*) begin
    m_data=beat_reg[DATA_W:1];
    m_last=beat_reg[0];
end
endmodule
