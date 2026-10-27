# 登录与首次上传

## 1. 仓库

本项目使用 [sherlwang/AdaptiveX](https://github.com/sherlwang/AdaptiveX)，仓库已由作者建立。发布 Skill 不重建仓库、不更改公开状态或许可证。

## 2. 一次性登录

使用 GitHub 官方 CLI：

```bash
gh auth login --hostname github.com --git-protocol https --web
```

如果 CLI 位于缓存，使用其完整路径。按提示打开 GitHub 登录页并输入临时设备码；账号密码、验证码和授权均由用户在 GitHub 页面完成，不把访问令牌发送到对话。认证由 CLI 保存在用户凭据存储中，不复制到 Submission。

发布脚本为 Git 子进程配置 CLI 认证助手，不需要运行全局 `gh auth setup-git`。已有 Git 署名沿用；没有时，独立发布仓库使用已认证账号的公开名称和 GitHub noreply 地址，不改全局身份。

## 3. 首次测试与最终提交

在 Submission 根目录：

```bash
# 测试上传，创建预发布
python3 skill/sherl-github-project-publish/scripts/publish_submission.py --preview --push

# 同事完成材料后，上传正式版
python3 skill/sherl-github-project-publish/scripts/publish_submission.py --push
```

仅本地准备使用 `--plan`；此选项不联网发布。上传后的实际结果存于 `~/.cache/adaptivex-publish/receipts/`，不混入作品材料。

## 4. 完整工程下载

打开仓库 README 中的本版 Release，或使用随仓库提供的 `receive_submission.py`。下载所有 ZIP 分包及 `submission-manifest.json` 后恢复到新目录，脚本逐文件检查 SHA-256。仓库自带的源码 ZIP 不包含完成态运行树。

GitHub 普通 Git 文件与 Release 附件有不同大小限制，本项目使用 Release 承载完整工程，不要求安装 Git LFS。

- [GitHub CLI 登录](https://cli.github.com/manual/gh_auth_login)
- [GitHub 大文件说明](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)
- [Release 附件限制](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
