---
name: sherl-github-project-publish
description: 将 AdaptiveX Submission 按已确认范围一次上传到 GitHub，包括源码与文档、完整 Vivado/Vitis 工程附件，并校验远端提交与附件。支持试传、最终提交和同事交回新版本后的更新。
---
# Submission GitHub 发布

## 1. 本项目的上传范围

默认输入为本 Skill 所在的 `AdaptiveX_Submission`，默认仓库为 `sherlwang/AdaptiveX`。工程目录允许 `AdaptiveX_Prj`、`Prj` 或 `prj` 三者之一；其余目录按现有结构使用。

| 上传 | 不上传 |
|---|---|
| 工程与结果、`skill/`、`vitis_workspace/` | 演示视频 |
| 代码 RAR、技术文档 | 授权书、承诺书、poster |
| 作品全貌图、开发板图片 | 内部交接说明、Git 历史、登录凭据 |
| README、LICENSE、必要配置 | 发布工具的缓存与本地工作目录 |

选择规则在 [项目配置](assets/adaptivex_public_files.json)。技术文档和媒体采用同事最终放入的现成文件；发布不修改工程、重跑仿真、生成 bit 或润色 Word。许可沿用提交目录现有文件。

用户调用本 Skill 要求“上传”时，完成检查后直接执行上传，不在已确认范围内重复询问。明确要求只准备或查看时使用 `--plan`。不得扩大公开范围、改变仓库可见性、强推或改写历史。

## 2. 直接执行

维护版位于 `~/Projects/AI_Skills/sherl-github-project-publish`，不自动安装。接到同事最终目录后，先把维护版同步到该目录的 `skill/sherl-github-project-publish`，只更新这项发布 Skill，保留其他 Skill；再使用维护版脚本并显式传入 `--source`。这样不会因同事带回旧版发布工具而退回旧流程。

从维护版调用时的命令：

```bash
python3 ~/Projects/AI_Skills/sherl-github-project-publish/scripts/publish_submission.py \
  --source /path/to/AdaptiveX_Submission --push
```

在 Submission 根目录运行：

```bash
python3 skill/sherl-github-project-publish/scripts/publish_submission.py --push
```

本次仅试通上传时使用预发布：

```bash
python3 skill/sherl-github-project-publish/scripts/publish_submission.py --preview --push
```

同事交回最终目录后，用同一条不带 `--preview` 的命令上传正式版本。目录位置改变时加 `--source /path/to/AdaptiveX_Submission`；不需要手动选择 Git 文件或重新建立仓库。

依赖 Python 3.10+、Git、GitHub 官方 CLI `gh`。脚本优先使用 PATH，其次查找 `~/.cache/adaptivex-publish/cli/`。首次登录见[登录与首次上传](references/github_first_upload.md)。已有认证直接沿用，不在对话、脚本或材料中填写令牌。

## 3. 文件如何交付

仓库页面保存可直接浏览的源码、Skill、报告、图片和代码 RAR。完成态 Tx/Rx 运行树和原生 Vitis 工作区连同其余公开材料，保存为同仓库 Release 的完整 ZIP 分包。每个分包保留原相对路径，单个附件小于 2 GiB。

README 提供本版 Release 和[下载恢复脚本](scripts/receive_submission.py)的入口。完整工程从 Release 恢复；GitHub 自带的源码 ZIP 只包含仓库页面文件。这两种下载方式必须说明清楚。

脚本在 Submission 之外的 `~/.cache/adaptivex-publish/` 准备文件、保存独立发布仓库和执行记录。不要把该工作目录放进 Submission。Git 身份和认证助手仅作用于发布仓库或本次子进程，不改全局 Git 设置。

大附件上传不设置 1 小时截止，上传阶段与收据保存在独立工作目录。

每版按公开文件内容确定标签。先上传 Git 提交和 draft 附件，核对大小、SHA-256 及标签所指提交，再公开 Release；试传标为 prerelease，正式版标为 latest。已上传的相同版本不重复发布，新版保留旧版历史。网络中断后按已完成步骤继续，遇到摘要冲突、错误远端或人工未提交改动时说明实际状态，不覆盖它们。

## 4. 完成判定

返回仓库链接、实际提交 SHA、Release 链接、附件核验结果，以及这是预发布还是正式发布。Git 推送和附件发布是两步；只有两者都完成，才能报告“上传完成”。失败时报告停在哪一步和是否已有部分内容上线。

本次上传成功只证明材料传输和文件一致性，不代替仿真、时序或板测。具体目录、代码 RAR 与接收方使用方法见[AdaptiveX 交付说明](references/adaptivex_upload.md)。旧的通用白名单工具 `scripts/publish.py` 保留给其他小型发布任务，本项目使用上述新入口。
