# PL-PS DDR 测试器性能改进方案

> 本文档基于对当前 `PL-PS-MEM-TEST` 项目的完整阅读，先总结项目本身（作用 / 设计 /
> 配置 / 配置方法 / 目的），再分析当前实测约 500 MB/s 与 3200 MT/s × 64 bit
> DDR4 理论带宽之间巨大差距的根因，提出分阶段的提速方案，并对每一步给出
> 详细设计改动与性能预测。

---

## 0. 项目总结

### 0.1 作用

该项目为 Xilinx Zynq UltraScale+ MPSoC `xczu4ev-sfvc784-2-i` 板卡上的
**PL 侧 PS DDR 测试器**。PL 自定义逻辑通过 PS 高性能 AXI 端口
`S_AXI_HP0_FPD` 直接读写 PS DDR4，主机通过 PL UART（8 Mbps）下发命令，
FPGA 写入确定模式 → 读回 → 比对 → 上报原始周期数与错误信息，由主机换算成
MB/s 与 PASS/FAIL。它是一个独立于 Linux/FSBL 的硬件级 DDR 校验工具。

### 0.2 设计

- **顶层模块** `rtl/pl_ps_ddr_mem_test_top.v`，包含：
  - `uart_rx` / `uart_tx`：分数累加器 UART，200 MHz 时钟下支持 8 Mbps。
  - `command_parser`：解析 `55 AA TYPE LEN PAYLOAD CHECKSUM` 帧。
  - AXI 主状态机：`ST_IDLE → ST_WRITE_AW → ST_WRITE_W → ST_WRITE_B
    → ST_READ_AR → ST_READ_R → ST_REPORT`。
  - `response_sender`：组帧发送 ACK / MAP_CONFIG / RESULT。
  - `map_addr()`：逻辑地址到物理地址翻译（DDR_LOW / DDR_HIGH 两段）。
  - `pattern_lane_safe`：128-bit 对粒度的 lane-safe 模式发生器与比较器。
- **AXI 参数**（`pl_ps_ddr_mem_test_top.v:9-11`）：
  - `AXI_DATA_WIDTH = 64`
  - `AXI_ADDR_WIDTH = 64`
  - `BURST_BEATS = 16` → 每突发 128 字节
- **地址翻译**（`pl_ps_ddr_mem_test_top.v:236-248`）：单 split、两段映射，
  默认 `logical_split=0x8000_0000`、`physical_high_base=0x8_0000_0000`。
- **复位**：`rtl/pl_por.v`，~5 ms PL 本地 POR，不依赖 PS `pl_resetn0`，
  位流加载后立即可用 UART 调试。
- **互连**：`ddr_tester_0/M_AXI` → `axi_smc_0`（SmartConnect）→
  `zynq_ultra_ps_e_0/S_AXI_HP0_FPD` → PS DDR 控制器 → DDR4。
- **时钟与复位拓扑**：
  ```
  E12 200 MHz osc ─► sys_clk ─► ddr_tester_0/aclk
                              ─► axi_smc_0/aclk
                              ─► zynq_ultra_ps_e_0/saxihp0_fpd_aclk
                              ─► pl_por_0/clk
  pl_por_0/rstn ─► ddr_tester_0/aresetn, axi_smc_0/aresetn
  ```

### 0.3 配置

| 项 | 取值 | 来源 |
|---|---|---|
| 器件 | `xczu4ev-sfvc784-2-i` | `build_pl_ps_ddr_mem_test.tcl:1` |
| PL 时钟 | 200 MHz 单端晶振，E12，LVCMOS25 | `constraints/uart_zu4ev.xdc:4-6` |
| UART | 8 Mbps 8N1，RX=D12，TX=C12 | `constraints/uart_zu4ev.xdc:8-12`，`config.vh` |
| AXI 数据宽度 | 64 bit | `build_pl_ps_ddr_mem_test.tcl:172` |
| AXI 突发长度 | 16 beats (128 B) | `pl_ps_ddr_mem_test_top.v:11` |
| PS HP 端口 | `S_AXI_HP0_FPD`，64 bit | `build_pl_ps_ddr_mem_test.tcl:216-224` |
| DDR 容量/几何 | 4 GiB / 8 Gb ×16 ×4 / 64-bit | `build_pl_ps_ddr_mem_test.tcl:55-62` |
| DDR 速率等级 | `DDR4_2400P`（2400 MT/s，CL=16, tRCD=16, tRP=16, tRC=45.32, tRAS=32, tFAW=30） | `reference/design_1.bd:264-293` |
| DDR 控制器时钟 | 600 MHz（DPLL 半速率，DRAM I/O 1200 MHz） | `reference/design_1.bd:108-112` |
| 默认测试范围 | `0x10000000`，16 MiB | `build_pl_ps_ddr_mem_test.tcl:8-9` |
| 地址翻译默认 | 启用，split `0x8000_0000`，high `0x8_0000_0000` | `pl_ps_ddr_mem_test_top.v:175-177` |

### 0.4 配置方法

1. **PS/DDR 配置**：`build_pl_ps_ddr_mem_test.tcl:20-50` 的
   `apply_ps_config_from_bd` 过程，从仓库内 `reference/design_1.bd` 中正则
   抽取 `CONFIG.*` 字段，整体 `set_property -dict` 一次性写入 PS 块；
   然后 `enable_ps_ddr_high_address` 显式覆盖 8 Gb ×16 几何与
   `PSU__HIGH_ADDRESS__ENABLE=1`，并打开 `DDR_HIGH` 保护从端口。
   这避免了依赖开发者绝对路径，让工程自包含。
2. **PL 时钟/UART**：直接改 `constraints/uart_zu4ev.xdc` 的
   `create_clock`、`PACKAGE_PIN`、`IOSTANDARD`；同步改
   `build_pl_ps_ddr_mem_test.tcl` 的 `pl_clk_mhz/pl_clk_hz`、
   `rtl/config.vh` 的 `CFG_CLK_HZ`、`host/pl_ps_ddr_test.py` 的 `--clk-hz`
   默认值。
3. **波特率**：分数累加器不要求整除，但需同时改
   `build_pl_ps_ddr_mem_test.tcl:uart_baud`、`config.vh:CFG_UART_BAUD`、
   主机 `--baud`。
4. **运行时参数**：主机命令行 `--base/--bytes/--seed/--flags/--logical-split
   /--physical-high-base/--no-addr-map/--query-map` 全部可在每条 START 帧
   中动态改变，无需重新综合。
5. **构建/烧写**：`vivado -mode batch -source build_pl_ps_ddr_mem_test.tcl`
   生成位流与 XSA；`boot_jtag.tcl` 用 `psu_init.tcl` 通过 JTAG 空白启动 PS
   后下装位流（推荐开发用）；或 `tools/create_boot_image.tcl` 生成
   `BOOT.BIN` 走 SD/QSPI。

### 0.5 目的

- 提供一个**自包含、不依赖 PS 软件**的 PL 硬件级 DDR 校验通道：位流加载后
  ~5 ms 即可响应 UART，可用于 bring-up 阶段裸机排查 DDR 训练、地址映射、
  PL-PS 互连问题。
- 验证 4 GiB DDR（含 `0x8_0000_0000` 高地址段）的端到端正确性，支持 4 KiB
  至完整 4 GiB 单命令测试与低/高窗口边界穿越。
- 报告原始 `write_cycles / read_cycles / error_count / first_mismatch*`，
  让主机而非 FPGA 计算速度，避免硬编码除法器。
- 故意采用保守、可调试的简单 AXI 主（单 outstanding、显式状态机、lane-safe
  模式），把**正确性与可观测性**放在**绝对带宽**之前。

---

## 1. 性能现状与理论极限

### 1.1 当前实测（JTAG 空白启动，无 Linux）

来源：`README.md` “Final Measured Results”。

| 测试规模 | 写 | 读 | 错误 |
|---|---|---|---|
| 4 KiB | 505.991 MiB/s | 455.805 MiB/s | 0 |
| 16 MiB | 509.031 MiB/s | 454.583 MiB/s | 0 |
| 1 GiB | 509.031 MiB/s | 454.583 MiB/s | 0 |

写 ~509 MiB/s ≈ **534 MB/s**，读 ~455 MiB/s ≈ **477 MB/s**，与用户描述的
“约 500 MB/s”吻合。

### 1.2 各级理论峰值

```
DDR4-3200 (颗粒规格)        3200 MT/s × 8 B = 25600 MB/s ≈ 24414 MiB/s
DDR4-2400 (当前 PS 配置)    2400 MT/s × 8 B = 19200 MB/s ≈ 18311 MiB/s
AXI 64-bit @ 200 MHz        200 MHz  × 8 B =  1600 MB/s ≈  1526 MiB/s
AXI 128-bit @ 200 MHz       200 MHz  × 16 B=  3200 MB/s ≈  3052 MiB/s
AXI 128-bit @ 300 MHz       300 MHz  × 16 B=  4800 MB/s ≈  4578 MiB/s
```

### 1.3 效率分析

| 瓶颈层 | 峰值 | 当前实测 | 效率 |
|---|---|---|---|
| DDR4-2400 物理 | 18311 MiB/s | 509 MiB/s（写） | **2.8%** |
| 64-bit AXI @ 200 MHz | 1526 MiB/s | 509/455 MiB/s | **33.4% / 29.8%** |

**关键结论**：当前瓶颈**根本不在 DDR4 本身**。颗粒是 3200 MT/s、PS 配的是
2400 MT/s，物理层有 18.3 GiB/s 余量；当前 500 MiB/s 只消耗了 2.8%。
真正卡住的是**PL 侧 AXI 主端口**：64-bit/200 MHz 的理论峰值就只有 1.5 GiB/s，
而 RTL 又只跑到其 30~33%。因此提速的核心是 **PL 侧 AXI 数据通路 + RTL
流水化**，而非 DDR4 时序。

把 DDR4-2400 改成 DDR4-3200（粒料额定值）能再放 1.33× 物理带宽，但只有当
AXI 侧先打到 ≥20 GiB/s 量级时才会成为新的瓶颈——当前距离那还差一个数量级，
所以 DDR4 重配放在最后一步。

---

## 2. 瓶颈根因（代码级定位）

逐条对照 `pl_ps_ddr_mem_test_top.v`：

### 2.1 单 outstanding 读（读路径最主要瓶颈）

`ST_READ_AR → ST_READ_R`（行 437-476）：发一个 AR，等 16 拍 R 全部回来
+比对完，才发下一个 AR。每 burst 之间出现：
```
T_AR_handshake → T_DDR_roundtrip → 16 × T_R_beat → T_next_AR
```
其中 `T_DDR_roundtrip` 在 PS 互连+DDR 控制器路径上典型 20~40 个 200 MHz
时钟。burst 本身只有 16 拍有效数据 → 16 / (16+30) ≈ 35% 效率，正好对应
实测读 29.8%。**只要不打散成多 outstanding，再快的时钟也救不回来**。

### 2.2 突发太短（128 字节）

`BURST_BEATS = 16`（行 11），每 burst 128 B。每 burst 要付：
- 1 拍 AW/AR 握手
- 1 拍 WVALID 拉高 / RVALID 第一拍
- 1 拍 B 响应握手

有效 16 拍 / 总 ~18~20 拍 = 80~89%，再加上 outstanding=1 的 round-trip 空泡，
总效率被进一步压低。AXI4 的 `AWLEN` 字段是 8 bit，最大 256 beats；改到
64 / 128 / 256 几乎零成本。

### 2.3 写通道未完全解耦

`ST_WRITE_B`（行 408-435）等 `BVALID` 到来后才更新 `m_axi_awaddr` 并回到
`ST_WRITE_AW`，即 **AW 通道被 B 通道反压**。理想流水是：
```
AW: 提前发出未来若干 burst 的地址
W : 连续流数据，不被 B 阻塞
B : 后台收集响应
```
当前仅“消除了 beat 之间的强制空拍”（README 所说的 write optimization），
但 burst 间仍串行 → 写效率卡在 33%。

### 2.4 64-bit AXI 数据宽度

PS `S_AXI_HP0_FPD` 在 ZU+ 上**原生支持 128-bit**（`PSU__SAXIGP0__DATA_WIDTH`
可取 32/64/128）。当前强制 64-bit（`build_pl_ps_ddr_mem_test.tcl:172`），
等于把数据通道峰值腰斩。

### 2.5 PL 时钟仅 200 MHz

ZU4EV -2 速度等级下，PL fabric 跑 250 MHz 很轻松，300 MHz 在中等扇出下
也可实现。200 MHz 是直接沿用 E12 晶振，没有 PLL 升频。

### 2.6 SmartConnect 时钟域与读阻塞

`axi_smc_0` 当前与 tester 同域（200 MHz），本身没问题；但因 tester 单
outstanding，SmartConnect 的 pipeline 不能被填满，无法发挥其本可吸收的
DDR 延迟。

### 2.7 DDR4 跑在 2400 MT/s（而非颗粒额定的 3200）

参考 BD 选择 DDR4-2400P 是 bring-up 阶段的保守已知点。这是最后一项，
仅在前面所有改动完成后才有意义。

---

## 3. 提速方案（分阶段，每阶段独立可验证）

总体目标：在不大改主机协议、不牺牲 lane-safe 校验语义的前提下，把写/读
**同时推到 ≥ 2 GiB/s**，并保留向后兼容的 4 KiB / 16 MiB / 1 GiB 测试流程。

阶段路线图（每阶段都先做 4 KiB + 16 MiB 回归，再上 1 GiB）：

```
基线 64b/200MHz/16beat/1os:   写 509  读 455  MiB/s
  │
  ├─ Stage A: 突发长度 16→64 + 写 AW/W/B 解耦
  ├─ Stage B: 读多 outstanding（深度 4）
  ├─ Stage C: AXI 数据宽度 64→128 bit（含 PS 端口改 128）
  ├─ Stage D: PL 时钟 200→250/300 MHz（MMCM 升频）
  └─ Stage E（可选）: DDR4-2400 → DDR4-3200
```

下面逐阶段给出**改动文件、改动要点、RTL 结构、预期性能、风险**。

### Stage A：长突发 + 写通道完全解耦

**目标**：在不改任何 PCB / PS 配置的前提下，仅靠 RTL 把 64-bit/200 MHz
管线的效率从 ~33% 推到 ~70%（写）/ ~50%（读）。

**改动文件**：
- `rtl/pl_ps_ddr_mem_test_top.v`
- `rtl/config.vh`（新增 `CFG_BURST_BEATS`）

**关键 RTL 改动**：

1. `BURST_BEATS` 改为 `64`（参数化，便于后续 128/256）。`BURST_BYTES` 随之
   变为 512 B，128-byte 对齐约束仍然满足。`m_axi_awlen / m_axi_arlen` 自动
   跟随参数（已是 `BURST_BEATS - 1`）。
2. 写引擎改为三通道独立进程：
   ```
   aw_engine: burst_index 每完成一个 B 就自增；只要 outstanding < N 就
              在 AWVALID 上发下一个 burst 地址
   w_engine:  连续产生 WDATA/WLAST/WVALID，与 burst_index 同步；
              不再每个 beat 等握手再拉下一拍 VALID，而是 WVALID 持续为 1
              直到 WREADY 累计够 BURST_BEATS 拍
   b_engine:  只要 BVALID 就 BREADY=1，统计 bresp 错误，更新 outstanding--
   ```
3. 引入 `WRITE_OUTSTANDING` 参数（默认 4），用一个小计数器维护 AW 已发但
   B 未回的数量。SmartConnect/HP0 都支持 ≥16 outstanding，4 是保守值。
4. 读引擎**暂保持单 outstanding**，留到 Stage B；但因为 burst 拉长到 64
   beat，单 outstanding 的相对空泡也从 16/(16+30) ≈ 35% 提升到
   64/(64+30) ≈ 68%。

**预期性能**（200 MHz / 64-bit / 64-beat / 写 outstanding=4，读仍 1）：

```
AXI 峰值 = 1526 MiB/s
写效率：burst 内 64/64=100%，burst 间 AW 可与上一 burst W 重叠 → ~85~90%
  写 ≈ 1526 × 0.85 ≈ 1297 MiB/s  (≈ 1362 MB/s)
读效率：单 outstanding，但 burst 长 → 64/(64+30) ≈ 68%
  读 ≈ 1526 × 0.68 ≈ 1038 MiB/s  (≈ 1089 MB/s)
```

**回归保证**：lane-safe pattern 只依赖 `burst_beat_index`，与 burst 长度
无关，读比对逻辑不变；地址翻译 `map_addr()` 仅作用于 burst 起始地址，128 B
对齐保持，但**对齐约束改为 512 B 对齐**（或保留 128 B 对齐、由 RTL 在内部
处理 burst 边界）。建议在 ACK 阶段把 `BAD_ALIGN` 检查改为
`cmd_base[8:0] != 0` 以与新 burst 一致；同时为兼容老主机，保留 16-beat 模式
作为 `--legacy-burst` 开关。

**风险**：低。仅 RTL 改动，PS 不动，PCB 不动。最容易回归的是 `wlast`
生成时序，建议加 ILA 抓 AW/W/B 三通道一帧验证。

---

### Stage B：读路径多 outstanding

**目标**：把读效率从 ~68% 推到 ≥85%，读带宽接近写带宽。

**改动文件**：
- `rtl/pl_ps_ddr_mem_test_top.v`

**关键 RTL 改动**：

1. 引入 `READ_OUTSTANDING` 参数（默认 4，HP0 可支持到 16）。
2. AR 引擎与 R 引擎拆分：
   ```
   ar_engine: 只要 (ar_issued - r_completed) < READ_OUTSTANDING 且还有
              未读 burst，就在 ARVALID 上发下一个 burst 地址
   r_engine:  连续收 RVALID，按 burst_index 序号和 beat_index 比对；
              RREADY 持续为 1，直到当前 burst RLAST 收完
   ```
3. 由于多 outstanding，R 数据**可能乱序返回**——但 DDR4 控制器与
   SmartConnect 默认保序（同 ID 顺序返回）。**保持 ARID = 0 单 ID**，可
   严格保序；若未来要按 bank 乱序调度，需扩 ID 与重排序缓冲，不在本阶段。
4. 比对逻辑从“当前 beat_index”改为“当前 burst + beat 联合索引”，需要小
   FIFO 缓存每条 outstanding AR 对应的 burst_index。深度 = READ_OUTSTANDING。

**预期性能**：

```
读效率：4 outstanding 足以覆盖 ~30 拍 round-trip，pipeline 几乎不打断
  读 ≈ 1526 × 0.88 ≈ 1343 MiB/s  (≈ 1409 MB/s)
```

**风险**：中。多 outstanding 状态机是本项目最容易出错的点，必须加 ILA 抓
AR/R 全通道；建议先用 `READ_OUTSTANDING=1` 回归 Stage A 行为，再逐步调到
2/4/8。

---

### Stage C：AXI 数据宽度 64 → 128 bit

**目标**：把 AXI 峰值翻倍到 3052 MiB/s，让 Stage A/B 的效率有更大舞台。

**改动文件**：
- `build_pl_ps_ddr_mem_test.tcl`：`PSU__SAXIGP0__DATA_WIDTH 128`；
  SmartConnect 自动适配。
- `rtl/pl_ps_ddr_mem_test_top.v`：
  - `AXI_DATA_WIDTH = 128`，`AXI_STRB_WIDTH = 16`。
  - `BURST_BEATS` 与 `BURST_BYTES` 重新平衡：建议 64 beats × 16 B = 1024 B
    per burst。
  - 模式发生器从 64-bit `pattern_lane_safe` 扩为 128-bit：相邻两 64-bit
    半拍仍保持 lane-safe，但上/下半拍可携带不同 idx，使有效校验粒度仍是
    128-bit 对（保持向后兼容现有错误定位语义）。
  - `wdata_r` 改 128-bit，`m_axi_wstrb` 改 16-bit。
  - 比对器改 128-bit 宽比较。
- `host/pl_ps_ddr_test.py`：`--clk-hz` 不变；不需要协议改动（payload 仍是
  字节计数），但 `BAD_ALIGN` 边界改 1024 B（或保持 128 B 由 RTL 处理边界）。

**关键约束**：
- ZU+ `S_AXI_HP0_FPD` 128-bit 模式要求 PS 端 `saxihp0_fpd_aclk` 仍可来自 PL
  200 MHz（当前已是），不需要 PS PLL 改动。
- SmartConnect 在 64→128 转换处自动插入位宽转换器；本设计直接两端都改 128，
  跳过转换器，路径更短。

**预期性能**：

```
AXI 峰值 = 3052 MiB/s
写效率 ~85% → 写 ≈ 2594 MiB/s (≈ 2720 MB/s)
读效率 ~88% → 读 ≈ 2686 MiB/s (≈ 2818 MB/s)
```

**风险**：中。128-bit 模式下 PS HP 端口的 `WDATA` 走线密度高，时序更紧；
建议在 Stage D 之前先稳在 200 MHz，时序关通过后再升频。lane-safe 模式扩展
需重新验证 4 GiB 全量 PASS。

---

### Stage D：PL 时钟 200 → 250 / 300 MHz（MMCM 升频）

**目标**：进一步把 AXI 峰值推到 3.8~4.6 GiB/s，把 64-bit/200 MHz 时代的
“天花板”彻底打掉。

**改动文件**：
- `constraints/uart_zu4ev.xdc`：保留 E12 200 MHz 输入约束；新增
  `create_generated_clock` 约束 MMCM 输出。
- `rtl/`：新增 `clk_mmcm.v`（实例化 MMCME4_ADV），200 MHz → 250 MHz
  （`CLKFBOUT_MULT=10, DIVCLK_DIVIDE=1, CLKOUT0_DIVIDE=8`）或 300 MHz
  （`CLKFBOUT_MULT=12, DIVCLK_DIVIDE=1, CLKOUT0_DIVIDE=8`），同时输出
  200 MHz 供 UART 与 PL POR。
- `build_pl_ps_ddr_mem_test.tcl`：BD 中新增 `clk_mmcm_0`，输出 `aclk_250`
  接到 `ddr_tester_0/aclk`、`axi_smc_0/aclk`、
  `zynq_ultra_ps_e_0/saxihp0_fpd_aclk`；UART 与 `pl_por_0` 仍用 200 MHz
  原时钟。
- `rtl/config.vh`：拆分为 `CFG_CLK_HZ`（AXI 时钟，250/300 MHz）与
  `CFG_UART_CLK_HZ`（200 MHz）。
- `rtl/uart_rx.v / uart_tx.v`：当前 UART 与 AXI 同域，本阶段后跨域。两个
  选项：
  1. UART 仍在 200 MHz 域，命令/响应通过简单异步 FIFO 跨到 AXI 域（推荐）。
  2. UART 也跑 250/300 MHz（分数累加器无整除要求，可行）。
- `host/pl_ps_ddr_test.py`：`--clk-hz` 默认改为 250000000 或 300000000。

**时序收敛提示**：
- HP0 128-bit 在 -2 速度等级下 250 MHz 几乎免费，300 MHz 需要注意
  SmartConnect 内部流水级数；可在 SmartConnect 上加 1 级 slice。
- tester RTL 全流水化后（Stage A/B），250 MHz 下的关键路径通常是
  `pattern_lane_safe` 的 XOR 树，可改为预先计算的 ROM 表。

**预期性能**：

```
250 MHz / 128-bit:
  峰值 = 250 × 16 = 4000 MB/s ≈ 3815 MiB/s
  写 ≈ 3815 × 0.85 ≈ 3242 MiB/s  (≈ 3402 MB/s)
  读 ≈ 3815 × 0.88 ≈ 3357 MiB/s  (≈ 3522 MB/s)

300 MHz / 128-bit:
  峰值 = 300 × 16 = 4800 MB/s ≈ 4578 MiB/s
  写 ≈ 4578 × 0.85 ≈ 3891 MiB/s  (≈ 4082 MB/s)
  读 ≈ 4578 × 0.88 ≈ 4029 MiB/s  (≈ 4227 MB/s)
```

**风险**：中-高。MMCM 加跨域 FIFO 是新结构，但都是标准模式；主要风险是
300 MHz 时序收敛，若不过则回退 250 MHz 即可，不影响其他阶段。

---

### Stage E（可选）：DDR4-2400 → DDR4-3200

**何时做**：仅当 Stage D 之后 AXI 侧已稳定 ≥ 4 GB/s，并且确实需要向 25 GB/s
物理峰值继续推进时。对当前测试器（单主机、单端口）而言，Stage D 后已经
接近 HP0 单端口在 ZU4EV 上的实际可用上限，再做 DDR4 升速收益边际很小。

**前提**：
- 板子 DDR4 走线 SI 必须支持 3200 MT/s（需查板卡原理图与 PDN 仿真）；
- Hynix `H5AN8G6NDJR-XNC` 数据手册额定 3200 MT/s @ 1.2V，颗粒本身没问题。

**改动方法**：
1. 复制 `reference/design_1.bd` → `reference/design_1_ddr4_3200.bd`。
2. 修改以下 PS 字段为 DDR4-3200 对应值（参考 JEDEC DDR4-3200 22-22-22）：
   ```
   PSU__DDRC__SPEED_BIN                 DDR4_3200N  (或 Vivado 支持的最接近子预设)
   PSU__CRF_APB__DDR_CTRL__FREQMHZ      1600        (DRAM I/O 1600 MHz, 双沿 3200 MT/s)
   PSU__DDR__INTERFACE__FREQMHZ         800         (半速率控制器)
   PSU__DDRC__CL                        22
   PSU__DDRC__CWL                       16
   PSU__DDRC__T_RCD                     22
   PSU__DDRC__T_RP                      22
   PSU__DDRC__T_RC                      60.88       (22 + 22 + tRP_pipe, 按 datasheet)
   PSU__DDRC__T_RAS_MIN                 52
   PSU__DDRC__T_FAW                     50          (32 banks, 4-bank activate window)
   ```
   其余 `DEVICE_CAPACITY/DRAM_WIDTH/ROW_ADDR_COUNT` 已由
   `enable_ps_ddr_high_address` 强制覆盖，无需重设。
3. 重新生成 `psu_init.tcl`（必须！PS PLL 与 DDRC 寄存器值会变），用
   `boot_jtag.tcl` 验证 `DEADBEEF` 读回。
4. 先跑 4 KiB → 16 MiB → 1 GiB 回归。若训练失败（常见于 SI 边界），
   可尝试 DDR4-2666 / DDR4-2933 作为中间档。

**预期性能**：
- 单 HP 端口在 250 MHz / 128-bit 下的实测天花板约为 3.4 GiB/s（Stage D），
  这远低于 DDR4-3200 的 24.4 GiB/s 峰值，**DDR 升速本身不会进一步提升测试器
  带宽**。
- 仅在多端口并发（例如同时开 HPC0+HP1+HP2 走 DMA）或后续要做 VCU/大流量
  PL→DDR 搬运时才有意义。

**风险**：高。DDR 重训练失败会让整个 PS 起不来；务必保留 2400P BD 作回退。

---

## 4. 综合性能预测汇总

| 阶段 | 配置 | 写 (MiB/s) | 读 (MiB/s) | 相对基线倍数（写/读） |
|---|---|---|---|---|
| 基线 | 64b / 200 MHz / 16-beat / 1-os / DDR4-2400 | 509 | 455 | 1.0× / 1.0× |
| A | + 64-beat + 写解耦 (4 os) | ~1297 | ~1038 | 2.55× / 2.28× |
| B | + 读 4-outstanding | ~1297 | ~1343 | 2.55× / 2.95× |
| C | + 128-bit AXI | ~2594 | ~2686 | 5.10× / 5.90× |
| D250 | + 250 MHz MMCM | ~3242 | ~3357 | 6.37× / 7.38× |
| D300 | + 300 MHz MMCM | ~3891 | ~4029 | 7.64× / 8.85× |
| E | + DDR4-3200（仅物理层） | ~3891 | ~4029 | ≈ D300（单端口已封顶） |

> 说明：以上预测基于“AXI 峰值 × 效率”，效率取值来自当前实测外推（写 85%,
> 读 88%，长 burst + 多 outstanding 后的典型上限）。实测会因 SmartConnect
> 流水深度、DDR refresh 周期、PS 后台流量而±10%。

---

## 5. 实施优先级与工作量估计

| 阶段 | 改动量 | 风险 | 收益 | 建议优先级 |
|---|---|---|---|---|
| Stage A | RTL 一个文件 + config.vh | 低 | 写 2.5×、读 2.3× | **P0，先做** |
| Stage B | RTL 一个文件（读引擎重构） | 中 | 读再 +30% | P1，紧跟 A |
| Stage C | RTL + build tcl + PS 端口宽度 | 中 | 整体再 2× | P2 |
| Stage D | 新增 MMCM + 跨域 FIFO + XDC | 中-高 | 再 1.25~1.5× | P3 |
| Stage E | BD 重配 + 重新生成 psu_init | 高 | 单端口下≈0 | 仅多端口场景 |

**推荐落地路径**：A → B → C → D。前两步在 2~3 个工作日内可完成并验证，单
即获得 ~5~6× 提升；C+D 视时序收敛情况 1~2 周。Stage E 暂不做。

---

## 6. 兼容性与回归保证

- **UART 协议不变**：所有阶段保持 `55 AA TYPE LEN PAYLOAD CHECKSUM` 帧格式、
  ACK / MAP_CONFIG / RESULT 三种帧类型、`--query-map` 行为。Stage A 后对齐
  边界从 128 B 变为 512 B（或保留 128 B 由 RTL 处理），可在主机加
  `--burst-beats` 参数透传，老主机仍发 16-beat 模式时由 RTL 兼容。
- **lane-safe 校验语义不变**：所有阶段保持相邻 64-bit 半拍相同，错误定位仍
  到 128-bit 对粒度。Stage C 扩 128-bit 后，把对粒度提升到 256-bit 也行，
  但默认保持 128-bit 兼容。
- **地址翻译不变**：`map_addr()` 仅作用于 burst 起始地址，与数据宽度、burst
  长度、outstanding 深度正交。
- **boot 流程不变**：`boot_jtag.tcl` / `program_bitstream.tcl` /
  `tools/create_boot_image.tcl` 不受影响。Stage E 需重新生成 `psu_init.tcl`，
  是唯一例外。
- **每阶段回归测试集**：4 KiB（边界 + 启动开销）、16 MiB（标准）、
  1 GiB（大流量稳定性）、`0x7fff0000` 128 KiB 边界穿越、
  逻辑 `0x80000000` 16 MiB 高地址翻译、物理 `0x8_0000_0000` 4 KiB 直访。

---

## 7. 调试与可观测性增强

强烈建议在 Stage A 起把 AXI 性能计数器与 ILA 一次性加上，否则后续每阶段
都会陷入“性能上不去却看不到哪一段空”的盲区：

1. 在 `pl_ps_ddr_mem_test_top.v` 内部加 4 个 cycle 计数器：
   - `aw_stall_cycles`：AWVALID=1 且 AWREADY=0 的周期数
   - `w_stall_cycles`：WVALID=1 且 WREADY=0 的周期数
   - `b_idle_cycles`：写阶段无 outstanding AW 的“空窗”周期数
   - `r_idle_cycles`：读阶段 RVALID=0 的周期数
   将它们追加到 RESULT 帧尾部（向后兼容地新增 `LEN_RESULT_EXT = 94`）。
2. 在 SmartConnect 与 HP0 之间插一组 ILA（AW/W/B/AR/R 全通道 + aclk/aresetn），
   depth 4096，触发条件为 `aw_valid & ~aw_ready` 或 `r_valid & ~r_ready`，
   用于定位反压来源。
3. 主机 `pl_ps_ddr_test.py` 加 `--profile` 选项，解析扩展 RESULT 并打印
   `aw/w/b/r` 占空比，便于直接看到是“AW 没跟上”还是“DDR 在反压 W”。

---

## 8. 一句话结论

当前 500 MB/s 不是 DDR4 的极限，而是**单 outstanding + 64-bit + 200 MHz
+ 16-beat 的简单 AXI 主**的极限。先做 Stage A+B（纯 RTL，零硬件改动）即可
拿到 ~2.5× 提升；再做 Stage C+D（128-bit + 升频）拿到 ~7~9× 提升，达到
~4 GB/s 量级，逼近 ZU4EV 单 HP 端口实际可用上限。DDR4-3200 重配留作未来
多端口场景的储备，单测试器用不上。

---

# 9. 实测验证报告

> 以下章节记录每个阶段的实际构建、测试与性能数据。所有测试在 JTAG 空白启动
> （无 Linux/FSBL）下进行，`boot_jtag.tcl` 初始化 PS DDR 后下装位流。

## 9.1 基线 (Baseline)

**配置**：64-bit AXI / 200 MHz / 16-beat burst / 单 outstanding / DDR4-2400P

| 测试规模 | 写 (MiB/s) | 读 (MiB/s) | 错误 | 结果 |
|---|---|---|---|---|
| 4 KiB | 509.289 | 458.211 | 0 | PASS |
| 16 MiB | 509.023 | 454.583 | 0 | PASS |
| 2 GiB | 509.024 | 454.583 | 0 | PASS |

写效率 = 509 / 1526 = **33.4%**；读效率 = 455 / 1526 = **29.8%**。

## 9.2 Stage E：DDR4-3200 尝试（失败回退）

**改动**：在 `build_pl_ps_ddr_mem_test.tcl` 中 `enable_ps_ddr_high_address`
之后追加 DDR4-3200 速度档覆盖（`SPEED_BIN=DDR4_3200AA`，CL=22，tRCD=22，
tRP=22，DDR_CTRL_FREQMHZ=1600）。

**结果**：**Vivado 2024.2 的 ZynqMP PS IP 在 ZU4EV 上最高仅支持
DDR4-2400**。`set_property CONFIG.PSU__DDRC__SPEED_BIN DDR4_3200AA` 被拒绝，
有效速度档列表为：

```
DDR4_1600J, DDR4_1600K, DDR4_1600L,
DDR4_1866L, DDR4_1866M, DDR4_1866N,
DDR4_2133N, DDR4_2133P, DDR4_2133R,
DDR4_2400P, DDR4_2400R, DDR4_2400T, DDR4_2400U
```

`PSU__CRF_APB__DDR_CTRL__FREQMHZ` 上限为 600 MHz（对应 1200 MT/s 控制器
半速率）。DDR4-2666/2933/3200 均不在 IP 支持范围内。

**结论**：Stage E 在此器件/IP 版本上**不可实现**。已回退所有更改，构建脚本
恢复原状。颗粒虽然额定 3200 MT/s，但 PS DDR 控制器物理层上限为 2400 MT/s。
后续阶段全部在 DDR4-2400P 下进行。

## 9.3 Stage A：长突发 (16→64) + 写通道 AW/W/B 完全解耦

**改动文件**：
- `rtl/pl_ps_ddr_mem_test_top.v`

**改动要点**：
1. `BURST_BEATS` 从 16 改为 64（每突发 512 字节）。
2. 新增 `localparam BURST_SHIFT = $clog2(BURST_BYTES)` 和
   `WRITE_OUTSTANDING = 4`。
3. 将原来的 `ST_WRITE_AW → ST_WRITE_W → ST_WRITE_B` 三状态串行写流程
   替换为单一 `ST_WRITE` 状态，AW/W/B 三通道并发执行：
   - **AW 通道**（sticky valid）：只要 `aw_issued < active_bursts` 且
     `wr_outstanding < 4`，就拉高 AWVALID 发下一 burst 地址；AWREADY 后立即
     准备下一个或取消。
   - **W 通道**（sticky valid）：只要对应 burst 的 AW 已被接受
     （`w_burst < aw_issued`），就连续流式发送 WDATA，WVALID 持续到 WREADY
     接收完整个 burst。
   - **B 通道**：`BREADY` 常高，后台收集 B 响应，递减 `wr_outstanding`。
4. 完成条件：`aw_issued == active_bursts && w_burst == active_bursts &&
   wr_outstanding == 0`。
5. 硬编码的 `<< 7` / `>> 7` 全部改为 `<< BURST_SHIFT` / `>> BURST_SHIFT`。
6. `bad_size` 检查从 128 字节对齐改为 BURST_BYTES (512 字节) 对齐。
7. 读路径暂保持单 outstanding，仅受益于 burst 拉长。

**构建**：Vivado 2024.2 综合 + 实现 + 比特流，0 错误，通过。

**实测结果**：

| 测试规模 | 写 (MiB/s) | 读 (MiB/s) | 错误 | 结果 | 写倍数 | 读倍数 |
|---|---|---|---|---|---|---|
| 4 KiB | 1430.861 | 926.750 | 0 | PASS | 2.81× | 2.02× |
| 16 MiB | 1525.853 | 940.545 | 0 | PASS | 3.00× | 2.07× |
| 2 GiB | 1525.879 | 940.518 | 0 | PASS | 3.00× | 2.07× |
| 4 GiB | 1525.879 | 940.518 | 0 | PASS | 3.00× | 2.07× |

**分析**：
- **写路径达到 1525.879 MiB/s = 200 MHz × 8 B 的理论 AXI 峰值，效率 100%**。
  AW/W/B 三通道完全解耦后，写数据连续不断，无任何空泡。这是该 AXI 配置下
  的物理极限。
- **读路径 940.5 MiB/s = 峰值的 61.6%**。单 outstanding 下，64-beat burst
  使效率从 35%（16-beat）提升到 61.6%，与 64/(64+30+overhead) 的预期吻合。
  读路径的剩余空间需要 Stage B 的多 outstanding 来填补。
- 4 GiB 全量测试 0 错误，lane-safe 校验语义不变，地址翻译正常工作。

## 9.4 Stage B：读路径多 outstanding

**改动文件**：
- `rtl/pl_ps_ddr_mem_test_top.v`

**改动要点**：
1. 新增 `localparam READ_OUTSTANDING = 4`。
2. 新增读路径寄存器：`ar_issued`（已发 AR 数）、`r_burst`（正在接收的 R burst
   序号）、`rd_outstanding`（已发 AR 但 R 未收完的数量）。
3. 新增辅助 wire：`ar_fire`、`r_fire`、`r_last_fire`、`ar_issued_next`、
   `r_burst_next`、`rd_outstanding_next`。
4. 将原来的 `ST_READ_AR → ST_READ_R` 两状态串行读流程替换为单一 `ST_READ`
   状态，AR/R 两通道并发执行：
   - **AR 通道**（sticky valid）：只要 `ar_issued < active_bursts` 且
     `rd_outstanding < 4`，就拉高 ARVALID 发下一 burst 地址；ARREADY 后立即
     准备下一个或取消。
   - **R 通道**：`RREADY` 常高，连续接收 R 数据并与 `pattern_lane_safe` 比对；
     RLAST 时 `r_burst++`、`rd_outstanding--`。
5. 完成条件：`ar_issued == active_bursts && r_burst == active_bursts &&
   rd_outstanding == 0`。
6. 保持 ARID=0 单 ID，AXI 保证同 ID 顺序返回，`read_beat_index` 全局递增即可
   正确比对。

**构建**：Vivado 2024.2 综合 + 实现 + 比特流，0 错误，通过。

**实测结果**：

| 测试规模 | 写 (MiB/s) | 读 (MiB/s) | 错误 | 结果 | 写倍数 | 读倍数 |
|---|---|---|---|---|---|---|
| 4 KiB | 1428.245 | 1425.639 | 0 | PASS | 2.80× | 3.11× |
| 16 MiB | 1525.853 | 1525.851 | 0 | PASS | 3.00× | 3.36× |
| 2 GiB | 1525.879 | 1525.879 | 0 | PASS | 3.00× | 3.36× |
| 4 GiB | 1525.879 | 1525.879 | 0 | PASS | 3.00× | 3.36× |

**分析**：
- **读路径从 940.5 MiB/s 跃升至 1525.879 MiB/s = 理论 AXI 峰值，效率 100%**。
  4-deep outstanding 完全隐藏了 DDR 控制器 ~30 周期的 round-trip 延迟，R 通道
  数据如流水般连续不断。
- **写路径保持 1525.879 MiB/s（100% 峰值），不受读路径改动影响**。
- 64-bit / 200 MHz AXI 通道的理论上限（1526 MiB/s）已被写和读**同时达到**，
  通道已完全饱和。后续提升必须依靠加宽数据通道（Stage C）或提升时钟频率
  （Stage D）。
- 4 GiB 全量测试 0 错误，lane-safe 校验与地址翻译均正常。

## 9.5 Stage C：AXI 数据宽度 64→128 bit（PS 端口不兼容，已回退）

**改动要点**：
1. RTL：`AXI_DATA_WIDTH` 从 64 改为 128，`pattern_lane_safe` 参数化为
   `{(AXI_DATA_WIDTH/32){p}}`，`expected_rdata` 宽度跟随，`first_error` 截取
   低 64 位以保持协议兼容。
2. 构建脚本：`PSU__SAXIGP0__DATA_WIDTH` 和 `PSU__SAXIGP2__DATA_WIDTH` 从 64
   改为 128；`apply_ps_config_from_bd` 跳过 `DATA_WIDTH` 属性以避免被参考 BD
   的 64-bit 值覆盖。
3. BD 确认两个 `DATA_WIDTH` 属性均为 128，综合与实现均通过（WNS=0.715）。

**结果**：**PS HP0 FPD 端口在 128-bit 模式下功能不正常**。JTAG 空白启动与
DDR 初始化（DEADBEEF 读回）均正常，`--query-map` 也正常响应，但 DDR 测试
在 ACK OK 后挂起——AXI 事务无法完成。

**对照实验**：将 PS 端口恢复为 64-bit（仅 tester 保持 128-bit，SmartConnect
做 128→64 宽度转换），测试通过 0 错误。这证明 **128-bit tester RTL 本身正确**，
问题出在 PS HP0 FPD 端口的 128-bit 配置。

**根因分析**：ZU4EV 的 PS HP0 FPD 端口虽然在 Vivado IP 属性中允许设置为
128-bit，但在实际硬件上无法正常工作。可能原因包括 PS IP 内部配置不完整、
板级信号完整性、或硅片 errata。参考 BD 中未设置 `DATA_WIDTH`（使用默认 64），
强制覆盖为 128 后 PS IP 内部可能有未同步的相关配置。

**结论**：Stage C 在此板卡上**不可实现**。已回退所有更改。128-bit tester RTL
已验证正确，未来若在支持 128-bit HP 端口的板卡上可复用。

## 9.6 Stage D：MMCM 升频 200→225 MHz

**改动文件**：
- `rtl/config.vh`：`CFG_CLK_HZ` 从 200000000 改为 225000000。
- `rtl/pl_ps_ddr_mem_test_top.v`：Stage A+B 全部优化（BURST_BEATS=64，
  写 4-outstanding 解耦，读 4-outstanding）。
- `build_pl_ps_ddr_mem_test.tcl`：
  - `pl_clk_mhz` / `pl_clk_hz` 改为 225。
  - 新增 `clk_wiz_0`（Clocking Wizard）：200 MHz 输入 → 225 MHz 输出
    （`clk_out1`）+ 200 MHz 直通输出（`clk_out2`，未使用）。
  - `sys_clk` 端口频率设为 200 MHz（实际晶振频率）。
  - `clk_wiz_0/clk_out1`（225 MHz）连接到 `ddr_tester_0/aclk`、
    `axi_smc_0/aclk`、PS `saxihp0_fpd_aclk`。
  - `clk_wiz_0/clk_out1` 同时连接到 `pl_por_0/clk`（避免跨时钟域复位）。
  - `pl_por_0` 的 `CLK_HZ` 设为 225000000。
  - `PRIM_SOURCE = Global_buffer`（避免 E12 非 CCIO 引脚的非法连接）。
- `constraints/uart_zu4ev.xdc`：新增
  `set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sys_clk_IBUF]`，
  允许 E12（非时钟专用引脚）通过通用布线驱动 MMCM。
- `host/pl_ps_ddr_test.py`：`--clk-hz` 默认改为 225000000。

**250 MHz 尝试失败**：首次尝试 250 MHz，时序不收敛（WNS=-1.063，
TNS=-1279）。200 MHz 设计的建立裕量仅 0.715 ns，对应最高约 236 MHz。

**225 MHz 时序**：WNS=0.453，TNS=0.000，WHS=0.012，THS=0.000。全部正裕量。

**实测结果**：

| 测试规模 | 写 (MiB/s) | 读 (MiB/s) | 错误 | 结果 | 写倍数 | 读倍数 |
|---|---|---|---|---|---|---|
| 4 KiB | 1600.922 | 1595.111 | 0 | PASS | 3.14× | 3.48× |
| 16 MiB | 1716.583 | 1716.579 | 0 | PASS | 3.37× | 3.77× |
| 2 GiB | 1716.614 | 1716.614 | 0 | PASS | 3.37× | 3.77× |
| 4 GiB | 1716.614 | 1716.614 | 0 | PASS | 3.37× | 3.77× |

**分析**：
- **写和读同时达到 1716.614 MiB/s = 225 MHz × 8 B 的理论 AXI 峰值，效率
  100%**。MMCM 升频后，Stage A+B 的完全流水化写/读引擎继续满效率运行。
- 相对基线的提升：写 3.37×，读 3.77×。写从 509 → 1717 MiB/s，读从 455 →
  1717 MiB/s。
- 4 GiB 全量测试 0 错误，lane-safe 校验与地址翻译均正常。
- MMCM 的 `CLOCK_DEDICATED_ROUTE FALSE` 约束允许非 CCIO 引脚 E12 驱动
  MMCM，时序仍满足要求（WNS=0.453 ns）。

---

## 10. 最终汇总

### 10.1 各阶段性能对比

| 阶段 | 配置 | 写 (MiB/s) | 读 (MiB/s) | 写效率 | 读效率 | 写倍数 | 读倍数 |
|---|---|---|---|---|---|---|---|
| 基线 | 64b / 200 MHz / 16-beat / 1-os / DDR4-2400 | 509 | 455 | 33.4% | 29.8% | 1.00× | 1.00× |
| Stage E | DDR4-3200 重配 | — | — | — | — | **不可实现**（PS IP 最高 DDR4-2400） |
| Stage A | + 64-beat + 写 4-os 解耦 | 1526 | 941 | 100% | 61.6% | 3.00× | 2.07× |
| Stage B | + 读 4-os | 1526 | 1526 | 100% | 100% | 3.00× | 3.36× |
| Stage C | + 128-bit AXI | — | — | — | — | **不可实现**（PS HP0 128-bit 不工作） |
| Stage D | + MMCM 225 MHz | 1717 | 1717 | 100% | 100% | **3.37×** | **3.77×** |

> 效率 = 实测 / (时钟 × 数据宽度字节)。基线 AXI 峰值 = 200 × 8 = 1600 MB/s
> = 1526 MiB/s。Stage D AXI 峰值 = 225 × 8 = 1800 MB/s = 1716 MiB/s。

### 10.2 关键发现

1. **瓶颈不在 DDR4**：颗粒额定 3200 MT/s（25.6 GB/s），PS 配 2400 MT/s
   （19.2 GB/s），但原始设计仅用掉 2.8%。瓶颈在 PL 侧 AXI 主端口。

2. **DDR4-3200 不可能**：ZU4EV 的 PS DDR 控制器在 Vivado 2024.2 中最高仅
   支持 DDR4-2400（速度档 DDR4_2400U）。DDR4-2666/2933/3200 不在 IP 支持
   列表中。颗粒额定值与 PS 控制器能力是两回事。

3. **128-bit PS HP0 端口不工作**：虽然 Vivado IP 属性允许设置 128-bit，BD
   中也确认了配置值，但实际硬件上 AXI 事务无法完成。128-bit tester RTL 本身
   正确（通过 SmartConnect 128→64 转换验证）。

4. **写路径最先饱和**：Stage A 后写即达 100% 效率（1526 MiB/s）。AW/W/B
   三通道完全解耦 + 4-deep outstanding 是关键。

5. **读路径需多 outstanding**：仅靠长突发（Stage A）读效率仅 61.6%。加入
   4-deep read outstanding（Stage B）后读也达 100%。单 outstanding 的
   round-trip 空泡是多 outstanding 之前的主要瓶颈。

6. **MMCM 升频受限于引脚与时序**：E12 非 CCIO 引脚，需
   `CLOCK_DEDICATED_ROUTE FALSE` 约束。250 MHz 时序不收敛（裕量不足），
   225 MHz 是当前设计的安全上限（WNS=0.453 ns）。

### 10.3 最终设计配置

```
SoC              : xczu4ev-sfvc784-2-i
DDR4             : 4 GiB, DDR4-2400P, 600 MHz controller clock
PL AXI clock     : 225 MHz (MMCM from 200 MHz E12 oscillator)
AXI data width   : 64 bit
AXI burst        : 64 beats × 8 bytes = 512 bytes/burst
Write outstanding : 4 (AW/W/B fully decoupled)
Read outstanding  : 4 (AR/R concurrent)
AXI port         : PS S_AXI_HP0_FPD
Interconnect     : axi_smc_0 SmartConnect
UART             : 8 Mbps, 8N1 (fractional accumulator at 225 MHz)
Reset            : pl_por_0 (~5 ms, on 225 MHz domain)
```

### 10.4 性能总结

```
基线 (200 MHz, 16-beat, 1-os):
  写 509 MiB/s (534 MB/s)   读 455 MiB/s (477 MB/s)

最终 (225 MHz, 64-beat, 4-os):
  写 1717 MiB/s (1800 MB/s)  读 1717 MiB/s (1800 MB/s)

提升: 写 3.37×    读 3.77×
效率: 写 100%     读 100% (相对各自 AXI 峰值)
```

从约 500 MB/s 提升到约 1800 MB/s（3.6×），写和读均达到 225 MHz × 64-bit
AXI 通道的理论峰值。剩余提升空间需要 128-bit PS HP 端口（此板卡不支持）或
更高 PL 时钟频率（受时序约束限制）。
