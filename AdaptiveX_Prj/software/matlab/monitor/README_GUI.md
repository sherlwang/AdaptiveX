# 界面接口说明

真实板端入口为 `jiemian`，UDP264、网络和统计说明见 `README.md`。直接创建 `LinkQualityMonitor` 可作为独立显示界面，供其他采集程序使用：

```matlab
app = LinkQualityMonitor;
app.startMonitoring();
sample = struct('P',4,'M',2,'IQ',[-3-3j;1+1j]/sqrt(10), ...
    'MERdB',30.2,'BER',0,'TotalBits',1e6);
sample.ElapsedSeconds = app.ElapsedSeconds;
app.updateMeasurement(sample);
```

| 字段 | 要求 |
| :--- | :--- |
| P | 2、4、8或NaN |
| M | 0=BPSK、1=QPSK、2=16QAM或NaN |
| IQ | 有限数值向量，I+jQ，与单位功率参考星座同标尺；可为空 |
| MERdB | 有限实数或NaN缺测 |
| BER | 0～1实数或NaN缺测 |
| TotalBits | 可选，累计正整数比特数；BER=0时用于1/N显示标记 |
| ElapsedSeconds | 可选，本会话内的测量时间，非负、不能晚于当前时刻或倒退 |

Rx采集器额外提交 `FrameID`（本批最后的uint32来源帧号）、`FrameIDs`（本批每包标签列向量）、`PacketCount`和 `ProtocolVersion`。这些标签不是UDP序号；BER仍为接收区间累计值。

`app.Running`、`app.ElapsedSeconds`、`app.LastMeasurement`、`app.Rates`和历史 `RunTimes/MERHistory/BERHistory` 为公开只读状态。无采集器时首次供数可自动开始；会话结束后提交忽略，重新开始或reset后才接受新数据。

- `app.startMonitoring()`：清空历史，从0计时；有采集器时同时打开UDP。
- `app.stopMonitoring()`：先显示待提交数据，冻结画面和时钟，关闭UDP。
- `app.reset()`：停止采集，清空显示，恢复等待状态。
- `delete(app)`或关闭窗口：释放采集、显示计时器及端口。

独立刷新间隔约0.1秒，趋势保留最近60秒。坐标范围可以跟随数值改变，主窗口尺寸未变时图表和绘图区的位置大小保持固定。改变主窗口尺寸时重新安排布局；窄窗口按纵向排列并支持滚动。

MATLAB忙于长循环时需由调用方通过drawnow、pause或回调返回让界面处理事件。测量时间仅用于曲线定位，不重置会话时钟。
