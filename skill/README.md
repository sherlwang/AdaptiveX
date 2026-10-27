# 独立开发 Skill

## 1. 内容

| Skill | 用途 |
|---|---|
| [sherl-vivado-resource-baseline](sherl-vivado-resource-baseline/SKILL.md) | 层级资源与时序基线 |
| [sherl-phy-checkpoint-compare](sherl-phy-checkpoint-compare/SKILL.md) | TB/ILA 数据与 MATLAB 对照 |
| [sherl-vivado-source-audit](sherl-vivado-source-audit/SKILL.md) | 源文件、初始化数据和外部依赖清点 |
| [sherl-vivado-netlist-delivery](sherl-vivado-netlist-delivery/SKILL.md) | 网表、功能模型与严格工程绑定 |
| [sherl-github-project-publish](sherl-github-project-publish/SKILL.md) | Submission 一次上传、完整工程 Release 与远端核验 |

## 2. 使用

每项以本目录内的 `SKILL.md` 为入口，辅助脚本和参考资料随各 Skill 独立保存。它们不参与 AdaptiveX 工程构建，也未自动安装。运行示例中的相对命令时，先进入相应 Skill 目录。

本次工程包、代码 RAR 与 GitHub 范围选择见 [AdaptiveX 交付与上传说明](sherl-github-project-publish/references/adaptivex_upload.md)。`AdaptiveX_Prj/MANIFEST.json` 用于工程清单核对；根目录原生 `vitis_workspace/` 的复制一致性单独记录。代码 RAR 按同版源输入与必要依赖选择，保留所选文件和工程对应文件的哈希关系。本项目发布使用独立工作目录，一次完成仓库页面内容与完整 Release 的更新；不自动安装 Skill。

## 3. 提炼来源

[协作案例](collaboration.md)保留本项目中需求核对、Vitis 可移植性和发布文件一致性三类实际问题，包含用户提示词、模型回答或处理摘要、纠正过程与验证范围。案例与各 Skill 的适用说明配合阅读。
