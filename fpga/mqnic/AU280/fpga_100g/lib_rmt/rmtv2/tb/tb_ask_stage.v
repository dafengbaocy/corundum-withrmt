`timescale 1ns / 1ps

module tb_ask_stage #(
    parameter STAGE = 0,  //valid: 0-4
    parameter PHV_LEN = 512,
    parameter KEY_WIDTH = 32,
    parameter VALUE_WIDTH = 32,
    parameter MEMORY_DEPTH = 16384,
    parameter ACTION_LEN = 25,
    parameter C_VLANID_WIDTH = 12
)();

reg                      clk;
reg                      rst_n;

// PHV输入输出信号
reg [PHV_LEN-1:0]        phv_in;
reg                      phv_in_valid;
wire [PHV_LEN-1:0]       phv_out;
wire                     phv_out_valid;

// VLAN输入输出信号
reg [C_VLANID_WIDTH-1:0] vlan_in;
reg                      vlan_valid_in;
wire [C_VLANID_WIDTH-1:0] vlan_out;
wire                     vlan_valid_out;
reg                      vlan_out_ready;

// 控制信号
wire                     stage_ready_out;
wire                     vlan_ready_out;
reg                      stage_ready_in;

// 控制路径信号
reg [511:0]              c_s_axis_tdata;
reg [127:0]              c_s_axis_tuser;
reg [63:0]               c_s_axis_tkeep;
reg                      c_s_axis_tvalid;
reg                      c_s_axis_tlast;

wire [511:0]             c_m_axis_tdata;
wire [127:0]             c_m_axis_tuser;
wire [63:0]              c_m_axis_tkeep;
wire                     c_m_axis_tvalid;
wire                     c_m_axis_tlast;

//clk signal
localparam CYCLE = 10;

always begin
    #(CYCLE/2) clk = ~clk;
end

//reset signal
initial begin
    clk = 0;
    rst_n = 1;
    #(10);
    rst_n = 0; //reset all the values
    #(10);
    rst_n = 1;
end

initial begin
    #(2*CYCLE); //after the rst_n, start the test
    
    // 初始化所有输入信号
    phv_in <= 0;
    phv_in_valid <= 0;
    vlan_in <= 0;
    vlan_valid_in <= 0;
    vlan_out_ready <= 1;
    stage_ready_in <= 1;
    
    // 初始化控制路径信号
    c_s_axis_tdata <= 0;
    c_s_axis_tuser <= 0;
    c_s_axis_tkeep <= 0;
    c_s_axis_tvalid <= 0;
    c_s_axis_tlast <= 0;
    
    #(5*CYCLE);
    
    // 测试用例1：发送一个包含KV对的PHV
    phv_in <= {
        // 4个KV对 (每个KV对64位)
        {32'hdeadbeef, 32'h12345678},  // KV对0
        {32'hcafebabe, 32'h87654321},  // KV对1
        {32'hfeedface, 32'h11223344},  // KV对2
        {32'hdeadc0de, 32'h44332211},  // KV对3
        // 其他PHV字段
        {PHV_LEN-256{1'b0}}
    };
    phv_in_valid <= 1;
    vlan_in <= 12'h123;
    vlan_valid_in <= 1;
    
    #CYCLE;
    
    // 重置输入信号
    phv_in <= 0;
    phv_in_valid <= 0;
    vlan_in <= 0;
    vlan_valid_in <= 0;
    
    #(4*CYCLE);
    
    // 测试用例2：发送一个更新操作的PHV
    phv_in <= {
        // 4个KV对，其中包含一个需要更新的值
        {32'hdeadbeef, 32'h12345678},  // KV对0
        {32'hcafebabe, 32'h87654321},  // KV对1
        {32'hfeedface, 32'h11223344},  // KV对2
        {32'hdeadc0de, 32'h44332211},  // KV对3
        // 其他PHV字段
        {PHV_LEN-256{1'b0}}
    };
    phv_in_valid <= 1;
    vlan_in <= 12'h456;
    vlan_valid_in <= 1;
    
    #CYCLE;
    
    // 重置输入信号
    phv_in <= 0;
    phv_in_valid <= 0;
    vlan_in <= 0;
    vlan_valid_in <= 0;
    
    #(4*CYCLE);
    
    // 测试用例3：发送一个清理操作的PHV
    phv_in <= {
        // 4个KV对，用于清理操作
        {32'hdeadbeef, 32'h12345678},  // KV对0
        {32'hcafebabe, 32'h87654321},  // KV对1
        {32'hfeedface, 32'h11223344},  // KV对2
        {32'hdeadc0de, 32'h44332211},  // KV对3
        // 其他PHV字段
        {PHV_LEN-256{1'b0}}
    };
    phv_in_valid <= 1;
    vlan_in <= 12'h789;
    vlan_valid_in <= 1;
    
    #CYCLE;
    
    // 重置输入信号
    phv_in <= 0;
    phv_in_valid <= 0;
    vlan_in <= 0;
    vlan_valid_in <= 0;
    
    #(4*CYCLE);
end

// 实例化ask_stage模块
ask_stage #(
    .STAGE_ID(STAGE),
    .PHV_LEN(PHV_LEN),
    .KEY_WIDTH(KEY_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .MEMORY_DEPTH(MEMORY_DEPTH),
    .ACTION_LEN(ACTION_LEN),
    .C_VLANID_WIDTH(C_VLANID_WIDTH)
) ask_stage_inst (
    .axis_clk(clk),
    .aresetn(rst_n),
    
    // 数据包头信息
    .phv_in(phv_in),
    .phv_in_valid(phv_in_valid),
    .stage_ready_out(stage_ready_out),
    .vlan_ready_out(vlan_ready_out),
    
    // VLAN输入
    .vlan_in(vlan_in),
    .vlan_valid_in(vlan_valid_in),
    
    // 输出信号
    .phv_out(phv_out),
    .phv_out_valid(phv_out_valid),
    .stage_ready_in(stage_ready_in),
    .vlan_out(vlan_out),
    .vlan_valid_out(vlan_valid_out),
    .vlan_out_ready(vlan_out_ready),
    
    // 控制路径
    .c_s_axis_tdata(c_s_axis_tdata),
    .c_s_axis_tuser(c_s_axis_tuser),
    .c_s_axis_tkeep(c_s_axis_tkeep),
    .c_s_axis_tvalid(c_s_axis_tvalid),
    .c_s_axis_tlast(c_s_axis_tlast),
    
    .c_m_axis_tdata(c_m_axis_tdata),
    .c_m_axis_tuser(c_m_axis_tuser),
    .c_m_axis_tkeep(c_m_axis_tkeep),
    .c_m_axis_tvalid(c_m_axis_tvalid),
    .c_m_axis_tlast(c_m_axis_tlast)
);

endmodule 