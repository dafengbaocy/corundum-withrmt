`timescale 1ns / 1ps

module ask_stage #(
    parameter C_S_AXIS_DATA_WIDTH = 512,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter STAGE_ID = 0,
    parameter PHV_LEN = 512,
    parameter KEY_WIDTH = 32,         // 关键字宽度
    parameter VALUE_WIDTH = 32,       // 值宽度
    parameter MEMORY_DEPTH = 16384,   // 2^14
    parameter ACTION_LEN = 25,
    parameter KV_IDX = 0,             // 默认使用第0个KV对
    parameter C_VLANID_WIDTH = 12
)
(
    input                                   axis_clk,
    input                                   aresetn,

    // 数据包头信息
    input [PHV_LEN-1:0]                     phv_in,
    input                                   phv_in_valid,
    output                                  stage_ready_out,
    output                                  vlan_ready_out,

    // VLAN 输入
    input [C_VLANID_WIDTH-1:0]              vlan_in,
    input                                   vlan_valid_in,

    // 输出信号
    output [PHV_LEN-1:0]                    phv_out,
    output                                  phv_out_valid,
    input                                   stage_ready_in,
    output [C_VLANID_WIDTH-1:0]             vlan_out,
    output                                  vlan_valid_out,
    input                                   vlan_out_ready,

    // 控制路径
    input [C_S_AXIS_DATA_WIDTH-1:0]         c_s_axis_tdata,
    input [C_S_AXIS_TUSER_WIDTH-1:0]        c_s_axis_tuser,
    input [C_S_AXIS_DATA_WIDTH/8-1:0]       c_s_axis_tkeep,
    input                                   c_s_axis_tvalid,
    input                                   c_s_axis_tlast,

    output [C_S_AXIS_DATA_WIDTH-1:0]        c_m_axis_tdata,
    output [C_S_AXIS_TUSER_WIDTH-1:0]       c_m_axis_tuser,
    output [C_S_AXIS_DATA_WIDTH/8-1:0]      c_m_axis_tkeep,
    output                                  c_m_axis_tvalid,
    output                                  c_m_axis_tlast
);

// ask_extract 到 aggregator_top 的连接信号
wire [PHV_LEN-1:0]           ask2agg_phv;
wire                         ask2agg_phv_valid;
wire [31:0]                  ask2agg_bitmap;
wire [15:0]                  ask2agg_aggre_index;
wire [7:0]                   ask2agg_ptype;
wire                         agg2ask_ready;

// 聚合器所需要的KV对和元数据
wire [4*KEY_WIDTH-1:0]       keys_to_agg;      // 4个key输入
wire [4*VALUE_WIDTH-1:0]     values_to_agg;    // 4个value输入
wire [19:0]                  base_addr_to_agg; // 基地址
wire [3:0]                   valid_bitmap_to_agg; // 有效KV对位图
wire                         is_even_seq_to_agg;  // 是否为偶数序列
wire [13:0]                  index_to_agg;        // 寄存器索引
wire                         is_empty_to_agg;     // 是否为空记录
wire                         is_update_to_agg;    // 是否为更新操作
wire                         is_aggr_pkt_to_agg;  // 是否为聚合包

// 寄存器记录中间状态
reg [PHV_LEN-1:0]            ask2agg_phv_r;
reg                          ask2agg_phv_valid_r;
reg [31:0]                   ask2agg_bitmap_r;
reg [15:0]                   ask2agg_aggre_index_r;
reg [7:0]                    ask2agg_ptype_r;

// VLAN 信号传递
reg [C_VLANID_WIDTH-1:0]     vlan_out_r;
reg                          vlan_valid_out_r;

// 控制路径信号
reg [C_S_AXIS_DATA_WIDTH-1:0]        c_m_axis_tdata_r;
reg [C_S_AXIS_TUSER_WIDTH-1:0]       c_m_axis_tuser_r;
reg [C_S_AXIS_DATA_WIDTH/8-1:0]      c_m_axis_tkeep_r;
reg                                  c_m_axis_tvalid_r;
reg                                  c_m_axis_tlast_r;

// 寄存器更新逻辑
always @(posedge axis_clk) begin
    if (~aresetn) begin
        ask2agg_phv_r <= 0;
        ask2agg_phv_valid_r <= 0;
        ask2agg_bitmap_r <= 0;
        ask2agg_aggre_index_r <= 0;
        ask2agg_ptype_r <= 0;
        
        vlan_out_r <= 0;
        vlan_valid_out_r <= 0;
        
        c_m_axis_tdata_r <= 0;
        c_m_axis_tuser_r <= 0;
        c_m_axis_tkeep_r <= 0;
        c_m_axis_tvalid_r <= 0;
        c_m_axis_tlast_r <= 0;
    end
    else begin
        ask2agg_phv_r <= ask2agg_phv;
        ask2agg_phv_valid_r <= ask2agg_phv_valid;
        ask2agg_bitmap_r <= ask2agg_bitmap;
        ask2agg_aggre_index_r <= ask2agg_aggre_index;
        ask2agg_ptype_r <= ask2agg_ptype;
        
        vlan_out_r <= vlan_in;  // 传递VLAN信号
        vlan_valid_out_r <= vlan_valid_in;
        
        c_m_axis_tdata_r <= c_s_axis_tdata;
        c_m_axis_tuser_r <= c_s_axis_tuser;
        c_m_axis_tkeep_r <= c_s_axis_tkeep;
        c_m_axis_tvalid_r <= c_s_axis_tvalid;
        c_m_axis_tlast_r <= c_s_axis_tlast;
    end
end

// 实例化ask_extract模块
ask_extract #(
    .C_S_AXIS_DATA_WIDTH(C_S_AXIS_DATA_WIDTH),
    .C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
    .STAGE_ID(STAGE_ID),
    .PHV_LEN(PHV_LEN),
    .KEY_WIDTH(KEY_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
) ask_extractor (
    .clk(axis_clk),
    .rst_n(aresetn),
    
    // 数据包头信息
    .phv_in(phv_in),
    .phv_valid_in(phv_in_valid),
    
    // 有效信号
    .valid_in(phv_in_valid),
    .ready_out(stage_ready_out),
    
    // 输出PHV
    .phv_out(ask2agg_phv),
    .phv_valid_out(ask2agg_phv_valid),
    
    // 提取的关键字段输出
    .bitmap_out(ask2agg_bitmap),
    .aggre_index_out(ask2agg_aggre_index),
    .ptype_out(ask2agg_ptype),
    
    .ready_in(agg2ask_ready)
);

// VLAN就绪信号
assign vlan_ready_out = agg2ask_ready;

// 从PHV中提取的数据填充到聚合器所需要的输入
// 这里假设PHV中已经有了KV对和元数据
// 实际实现中可能需要根据具体的PHV格式进行调整
assign keys_to_agg = ask2agg_phv_r[255:128];    // 假设4个32位key在PHV的这个位置
assign values_to_agg = ask2agg_phv_r[127:0];    // 假设4个32位value在PHV的这个位置
assign base_addr_to_agg = ask2agg_aggre_index_r[15:0] << 4; // 从aggre_index生成基地址
assign valid_bitmap_to_agg = 4'b1111;           // 默认所有KV对都有效，可根据实际需求调整
assign is_even_seq_to_agg = 1'b1;               // 默认为偶数序列
assign index_to_agg = ask2agg_aggre_index_r[13:0]; // 寄存器索引
assign is_empty_to_agg = 1'b0;                  // 默认不为空
assign is_update_to_agg = 1'b1;                 // 默认为更新操作
assign is_aggr_pkt_to_agg = (ask2agg_ptype_r == 8'h09); // 如果ptype为0x09，则为聚合包

// 实例化aggregator_top模块
aggregator_top #(
    .KEY_WIDTH(KEY_WIDTH),         // 32位key
    .VALUE_WIDTH(VALUE_WIDTH),     // 32位value
    .MEMORY_DEPTH(MEMORY_DEPTH),   // 内存深度
    .ACTION_LEN(ACTION_LEN),       // 动作长度
    .STAGE_ID(STAGE_ID),           // 阶段ID
    .PHV_LEN(PHV_LEN),             // PHV长度
    .KV_IDX(KV_IDX)                // 使用的KV对索引
) aggregator_inst (
    .clk(axis_clk),
    .rst_n(aresetn),
    
    // 从ask_extract接收的PHV输入
    .phv_in(ask2agg_phv_r),
    
    // 从ask_extract接收的KV对输入
    .keys_in(keys_to_agg),         // 4个key输入
    .values_in(values_to_agg),     // 4个value输入
    
    // 从ask_extract接收的序列号相关输入
    .base_addr_in(base_addr_to_agg),      // 基地址
    .valid_bitmap_in(valid_bitmap_to_agg), // 有效的KV对位图
    .is_even_seq(is_even_seq_to_agg),     // 是否为偶数序列
    
    // 从ask_extract接收的元数据输入
    .index_in(index_to_agg),              // 寄存器索引
    .is_empty(is_empty_to_agg),           // 是否为空记录
    .is_update(is_update_to_agg),         // 是否为更新操作
    .is_aggr_pkt(is_aggr_pkt_to_agg),     // 是否为聚合包
    
    // 有效信号和控制
    .valid_in(ask2agg_phv_valid_r),
    .ready_in(stage_ready_in),
    
    // 输出接口
    .phv_out(phv_out),             // PHV输出
    .valid_out(phv_out_valid),
    .ready_out(agg2ask_ready)
);

// 控制路径直接透传
assign c_m_axis_tdata = c_m_axis_tdata_r;
assign c_m_axis_tuser = c_m_axis_tuser_r;
assign c_m_axis_tkeep = c_m_axis_tkeep_r;
assign c_m_axis_tvalid = c_m_axis_tvalid_r;
assign c_m_axis_tlast = c_m_axis_tlast_r;

// VLAN输出
assign vlan_out = vlan_out_r;
assign vlan_valid_out = vlan_valid_out_r;

endmodule 