extends TestBase
## 故事界面美术登记表:每个角色 × 表情 × 遮罩 × 场景都指向真实存在的 PNG(缺图会让立绘无声消失)。


func test_every_registered_art_file_exists() -> bool:
	var ok := true
	for who: String in StoryArt.CHARACTERS:
		ok = check(ResourceLoader.exists(StoryArt.mask_path(who)), "遮罩缺图:%s" % who) and ok
		ok = check(ResourceLoader.exists(StoryArt.portrait_path(who, "默认")), "默认立绘缺图:%s" % who) and ok
	for sc: String in StoryArt.SCENES:
		ok = check(ResourceLoader.exists(StoryArt.scene_path(sc)), "场景缺图:%s" % sc) and ok
	# 美术目前给的表情集合(新图加进来后把这里补上)
	for pair in [["诺拉", "苦恼"], ["诺拉", "严肃"], ["诺拉", "惊讶"], ["莉娅", "苦恼"]]:
		ok = check(ResourceLoader.exists(StoryArt.portrait_path(pair[0], pair[1])), "立绘缺图:%s %s" % pair) and ok
	return ok


func test_lookup_helpers() -> bool:
	return check(StoryArt.is_nora("诺拉·拉弗蒂") and StoryArt.is_nora("诺拉"), "is_nora") \
		and check(not StoryArt.is_nora("莉娅"), "is_nora 否") \
		and check(StoryArt.character_of("亚瑟·威客利夫") == "亚瑟", "character_of 全名") \
		and check(StoryArt.character_of("阿梭") == "", "未登记角色 → 空") \
		and check(StoryArt.portrait_path("莉娅", "不存在的表情") == "", "非法表情 → 空路径") \
		and check(StoryArt.scene_path("工坊").ends_with("scene_workshop.png"), "场景路径")
