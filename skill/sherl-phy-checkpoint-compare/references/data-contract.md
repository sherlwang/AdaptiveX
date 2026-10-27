# 1. 打包 I/Q 读取

接口：

```matlab
[iq, meta] = read_iq(path, nmeta, width, lanes);
```

每个非空数据行包含 `nmeta` 个数值元数据，随后是两列定长十六进制字符串，分别表示 I、Q。列间用空白分隔，无表头、逗号或 `0x` 前缀；不接受 X/Z 等未知值。单路 `width` 为 4 的正整数倍，范围 4～52；`lanes` 和 `nmeta` 为正整数。调用者先检查参数满足这些约定。该函数使用 double，不能用于更宽单路整数的位精确比较。

- 每列 I/Q 长度必须为 `lanes * width / 4` 个十六进制字符，保留前导零。
- lane 0 放最低位；返回第 1 行为 lane 0，依次类推。
- 每个 lane 按 `width` 位二进制补码解码。
- `iq` 是 `lanes × 数据拍数` 复数矩阵；`meta` 是 `数据拍数 × nmeta`。
- 函数仅解码整数，没有施加小数位缩放、饱和、去导频或重排。
- 调用者检查原始文件行数、列数和采样数；不要仅以函数成功返回证明全文件已正确解析。

例如每拍 2 路、每路 16 位，元数据为时钟与帧号：

```text
100 0 0002ffff fffe0003
101 0 0004fffd fffc0005
```

```matlab
[iq, meta] = read_iq('capture.txt', 2, 16, 2);
% iq = [-1+3j, -3+5j; 2-2j, 4-4j]
% meta = [100, 0; 101, 0]
```

若整数含 `F` 位小数，另算 `value = iq / 2^F`。原始十六进制打包值用于位序审计，补码整数用于整数对照，缩放数值用于算法和 MER 对照，三者不要混用。

# 2. 最小帧账本

账本由输入真值确定，不由 Rx 已输出哪些帧反推。字段名称可以沿用项目已有格式，至少表达：

```json
{
  "input_sha256": "the common input hash",
  "frames": [
    {
      "frame_id": 0,
      "source_interval": [1000, 3200],
      "expected": true,
      "expected_samples": 2048,
      "observed_samples": 2048,
      "status": "recovered",
      "bit_errors": 0,
      "mer_matlab_db": 35.2,
      "mer_hdl_db": 35.1
    },
    {
      "frame_id": 1,
      "source_interval": [3200, 5400],
      "expected": true,
      "expected_samples": 2048,
      "observed_samples": 0,
      "status": "missing",
      "bit_errors": null,
      "mer_matlab_db": null,
      "mer_hdl_db": null
    }
  ]
}
```

这些数值只是格式示例，不是任何 PHY 的固定参数。区间采用何种单位、是否包含滤波支持、端点是否含末点需随项目声明。复位导致的允许丢弃区间也需有事先明确的接口语义。

汇总不能只算已恢复帧：上例应是 2 个应恢复帧、1 个已恢复帧、1 个缺失帧，不能写“BER=0、全部通过”。额外或重复输出另列；部分输入帧不替代缺失的完整帧。

# 3. bit 与 MER 口径

bit 比较保留预期和实测总长度、有效位宽、比较位数、错误位数、元数据错误及首个差异。比较整数打包值时先按约定有效宽度建立掩码；掩码不能掩掉错误的有效宽度声明。软信息另外检查符号、缩放和数值误差。

直接 MER 使用同一批、同一排列的参考符号 `s` 和实际符号 `y`：

$$
\mathrm{MER}=10\log_{10}\frac{\sum |s|^2}{\sum |y-s|^2}
$$

分别计算 MATLAB、HDL 对同一理想星座的 MER，再给出差值；HDL 对 MATLAB 输出的误差比另行命名。按约定排除导频或无效 lane，并记录范围；不要把样本数、缩放、导频范围的变化误当成性能差异。完美一致得到正无穷时保留该含义，不自行加 `eps` 限定结果。

零整数差异说明对应的定点参考一致，不自动证明浮点性能达到要求。量化影响需要使用已声明格式和项目精度要求解释。
