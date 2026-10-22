import Foundation

func L(_ english: String) -> String {
    guard Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true else { return english }
    return translations[english] ?? english
}

private let translations: [String: String] = [
    "Create": "创建", "History": "历史记录", "Search": "查询",
    "Version": "版本", "Development": "开发版",
    "selected": "项已选", "Target": "目标", "Source 1": "来源 1", "Source 2": "来源 2",
    "Sources": "来源", "Destination": "目标目录",
    "Drop files or folders here": "拖入文件或文件夹",
    "Click to choose from Finder": "点击以在 Finder 中选择",
    "Drop a destination folder here": "拖入目标文件夹",
    "Creating Links...": "正在创建硬链接…", "Create Hard Links": "创建硬链接",
    "Remove": "移除", "Choose a folder for the destination.": "请选择目标文件夹。",
    "Creating hard links for": "正在创建硬链接：", "Created hard links for": "已完成硬链接：",
    "item": "项", "items": "项", "Could not select sources:": "无法选择来源：",
    "Could not select destination:": "无法选择目标：",
    "History could not be read:": "无法读取历史记录：", "History could not be saved:": "无法保存历史记录：",
    "No completed jobs yet.": "尚无已完成的任务。",
    "Completed": "完成于", "files": "个文件", "Verify": "核验", "Forget": "忘记记录",
    "Forget this record?": "忘记这条记录？", "Only the record is removed. Files stay in place.": "只移除记录，不会删除文件。",
    "Cancel": "取消", "Verified": "核验完成", "Matching files": "匹配文件",
    "Missing": "缺失", "Changed": "已变化", "Extra": "额外文件", "Incomplete": "未完整",
    "Choose file or folder": "选择文件或文件夹", "Choose search folders": "选择搜索文件夹",
    "Search folders": "搜索文件夹", "Recorded locations": "记录中的目录",
    "Add folders": "添加目录", "Search hard links": "查询硬链接", "Scanning...": "正在扫描…",
    "Scanned files": "已扫描文件", "links found": "已找到链接", "total links": "链接总数",
    "Other links may be outside the selected scope.": "其他链接可能位于所选范围之外。",
    "Search was cancelled; results are incomplete.": "搜索已取消，结果不完整。",
    "No hard-linked files found in this folder.": "该文件夹内未发现多链接文件。",
    "No file selected.": "尚未选择文件或文件夹。",
    "Drop a file or folder anywhere here to select it for search.": "将文件或文件夹拖到此页面任意位置，即可设为查询对象。",
    "Search scope is limited to recorded and selected folders.": "仅搜索记录中的目录和本次指定的文件夹。",
    "No recorded locations. Add a search folder to look beyond the selected item.": "暂无记录，请添加搜索文件夹以查找所选项目之外的链接。",
    "Scan warnings": "扫描提示", "Paths": "路径", "No matching files": "没有匹配的文件",
    "Choose at least one source.": "请至少选择一个来源。",
    "The destination is not a folder:": "目标不是文件夹：",
    "The source no longer exists:": "来源已不存在：",
    "The destination cannot be the source folder or inside it.": "目标不能是来源文件夹本身或其子目录。",
    "Two sources would create the same target:": "两个来源会创建相同的目标：",
    "A file or folder already exists at the target path:": "目标路径已存在文件或文件夹：",
    "Could not create hard links for": "无法创建硬链接："
]
