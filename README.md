# 一人食堂 · Chanting

Godot 像素风餐厅经营游戏。已实现四桌营业、两道菜、独立烹饪小游戏、员工自动工作，以及阶段 4.1 的跨日资金和日结账本。

![阶段三实际运行画面](docs/stage-3-preview.webp)

## 运行

使用 Godot 4.7.1 打开 `project.godot`，按 F5 运行。项目使用 Compatibility 渲染器，无第三方插件。中文界面优先使用系统字体（macOS 苹方、Windows 微软雅黑、Linux Noto Sans CJK）。

## 操作

| 按键 | 功能 |
|---|---|
| WASD / 方向键 | 移动 |
| E / 空格 | 靠近工作台、餐桌或污渍交互 |
| Q | 切换待做订单；当前订单带 `▶` 标识 |
| M | 打开员工管理，调整工作开关和优先级 |
| Esc | 暂停 / 继续 |
| F1 | 开关调试信息；调试模式下 N 生成顾客、R 重新开店 |

游戏从“开店准备”开始，点击“开始营业”后才会接待顾客。靠近烹饪台按 E 进入独立小游戏。小游戏中按住空格加热，松开降温，在翻炒游标的绿色区按 F，熟度达到 80 后按 E 出锅；B 可返回餐厅并保留订单。更高的品质会增加付款金额。

## 员工协作

开局有一名员工，默认自动做菜、上菜、收盘和清洁。店内有两个可独立使用的烹饪台，主角与员工可以同时做菜。员工出发前会预留任务；在员工到达并开始执行前，主角可直接接手。员工已开始做菜、拿起菜品或收走餐盘后，任务由员工完成。员工之间仍不能重复领取同一任务。顶部显示员工当前工作和失败原因。按 M 打开管理面板，关闭某项工作或调整优先级；设置在下一营业日继续生效。禁用整名员工后，主角仍可独立完成营业日。正式雇佣和工资在阶段 4.3 加入。

![员工管理界面](docs/stage-3-management.webp)

## 营业规则

- 四张桌子各有独立订单与耐心。顶部订单卡显示菜品、状态和剩余秒数；不足 12 秒会变红。
- 菜品为香煎蛋饭（18 金币）和番茄炒面（24 金币）。炒面制作速度稍慢，锅里的像素表现不同。
- 出餐台最多放两份菜；做菜开工时会预留出餐位置。每个角色一次只能拿一件物品。把菜送错桌会提示，食物不会丢失。
- 顾客等餐超时会离店；制作中、出餐台和手中的失效食物会清理，不会长期占用炉灶或角色。
- 顾客用餐后付款、评价并离店。靠近桌子收盘，送到回收台，桌子恢复可用；地面出现污渍时，空手靠近按 E 清洁。
- 营业 180 秒，随后停止接待新顾客，并给 35 秒收尾。日结显示日初现金、营业收入、各类支出、日末现金，以及接待、评价和员工完成工作数。
- 点击“准备下一营业日”会保留金币、天数和员工安排，并清空当天的订单与任务；“新游戏”经确认后清空全部进度。目前尚未写入磁盘，退出程序后进度不会保留，本地存档安排在阶段 4.4。

## 图片和代码

用户提供的餐厅背景与已生成角色、家具、食物图片独立于规则；单张图片均小于 400KB。员工暂用着色的厨师图片，烹饪锅与地面污渍暂用像素绘制，后续可换图。

- `scripts/day_model.gd`：并行订单、耐心、桌位、统一任务预留、物品交接、付款和日结。
- `scripts/employee.gd`：员工调度、障碍寻路、四类自动工作和异常恢复。
- `scripts/restaurant.gd`：场景、交互、界面与各角色协调。
- `scenes/cooking/`、`scripts/cooking/`：独立做菜界面、规则与临时像素表现。
- `scenes/furniture/`、`scenes/actors/`：可独立替换的家具和角色场景。
- `scripts/service_model.gd`：保留阶段一单桌服务规则作为历史回归样本；当前游戏使用 `DayModel`。

详见 [完整开发计划](docs/development-plan.md)、[阶段 4.1 实现说明](docs/stage-4-1.md)、[阶段三实现说明](docs/stage-3.md)、[烹饪小游戏说明](docs/cooking-minigame.md) 与 [图片替换说明](docs/image-assets.md)。

## 验证

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_service_model.gd
godot --headless --path . --script tests/test_day_model.gd
godot --headless --path . --script tests/test_scene.gd
godot --headless --path . --script tests/test_assets.gd
godot --headless --path . --script tests/test_cooking_model.gd
godot --headless --path . --script tests/test_cooking_screen.gd
godot --headless --path . --script tests/test_employee_model.gd
godot --headless --path . --script tests/test_employee.gd
godot --headless --path . --script tests/test_employee_comparison.gd
godot --headless --path . --script tests/test_multi_day.gd
```

macOS 可将 `godot` 替换为 `/Applications/Godot.app/Contents/MacOS/Godot`。图形环境下运行 `godot --path . --script tests/capture_stage_4_1.gd` 可重新生成阶段 4.1 实际画面。GitHub Actions 对 `main` 的推送自动运行十组测试。

## 分支

`main` 是日常开发主分支；之前的 `feature/` 分支保留为阶段历史。除非明确需要隔离开发，后续直接提交和推送到 `main`。
