# KontextLab 3.0 · Research workspace

Live: https://hallodongyue-lang.github.io/kontextlab/

New in3.0: multi-dimensional corpus filters; context comparison with initial/final judgments; disagreement and entropy; real research aggregates; CSV/JSON exports; private records, per-review rationale consent, withdrawal and owner deletion.

See [RESEARCH.md](RESEARCH.md) for protocol, export definitions and limitations. The backend research SQL extends the existing V2.2 schema; apply `backend/research.sql` then `backend/research-seed-metadata.sql`. Do not rerun the original schema against an existing database.

# KontextLab V2.2 — Context Commons

在线：https://hallodongyue-lang.github.io/kontextlab/

德语语境公开共建智库。GitHub Pages 托管前端，Supabase 托管共享数据库、账户与注册服务。

## 已实现

- 投稿原文、上下文、释义、建议主标签和可选附加标签；TXT / 单条 JSON 辅助填写。
- 公开待审区：每账户每条语料一票、禁止自审、需填写判断依据。
- 至少 5 票、单个标签 ≥60% 自动入库。分母包括“不建议入库”；未参与不计。入库时锁定后续票数。所有判断在数据库事务内执行。
- 已入库语料显示点赞、评论；单账户每语料一个赞，可取消；可删除自己的留言。
- 模糊语料独立入口，支持检索、分类与分页。
- 邮箱仅作私有登录名，不验证邮箱归属。注册通过 kl-register Edge Function 创建账户，可立即登录；无需 SMTP。暂不提供邮件密码找回。
- 个人介绍、提交/入库/研判数量、贡献星级与进度条。
- 星级门槛：0 / 1 / 5 / 15 / 30 / 60 条已入库语料对应 0–5 星；评论、点赞和投票不增加星级。
- 德/英/中文界面、明暗主题；用户原文和释义不自动翻译。
- 原 V1 独立标注实验室保留于“独立标注实验室”入口，仍在浏览器本地保存，其实验界面保持中文。

初始 40 条原创虚构案例由编辑精选入库，没有社区投票。投票标签是社区研究共识，不是平台官方裁决或事实真值。

## 运行与文件

精简发布版为上一级目录 KontextLab-v2.2.html，部署时命名为 index.html；源码开发版为本目录。

开发：`python3 -m http.server 4173 --directory outputs`，打开 `http://localhost:4173/KontextLab-v2.2.html`。

`vendor/supabase.js` 为固定 2.102.0 版本的 Supabase 浏览器客户端；线上精简版从固定版本 CDN 加载，旧标注实验室从本仓库固定提交读取。config.js 仅含可公开的 publishable key，没有服务端密钥。数据库服务端密钥只使用 Supabase Edge Function 的内置环境变量。

## 后端

schema.sql 是基础结构；backend/no-email-confirmation.sql 是免邮件确认注册增量。公开匿名账户只能读公开资料与公开/待审语料；无法直接写审核状态、投票、点赞与评论表。受控 RPC 检查当前账户、所有权与限额。

管理员需由站点所有者在可信后台明确指定，不会将第一个注册者自动设为管理员。管理员表位于非公开 schema kl_private.admins。指定后可访问 #admin 处理举报、下架或重新研判；重新研判会清空旧票并记录后台日志。当前尚未指定管理员账户。

为避免数据泄漏和刷量：投稿每账户每日 10 条、研判每日 100 条、留言每小时 20 条；注册按服务器处理的来源 IP 和登录名做 HMAC 哈希限额（每来源每日 10 次、每登录名每日 3 次），原始地址不写入限额表。这不保证识别真实独立个人，也不能完全抵御多账户操纵。

公开展示名与介绍，请勿填写隐私。用户输入以文本转义展示。社区上传内容无需人工操作即可在共识通过后公开，管理员仍需持续维护。共享数据通过刷新按钮重新获取，不是实时推送。当前前端一次加载上限 1000 条；更大规模应改为服务器分页及聚合接口。

## 验证

数据库事务测试（最终回滚）覆盖：自审拒绝、四票不入库、重复投票拒绝、恰好 3/5 自动通过、2/5 与否决票保持待审、评论所有权、赞切换、非管理员拒绝、管理员下架/重开和直接写权限拒绝。

真实 HTTP 链路测试覆盖：免邮件确认注册并立即登录、个人资料初始化、投稿、自审拒绝、点赞/取消、留言/删除、个人资料修改、禁止直接改审核状态、退出登录。测试账户及投稿已清理。

界面验证包括德/英切换、明暗切换、8 条模糊样本、详情与评论输入。星级门槛与进度、字典完整性、输出转义和旧版保留已做代码检查。未做真实多人标注实验，也未确认真实 iPhone/Android 的设备兼容性。


## V2.1：热门话题与公开下线

- 首页热门 Hashtag：近 7 天真实研判记录与语料主题关联的次数排行，最多 10 个主题。同一条研判会为该语料的每个 Hashtag 增加一次关联；并非全网热度或独立人数。无真实研判时不展示虚构排行。
- 投稿可填自定义 Hashtag，也会提取原文中的 #主题，按小写去重；含建议分类标签共最多 8 个，每个最多 32 字符。Hashtag 仅是主题元数据，不等于经过共识确认的分类。
- 点赞与点踩互斥，一账户一条态度，再次点击可撤销。点踩需选择原因：语境不足、分类争议、低质量或其他。
- 至少 5 个账户表态且 点踩数 /（点赞数+点踩数）严格大于 60% 后，数据库自动转为 withdrawn。3/5 不下线，4/6 下线。
- 下线专区公开原文、上下文、原分类、下线时间、触发时的正负票数与比例、原因分布。态度票冻结，评论仍可继续；正式语料库与热门榜排除下线语料。管理员安全下架 hidden 与社区下线 withdrawn 分开。
- 管理员重新研判时清空此前审核票和态度票；不自动恢复被社区下线的语料。
- UI：星环 SVG 包围标题，霓虹青/紫/品红与网格背景，保留三语和明暗主题。

数据库增量：backend/cyber-community.sql。已通过事务测试：Hashtag 提取去重、严格 60% 边界、下线快照、冻结表态、下线评论、7 天热门统计及过期排除、非法主题拒绝、服务端写权限控制。全部测试最终回滚，没有留下测试账户或虚构下线语料。浏览器验证详情输入、关闭交互、点踩入口与空下线区。

## V2.2：新手指南、原文引用与星云

- 新账户第一次登录自动进入五步指南，可稍后再看，也可从顶部问号或侧栏重新进入。登录用户进度写入个人资料，只能由本人更新；访客可预览。完成指南不会增加贡献星级。
- 五步涵盖个人资料、阅读语境、投稿、独立研判、赞踩评论与贡献星级；每步提供实际页面入口。
- 首页只引用维特根斯坦的德文原句：Die Grenzen meiner Sprache bedeuten die Grenzen meiner Welt.
- 出处：Ludwig Wittgenstein, Tractatus Logico-Philosophicus, 5.6。原文核对来源：https://www.gutenberg.org/files/5740/5740-pdf.pdf#page=146 。
- assets/word-nebula.jpg 是内置 image_gen 生成的词云星云。CSS 将其置于底层、暗化并覆盖低透明度遮罩，不卡住按钮、不覆盖正文。浅色主题采用浅色遮罩。生成提示词见 assets/word-nebula.prompt.txt。原始 PNG 与网页压缩 JPEG 一并保留。
- GitHub Pages 发布目录是仓库根目录：index.html + assets/word-nebula.jpg。由 main 分支更新自动触发 Pages 部署。

## 数据库应用顺序

基础 schema.sql → backend/no-email-confirmation.sql → backend/cyber-community.sql → backend/onboarding.sql。只对全新环境按顺序执行，不要在已有项目重复执行。当前连接的 KontextLab Supabase 项目已应用这些变更。

## 本次验证

指南步数、跳过/重进、三语说明与访客进度已检查；数据库事务验证了新账户默认进度、本人进度与完成状态保存、禁止更新他人进度、拒绝越界步骤。原有核心统计和下线逻辑检查继续通过。
