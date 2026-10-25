# GPT 娘动态避让补充包

**本项目是对 [T7moris/GPT-Niang（GPT 娘）](https://github.com/T7moris/GPT-Niang) 的补充与优化。** GPT 娘原作者及项目维护者为 **[T7moris](https://github.com/T7moris)**；原项目贡献者、版权与素材来源完整保留。本仓库新增动态避让插件及组合安装流程，不将 GPT 娘的角色、额度挂件或原有功能归为本仓库原创。

GPT 娘负责角色展示、额度气泡和桌面陪伴；动态插件负责在它挡住输入框时，按实际位置和大小为输入框右侧留出空间。

[下载 Windows 组合包](https://github.com/fxboomflash/GPT-niang/releases/latest) · [查看发行记录](https://github.com/fxboomflash/GPT-niang/releases)

## 包含内容

| 组件 | 版本 | 来源与作用 |
| --- | --- | --- |
| GPT-Niang Windows 挂件 | 1.3.5 | T7moris 与原项目贡献者，原版完整保存在 [vendor/GPT-Niang](vendor/GPT-Niang/README.md) |
| 输入框右侧动态避让插件 | 1.4.6 | 本仓库补充，源码在 [plugins/codex-right-clearance](plugins/codex-right-clearance) |
| 组合安装与停用脚本 | 1.0.1 | 本仓库补充；可复用已有 GPT 娘安装 |

## 优化了什么

- 检测独立 GPT 娘挂件的实时窗口位置、人物大小、朝向及宿主窗口的屏幕缩放，每约 300 毫秒更新一次避让判断。
- 同时识别应用内置宠物与独立 GPT 娘，修复只检测内置宠物而漏掉右下角挂件的问题。
- 桌宠与底部输入框重叠时，只收缩输入框右边缘，并留出约 10 CSS 像素间距；人物移开或隐藏后恢复。
- 对话框位于页面中间时保持原样；侧栏和消息区域不改动，只调整底部输入框右边缘。
- 覆盖同一应用内的 Chat、Work、Codex 输入框。无法安全识别或剩余宽度不足 360 CSS 像素时跳过调整。
- 本地运行，不上传聊天正文或账户数据；日常运行不会关闭或重启 Codex、ChatGPT 或 GPT 娘。

原版挂件没有被修改。其人物与气泡分别缩放、拖动跟随等功能由 GPT-Niang 提供。检测依据为角色容器范围，未逐帧分析图片透明轮廓；挂件展开的额度气泡不纳入人物避让范围。

上传图片或文件后继续避让：附件和多行文字可正常增高，输入框底部锚点与左边缘保持不动；默认隐藏的删除按钮、横向滚动中不可见的附件卡片不会误触发恢复原宽。

## Windows 安装

需要 Windows 10/11 x64、Node.js 22+、Microsoft Store 版 Codex 桌面应用，以及原版 GPT 娘正常运行所需的登录状态。组合包未附带 Node.js 或 OpenAI 客户端。

1. 将整个包解压到准备长期保留的目录。
2. 双击 **[安装补充包.cmd](安装补充包.cmd)**。没有安装 GPT 娘时，调用随包保留的原版安装器；已有安装时复用原安装，不重装或关闭挂件。
3. 正常使用原 Codex 入口。已打开的客户端不会被自动关闭；首次增加本地连接后，在你下次自行正常打开客户端时生效。

已有 GPT 娘但无法自动发现时，可指定其安装记录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Install.ps1 -WidgetInstallation "D:\Apps\GPTNiangUsage\gpt-niang-usage\installation.json"
```

只检查依赖和安装计划，不执行安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Install.ps1 -CheckOnly
```

停用动态避让时运行 **[停用动态避让.cmd](停用动态避让.cmd)**。它恢复输入框原布局、撤销动态插件的启动接入，保留 GPT 娘及其个人设置。卸载原版挂件请使用原作者的停用入口。

## 自己调节避让

**⚙ 避让设置** 是一个可拖动的浮动按钮，首次显示在窗口右上方。按住拖动更换位置，松开后自动保存；切换页面或下次打开客户端会恢复保存的位置，窗口变小时保持在可见范围内。单击按钮打开本地设置窗口，拖动不会误开面板。停用插件时按钮一并移除。

也可以双击根目录的 **[避让设置.cmd](避让设置.cmd)**，或调用插件工具 `open_settings`。

- **自动模式**：继续测量桌宠大小和位置；可调额外间距 0–80 CSS 像素，默认 10。
- **手动模式**：指定底部输入框固定收缩 0–600 CSS 像素；0 恢复原宽，默认 96。剩余宽度不足 360 像素时不执行收缩。
- 拖动滑块后自动保存，约 450 毫秒防抖后由后台读取；无需重启客户端。居中的输入框始终保持原样。
- `configure` 工具也接受 `mode`（`auto` / `manual`）、`gapCssPx`、`manualClearanceCssPx` 及 `buttonPosition`（窗口内位置比例，传 `null` 可重置按钮位置）。设置只保存在本机。

1.4.2 还修复了长对话超过 15,000 个页面元素时扫描报错的问题。语义标记直接查询，Shadow DOM 分批发现，稳定状态无需反复遍历整段历史。

## 本地启动接入

这是一项实验性本地适配，不是 OpenAI 官方宿主 UI 扩展接口。动态插件通过当前用户的 Windows 应用包启动接入点，为原进程配置仅本机调试连接，再继续运行同一进程。它不替换客户端启动脚本、不修改客户端安装文件或原数字签名，也不需要专用桌面快捷方式。

启动注册位于当前用户 `HKCU\Software\Microsoft\Windows\CurrentVersion\PackagedAppXDebug`，只针对已验证的 Codex 应用包；本地数据与编译的辅助组件位于 `$CODEX_HOME/plugin-data/codex-right-clearance-v3`（未设置时使用用户目录下的 `.codex`）。调试连接是本地控制通道；停用会撤销本插件注册。应用包更新、窗口布局或挂件画布变化后可能需要重新适配。

## 验证范围

当前 Windows 实机已验证右下角 GPT 娘的动态避让，手动 64 / 120 CSS 像素收缩均精确生效，恢复自动后连续 35 次采样正常，输入框左边缘和高度不变。已验证设置按钮真实点击可打开面板；拖动、位置恢复、窗口缩放、点击与拖动区分、停用移除由 10 项浏览器回归及实际后台代码联动覆盖。长对话回归使用 60,000 个历史页面元素复现旧版故障并验证修复。

原有启动加载器曾从正常入口完成重启验证；1.4.6 本次以热更新方式安装，未再次执行完整冷启动验收。125% 屏幕缩放已实测，混合 DPI 多显示器尚未实机验收；动态补充插件未适配 macOS。组合安装脚本通过语法、只读预检查与隔离测试，没有为了打包而重新安装或关闭正在运行的应用。更新记录见 [CHANGELOG.md](CHANGELOG.md)。

## 署名与许可

- **GPT-Niang 原作者及维护者：T7moris。** 原仓库：[T7moris/GPT-Niang](https://github.com/T7moris/GPT-Niang)。完整贡献致谢见[原项目 README](vendor/GPT-Niang/README.md#致谢与许可)。
- **动态避让与组合安装：本仓库新增补充。** 目的为改善 GPT 娘遮挡输入框的体验；并非原作者官方发布，也不代表原作者或 OpenAI 对本补充包背书。
- 代码和一般文档分别保留 [本仓库 MIT 许可](LICENSE)及[上游 MIT 许可](vendor/GPT-Niang/LICENSE)。
- **角色图片不属于 MIT 授权范围。** 保留[原素材声明](vendor/GPT-Niang/gpt-niang-usage/assets/CHARACTER-NOTICE.txt)、[生成说明](vendor/GPT-Niang/gpt-niang-usage/assets/生成说明.md)和[语录许可](vendor/GPT-Niang/gpt-niang-usage/assets/quotes-LICENSE.txt)。随本项目的非商业副本展示和分发须遵循这些声明；商业用途另行取得相关权利人许可。

上游版本、下载来源和校验记录见 [UPSTREAM.json](UPSTREAM.json)。本仓库不分发个人安装记录、账户额度快照、聊天截图、认证文件或开发机器的运行日志。
