# 图片素材与替换说明

## 本轮变化

- 用户提供的“餐厅内部-无绿植版.png”用作完整背景，原图不覆盖、不修改。
- 背景压缩为 1216×521 WebP；保持原图约 2.334:1 的宽高比例，无裁切、无拉伸。
- 新增像素风主角、顾客、炉灶、出餐台、回收台、餐桌、椅子与餐食图片。
- 地板、墙面和原有收银台已经画在用户的整张背景中，本轮不再用 TileMapLayer 重铺，避免改变原图。
- 删除原有 `pixel_art.gd` 与餐厅脚本里的图形绘制。角色、家具和餐食均使用真实图片纹理。
- 使用 `Sprite2D`、`AnimatedSprite2D` 和独立 `.tscn` 场景，编辑器内可直接查看和摆放。

## 资源规范

| 路径 | 规格 | 用途 |
|---|---|---|
| `assets/backgrounds/restaurant.webp` | 1216×521 | 完整餐厅背景 |
| `assets/characters/chef.png` | 256×352；4×4 帧；单帧 64×88 | 主角四方向图片动画 |
| `assets/characters/customer.png` | 256×352；4×4 帧；单帧 64×88 | 顾客四方向图片动画 |
| `assets/furniture/stove.png` | 128×96 | 烹饪台 |
| `assets/furniture/serving_counter.png` | 128×96 | 出餐台 |
| `assets/furniture/sink.png` | 128×96 | 餐盘回收台 |
| `assets/furniture/table.png` | 128×90 | 餐桌 |
| `assets/furniture/chair.png` | 56×70 | 朝左的椅子 |
| `assets/items/meal.png` | 80×28；两帧 40×28 | 成品餐食与脏餐盘 |

所有游戏图片单文件必须小于 **400,000 字节**，比 400 KiB 的限制略严格。背景优先无损 WebP；透明素材使用 PNG。原始生成大图不进入 Git 仓库，也不会被游戏引用。

图片采用最近邻采样，不启用 mipmap。角色脚底是定位基准，家具底部是定位基准；图片尺寸与碰撞形状分开管理。

## 怎么替换图片

### 家具

1. 打开 `scenes/furniture/` 中对应场景。
2. 更换 `Sprite2D.texture`，或者在原路径放入同规格新 PNG。
3. 若图片尺寸改变，调整图片位置，使底部仍对齐场景原点。
4. 用 `CollisionShape2D` 调整地面占地，不必让碰撞覆盖整张图片的高度。
5. 用 `InteractionPoint` 调整玩家站立交互的位置。
6. 用 `ItemMount` 调整食物或餐盘显示在台面上的位置。

在主场景拖动整个家具实例即可同时移动图片、碰撞和交互点；不要只移动图片节点。

### 主角和顾客

打开 `scenes/actors/player.tscn` 或 `customer.tscn`。图片显示放在独立的 `Avatar` 子场景内，移动和服务行为留在角色脚本中。

动画资源是 `assets/characters/chef_frames.tres` 和 `customer_frames.tres`，可以在 Godot 的 SpriteFrames 面板编辑。命名约定为：

- `idle_down/up/left/right`：站立。
- `walk_down/up/left/right`：行走。
- `carry_down/up/left/right`：搬运，当前复用行走帧并叠加手持餐食图片。
- `work_down/up/left/right`：工作，当前复用静止帧，后续可以单独替换。

本轮不声称已完成独立烹饪动作和专用端盘动作；这些状态已预留可替换的动画入口。

### 餐食

`meal.png` 左帧是成品，右帧是用过的餐盘。角色的 `Avatar/HeldItem` 与家具的 `ItemMount/Item` 共享此图片资源。保持两帧规格即可替换，不必修改订单逻辑。

### 背景与路径

背景放在主场景的 `Background` 节点中。墙体和原收银台碰撞放在 `Boundaries` 下；`Entrance` 标记顾客入口，`CustomerRoute` 下的标记控制当前单桌顾客路线。

更换为布局不同的背景时，需要同步调整这些碰撞和路径标记。新增桌子的 `Seat` 控制当前顾客座位，但仍是阶段一的单桌固定路线，不是通用寻路。

原图里画好的收银台不能作为独立家具移动；如果后续要升级或搬动它，需要另做背景净版和收银台独立图片。

## 压缩与检查

`tools/prepare_assets.gd` 是离线素材整理工具，接收一个 JSON 源文件路径表。只用于制作最终小尺寸素材，游戏运行不需要原始大图，也不会现场处理图片。

```sh
godot --headless --path . --script tools/prepare_assets.gd -- /path/to/source-manifest.json
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_assets.gd
```

路径表使用 `background`、`chef`、`customer`、`stove`、`serving_counter`、`sink`、`table`、`chair`、`meal` 作为键。背景可单独整理，其他键可以按需提供。

自动检查覆盖：文件体积、Godot 导入、透明边角、角色动画资源、家具碰撞与随家具移动的交互点。视觉效果仍需用实际运行画面检查。

生成方式与完整提示词见 [图片生成记录](image-prompts.md)。

## 本次交付体积

| 文件 | 字节数 |
|---|---:|
| `assets/backgrounds/restaurant.webp` | 48,052 |
| `assets/characters/chef.png` | 120,858 |
| `assets/characters/customer.png` | 121,554 |
| `assets/furniture/stove.png` | 15,747 |
| `assets/furniture/serving_counter.png` | 13,327 |
| `assets/furniture/sink.png` | 19,324 |
| `assets/furniture/table.png` | 12,876 |
| `assets/furniture/chair.png` | 4,052 |
| `assets/items/meal.png` | 4,561 |

合计 **360,351 字节（约 360.4 KB）**；最大单张约 121.6 KB。

本地验证：服务规则 416 项、场景集成 22 项、图片资源 120 项，合计 **558 项检查通过**。另已查看烹饪、搬运与上菜后的真实渲染画面。
