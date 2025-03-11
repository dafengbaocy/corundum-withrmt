module aggregator #(
    parameter KEY_WIDTH = 32,
    parameter VALUE_WIDTH = 32,
    parameter MEMORY_DEPTH = 16384  // 2^14
)(
    input                           clk,
    input                           rst_n,
    
    // 输入接口
    input [KEY_WIDTH-1:0]          key_in,
    input [VALUE_WIDTH-1:0]        value_in,
    input [3:0]                    valid_bitmap,
    input [31:0]                   ptype,
    input                          valid_in,
    
    // State Unit 接口
    output wire                    su_valid_in,       // 状态单元有效输入
    input [1:0]                    su_exec_state,     // 状态单元执行状态
    input [3:0]                    su_new_bitmap,     // 状态单元位图
    input [31:0]                   su_new_ptype,      // 状态单元包类型
    input                          su_valid_out,      // 状态单元有效输出
    output wire [13:0]             su_hash_addr,      // 哈希地址输出
    
    // 内存读取结果接口 (连接到状态单元)
    output reg [KEY_WIDTH-1:0]     mem_read_key,      // 内存读取的键值
    output reg                     mem_read_valid,    // 内存读取结果有效
    
    // ALU2接口
    output reg [24:0]              alu_action,        // ALU动作
    output reg                     alu_action_valid,  // ALU动作有效
    output reg [KEY_WIDTH-1:0]     alu_operand_1,     // 存储时的键值
    output reg [31:0]              alu_operand_2,     // 地址
    output reg [VALUE_WIDTH-1:0]   alu_operand_3,     // 存储时的值
    input [KEY_WIDTH-1:0]          alu_result,        // ALU结果
    input                          alu_result_valid,  // 结果有效信号
    output reg                     alu_ready,         // ALU就绪信号
    
    // 页表接口
    input [15:0]                   page_tbl_out,      // 页表输出
    output reg                     page_tbl_req,      // 页表请求
    
    // 输出接口
    output [3:0]                   out_bitmap,
    output [31:0]                  out_ptype,
    output                         valid_out
);

    // ALU操作码定义
    localparam ALU_LOAD = 4'b1011;    // 读取操作
    localparam ALU_STORE = 4'b1000;   // 存储操作
    localparam ALU_LOADD = 4'b0111;   // 读取并+1操作
    localparam ALU_LOADINC = 4'b0100; // 读取并+自定义值操作
    
    // 状态机状态
    localparam SM_IDLE = 3'd0;
    localparam SM_MEM_READ = 3'd1;
    localparam SM_EXEC_STATE_UNIT = 3'd2;
    localparam SM_MEM_WRITE = 3'd3;
    localparam SM_INCREMENT = 3'd4;
    localparam SM_COMPLETE = 3'd5;
    
    // 执行状态定义 (与aggregator_state_unit一致)
    localparam IDLE = 2'b00;
    localparam SKIP = 2'b01;
    localparam UPDATE = 2'b10;
    localparam CLEANUP = 2'b11;
    
    // 内部信号和寄存器
    reg [2:0] sm_state, sm_state_next;
    reg [3:0] out_bitmap_reg, out_bitmap_next;
    reg [31:0] out_ptype_reg, out_ptype_next;
    reg valid_in_reg;
    reg [31:0] increment_value;  // 自定义增量值
    
    // 主状态机 - 组合逻辑部分
    always @(*) begin
        sm_state_next = sm_state;
        out_bitmap_next = out_bitmap_reg;
        out_ptype_next = out_ptype_reg;
        
        // 默认值
        mem_read_key = {KEY_WIDTH{1'b0}};
        mem_read_valid = 1'b0;
        
        // ALU接口默认值
        alu_action = 25'd0;
        alu_action_valid = 1'b0;
        alu_operand_1 = {KEY_WIDTH{1'b0}};
        alu_operand_2 = 32'd0;
        alu_operand_3 = {VALUE_WIDTH{1'b0}};
        alu_ready = 1'b1;
        
        // 页表请求默认关闭
        page_tbl_req = 1'b0;
        
        // 状态机逻辑
        case (sm_state)
            SM_IDLE: begin
                if (valid_in) begin
                    sm_state_next = SM_MEM_READ;
                end
            end
            
            SM_MEM_READ: begin
                // 发起内存读取请求
                page_tbl_req = 1'b1;
                alu_action = {ALU_LOAD, 21'd0};  // Load操作
                alu_action_valid = 1'b1;
                alu_operand_1 = key_in;
                alu_operand_2 = {{18{1'b0}}, su_hash_addr};  // 使用哈希地址
                
                if (alu_result_valid) begin
                    // 将ALU读取结果传递给状态单元
                    mem_read_key = alu_result;
                    mem_read_valid = 1'b1;
                    sm_state_next = SM_EXEC_STATE_UNIT;
                end
            end
            
            SM_EXEC_STATE_UNIT: begin
                // 等待状态执行单元完成决策
                mem_read_valid = 1'b0;
                
                if (su_valid_out) begin
                    case (su_exec_state)
                        IDLE: begin
                            // 空闲状态，直接完成
                            sm_state_next = SM_COMPLETE;
                        end
                        
                        SKIP: begin
                            // 跳过操作，保持数据不变，直接完成
                            out_bitmap_next = valid_bitmap;
                            out_ptype_next = ptype;
                            sm_state_next = SM_COMPLETE;
                        end
                        
                        UPDATE: begin
                            // 更新操作，需要写入内存
                            out_bitmap_next = su_new_bitmap;
                            out_ptype_next = su_new_ptype;
                            sm_state_next = SM_MEM_WRITE;
                        end
                        
                        CLEANUP: begin
                            // 整理操作，先执行增量操作，再写入内存
                            out_bitmap_next = su_new_bitmap;
                            out_ptype_next = su_new_ptype;
                            sm_state_next = SM_INCREMENT;
                        end
                    endcase
                end
            end
            
            SM_INCREMENT: begin
                // 使用LOADINC操作进行自定义增量操作
                page_tbl_req = 1'b1;
                alu_action = {ALU_LOADINC, 21'd0};  // LOADINC操作
                alu_action_valid = 1'b1;
                alu_operand_1 = 32'd5;  // 自定义增量值，这里设置为5
                alu_operand_2 = {{18{1'b0}}, su_hash_addr};  // 哈希地址
                alu_operand_3 = 32'd0;  // 默认值
                
                if (alu_result_valid) begin
                    sm_state_next = SM_COMPLETE;  // 直接进入完成状态，因为LOADINC已经完成了写回操作
                end
            end
            
            SM_MEM_WRITE: begin
                // 执行内存写入操作
                page_tbl_req = 1'b1;
                alu_action = {ALU_STORE, 21'd0};  // Store操作
                alu_action_valid = 1'b1;
                alu_operand_1 = key_in;  // 键
                alu_operand_2 = {{18{1'b0}}, su_hash_addr};  // 哈希地址
                alu_operand_3 = value_in;  // 值
                
                if (alu_result_valid) begin
                    sm_state_next = SM_COMPLETE;
                end
            end
            
            SM_COMPLETE: begin
                // 完成处理
                sm_state_next = SM_IDLE;
            end
        endcase
    end
    
    // 状态寄存器更新 - 时序逻辑部分
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm_state <= SM_IDLE;
            out_bitmap_reg <= 4'b0;
            out_ptype_reg <= 32'd0;
            valid_in_reg <= 1'b0;
            increment_value <= 32'd5;  // 默认增量值设置为5
        end else begin
            sm_state <= sm_state_next;
            out_bitmap_reg <= out_bitmap_next;
            out_ptype_reg <= out_ptype_next;
            valid_in_reg <= valid_in;
        end
    end
    
    // 输出赋值
    assign out_bitmap = out_bitmap_reg;
    assign out_ptype = out_ptype_reg;
    assign valid_out = (sm_state == SM_COMPLETE);
    
    // 状态单元输入有效信号
    assign su_valid_in = (sm_state == SM_EXEC_STATE_UNIT) && valid_in_reg;
    
    // 生成哈希地址 (简单实现示例 - 实际应该由状态单元或其他模块提供)
    assign su_hash_addr = key_in[13:0];
    
endmodule 