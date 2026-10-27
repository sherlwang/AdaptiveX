# AdaptiveX 交付与 GitHub 使用

## 1. 本地总目录

当前总目录为 `/home/sherl/Projects/Competition/FPGA嵌入式设计大赛/AdaptiveX_Submission`。

| 内容 | 本地入口 | GitHub 交付 |
|---|---|---|
| 完成态工程及结果 | `AdaptiveX_Prj/` | 源输入可浏览；完整 Tx/Rx 运行树在 Release |
| PS 工作区 | `vitis_workspace/` | 原样放入完整 Release |
| Skill | `skill/` | 可浏览，并包含在完整 Release |
| 代码包 | `adaptivex_code.rar` | 可直接下载，并包含在完整 Release |
| 技术文档 | `technical_report.docx`、准备好的 PDF | 可浏览或下载，并包含在完整 Release |
| 作品全貌、开发板图片 | 根目录图片 | 可浏览，并包含在完整 Release |
| 视频、签字授权书、poster | 根目录对应文件 | 不上传 |
| 内部交接说明 | 作者自用 | 不上传 |

出于核心技术保护考虑，本次提供部分功能代码；技术文档及演示中的性能结果来自源工程。

发布使用现成材料，不重新生成硬件或改动报告。尚未放入的 PDF、图片不会被伪造为空文件；同事补齐后再次执行即可加入。最终上传前，由作者确认对应网站要求的材料已经备齐。

## 2. 一次上传

仓库为 [sherlwang/AdaptiveX](https://github.com/sherlwang/AdaptiveX)。在 Submission 根目录：

```bash
python3 skill/sherl-github-project-publish/scripts/publish_submission.py --push
```

试通上传加 `--preview`，正式提交不加。脚本先检查登录及仓库权限，再选择文件、生成分包、提交 Git、上传并核对附件，最后发布 Release。登录方法见[首次使用](github_first_upload.md)。

同事交回的目录放在相同位置时无需改命令；放在其他位置时添加 `--source /path/to/AdaptiveX_Submission`。缓存、独立发布仓库和执行结果保存在 `~/.cache/adaptivex-publish/`，不随材料公开。Skill 不自动安装。

## 3. 获取完整工程

仓库 README 顶部固定指向本版 Release。完整交付文件包含：

- `submission-001.zip` 等独立 ZIP 分包。
- `submission-manifest.json`：各分包及全部文件的大小、SHA-256、权限和相对位置。

使用仓库中的恢复脚本，将 `TAG` 换成本版实际标签：

```bash
python3 skill/sherl-github-project-publish/scripts/receive_submission.py \
  --repo sherlwang/AdaptiveX --tag TAG --output /path/to/AdaptiveX_Submission
```

目标目录须为空。恢复脚本下载所有分包并校验，再按原路径还原文件；不会向已有工程中覆盖文件。每份 ZIP 可单独打开，但应全部下载并恢复，以获得完整交付。

GitHub 自带的 `Source code (zip)` 只包含仓库页面文件，不能代替完成态工程附件。完整工程入口为 `AdaptiveX_Prj/Tx/project/tx.xpr` 和 `AdaptiveX_Prj/Rx/project/rx.xpr`。原生 Vitis 工作区在 `vitis_workspace/`；两端匹配 XSA 和已验证的软件重建入口仍见工程内 `software/board/README.md`。

## 4. 代码 RAR

代码 RAR 从同版工程源输入和必要依赖提取，排除生成运行树、原生 IDE 缓存和根目录媒体。源码、ROM/MEM/COE、BD/XCI/XDC、必需 hook、网表及仿真依赖均按用途保留。

导出入口：

```bash
python3 skill/sherl-github-project-publish/scripts/export_code.py export \
  --source . --output /path/to/adaptivex_code
python3 /path/to/adaptivex_code/skill/sherl-github-project-publish/scripts/export_code.py verify \
  --directory /path/to/adaptivex_code
```

再在导出目录使用支持写入 RAR 的工具压缩，测试归档并解压校验。ZIP 改后缀不是 RAR。发布脚本只上传已准备好的代码包，不自动重新提取或替换它。代码包内 `SOURCE_EXPORT.json` 记录源文件选择和哈希。

## 5. 更新与记录

预发布标签以 `preview-` 开头，正式版以 `submission-` 开头，后接公开文件内容指纹。不同内容创建新版本，不移动旧标签或覆盖已发布附件。正式版发布完成后设置为 latest；试传保留 prerelease 标记。

上传后的本地记录包含 Git 提交、Release 地址和附件核验值。Git 已推送而附件尚未完成时，记录会明确指出，不能宣称整套交付完成。重复执行可继续匹配的未完成发布；发现人工改动、错误仓库或摘要冲突时保留实际状态并停止。
