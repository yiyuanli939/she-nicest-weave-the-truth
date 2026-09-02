# 关内曲候选(自作)

`compose.py` 用音符数据写死五首循环曲(梭声 / 黄铜机房 / 羊毛与雨 / 齿轮华尔兹 / 静语),输出 `compositions.json`;
`workshop.tpl.html` 是试听台模板(Web Audio 现场合成,`__DATA__` 处嵌入 json),发布为 artifact「静语纹关内曲工坊」。
用户在试听台里给四章指派后贴回结果,再按同一份音符数据离线渲染成 `music/level_N.wav`(渲染器待选定后补,乐器模型与页面里的 JS 一一对应)并填 `game/bgm.gd` `TRACKS`。
`tools/` 不进导出包。
