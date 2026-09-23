# 图片生成记录

生成方式：内置 imagegen；用户提供的餐厅图仅作为新增素材的风格参考。餐厅背景直接使用用户原图的压缩副本。

以下为实际使用的生成提示词。最终游戏素材经过 Godot 离线工具裁切透明留白、统一尺寸和压缩；不改变用户原图内容。

## 通用提示词

```text
Use case: stylized-concept. Asset type: production-ready 2D raster pixel-art game sprite. Input image is STYLE REFERENCE ONLY, do not reproduce the restaurant room. Match its warm amber oak, cream highlights, dark brown outlines, slightly detailed cozy top-down RPG pixel art, front-facing 3/4 overhead camera with horizontal front edges (NOT isometric diamonds). Crisp pixel clusters, simple readable silhouette, no text, no labels, no watermark, no floor, no wall, no props except requested subject. Background must be truly transparent alpha, NOT white or a checkerboard drawing. Keep all sprite edges inside generous transparent margins. 
```

## chef

```text
Create ONE complete uniform 4-column by 4-row animation sprite sheet of a small friendly restaurant chef with white tall chef hat, cream shirt, dark green apron, brown shoes. Exactly 16 equally sized cells on a square 1024x1024 canvas, no grid lines. Each row one direction: row1 front facing down; row2 back facing up; row3 left profile; row4 right profile. Columns idle, left-foot walking step, idle, right-foot walking step. Same identity, size, proportions, consistent foot baseline and center within each cell, no tools or food. Compact 2.5-head-tall game character, approximately 64x80 pixel appearance per character, enlarged with crisp pixels.
```

## customer

```text
Create ONE complete uniform 4-column by 4-row animation sprite sheet of a friendly young restaurant customer with short dark brown hair, muted rust-orange jacket, cream shirt, dark navy trousers, brown shoes. Exactly 16 equally sized cells on a square 1024x1024 canvas, no grid lines. Each row one direction: row1 front facing down; row2 back facing up; row3 left profile; row4 right profile. Columns idle, left-foot walking step, idle, right-foot walking step. Same identity, size, proportions, consistent foot baseline and center within each cell, no tools or food. Compact 2.5-head-tall game character, approximately 64x80 pixel appearance per character, enlarged with crisp pixels.
```

## stove

```text
One isolated cooking station furniture sprite: a compact two-burner iron stovetop built into a warm amber oak counter cabinet, two dark burners on a gray steel top, one small dark frying pan, copper knobs on the front. Front-facing slight top-down RPG view matching the room. Rectangular, wider than tall (object ratio around 1.5:1), all feet visible. Single object centered, no background, no food, no side props. Modest pixel detail readable at 128x96 pixels.
```

## serving_counter

```text
One isolated food serving counter furniture sprite: warm amber oak rectangular cabinet with cream ivory clean countertop, two wood front cupboard doors and dark iron handles. Empty top surface, no food or appliances. Front-facing slight top-down RPG view matching the room. Rectangular, wider than tall (object ratio around 1.5:1), all feet visible. Single object centered, no background or side props. Modest pixel detail readable at 128x96 pixels.
```

## sink

```text
One isolated dish return / sink counter furniture sprite: warm amber oak cabinet, a single inset blue-gray steel sink basin on cream countertop, simple curved silver faucet, two wooden front cupboard doors. Empty sink, no dishes. Front-facing slight top-down RPG view matching the room. Rectangular, wider than tall (object ratio around 1.5:1), all feet visible. Single object centered, no background or side props. Modest pixel detail readable at 128x96 pixels.
```

## table

```text
One isolated small rectangular oak restaurant dining table furniture sprite: warm honey amber wood top with subtle visible wood planks, dark brown border, short sturdy wooden legs. Empty table top. Front-facing slight top-down RPG view, horizontal front edge, NOT diamond isometric. Ratio around 1.45:1. No chair, no place setting, no other objects. Single centered complete object, transparent background. Readable at 112x80 pixels.
```

## chair

```text
One isolated simple honey amber oak dining chair furniture sprite, oriented facing LEFT (the table will be to its left). Slight top-down RPG room camera matching the reference. Visible seat and wooden backrest at its right side, sturdy legs, clean simple shape. No table, no cushion, no character, no other objects. Complete centered object with transparent background. Readable at 48x64 pixels.
```

## meal

```text
Create ONE uniform 2-column by 1-row item state sprite sheet on a wide canvas, two equally sized cells with the same plate at same scale and center. Left cell: an ivory ceramic dinner plate of golden rice topped with one fried egg, tiny green garnish. Right cell: the identical used empty plate with a few brown and green food crumbs. Slight top-down oval view, cozy warm detailed pixel art matching the restaurant. No cutlery, no table, no lettering, no background. Exactly two separated plate states, ample transparent space around each. Each plate readable at 40x28 pixels.
```
## 炉灶与水槽透明底修订

```text
Use case: background-extraction. Edit target: attached furniture image. Preserve ONLY the pixel-art furniture itself unchanged, including faucet/pan, feet, perspective and colors. Remove ALL background, white floor, black backdrop, brown glow, ambient halo, cast shadow, gradient, fog and ground line. Everything outside the hard pixel silhouette of the furniture must be genuinely fully transparent alpha=0, including the space under and between the feet. This is a game sprite cutout, NOT a staged product image. Crisp opaque furniture pixels and transparent canvas only. Keep the entire furniture centered with a narrow transparent border, no text.
```

## 椅子与餐食最终补充约束

```text
Absolutely no outer glow, no floor, no black backdrop. Fully transparent sprite background.
```
