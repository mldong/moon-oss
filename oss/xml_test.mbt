///|
// 实体还原与容器切段两族的读数钉。
//
// 两处值得单独钉：① 还原归 hutool（本仓不再自带那张表），对 OSS 真会回的形状逐字相同，
// 但那一件是 `raise` 的，解不动时**整串退回**——这一档不追求与旧的逐条替换实现逐字等价；
// ② 容器切段必须给**未解转义**的段内原文。段内再取叶子时只解一趟；
// 若切段那一步先解一次、取叶子再解一次，键里本身就写着实体形状的对象就会被改字
// （`a&amp;lt;b` 会变成 `a<b`），而那个键还要拿去 copy／delete，等于打错对象。

///|
test "五个基本实体与十进制写法：真端点会回的那些档逐字还原" {
  assert_eq(@oss.xml_unescape("a&#34;b&#34;c"), "a\"b\"c")
  assert_eq(@oss.xml_unescape("&#60;a&#62;"), "<a>")
  assert_eq(@oss.xml_unescape("&amp;amp;"), "&amp;")
  assert_eq(@oss.xml_unescape("&amp;lt;"), "&lt;")
  assert_eq(@oss.xml_unescape("&#38;#34;"), "&#34;")
  assert_eq(@oss.xml_unescape("&nbsp;"), "&nbsp;")
  assert_eq(@oss.xml_unescape("&notanentity;&amp"), "&notanentity;&amp")
}

///|
/// 这一档是 hutool 比旧的本地实现**多认**的：十六进制引用与十进制引用。
/// 记在这儿是为了以后有人说"怎么和多出来的表不一样"时有出处。
test "十六进制与十进制数字引用也解（超集那一档）" {
  assert_eq(@oss.xml_unescape("&#x41;"), "A")
  assert_eq(@oss.xml_unescape("中文&#20013;"), "中文中")
}

///|
/// 已知不等价档，按"不承诺逐 token 回退"记：`&#xD800;` 是落单代理，MoonBit 的 `String`
/// 表示不了它，参照那边能产出一个本库装不下的形状 ⇒ 整串退回原文，而不是把前面解得动的部分
/// 留下（旧实现会给出"一个引号加半截实体"那种一半解一半没解的形状）。
test "落单代理让整串退回，不做逐 token 回退" {
  assert_eq(@oss.xml_unescape("&#34;a&#xD800;"), "&#34;a&#xD800;")
}

///|
/// 写出请求体那一侧（分片完成的文档）。转义是单趟查表：五种字符一次换完，
/// 不会像"逐条 replace_all"那样把刚产出的 `&amp;` 再吃进去。
test "escape 与 unescape 互为逆：五种字符往返一致" {
  let raw = "a<b&c>\"e'f"
  let escaped = @oss.xml_escape(raw)
  assert_eq(escaped, "a&lt;b&amp;c&gt;&quot;e&apos;f")
  assert_eq(@oss.xml_unescape(escaped), raw)
}

///|
/// 容器路径只解一趟。真端点对键 `a&lt;b` 给的是 `<Key>a&amp;lt;b</Key>`：
/// 切段不解、取叶子解一次 ⇒ 得到 `a&lt;b`（服务端存的就是这个字面值）。
/// 若切段先解一次，这里会拿到 `a<b`——那是改字，不是解析。
test "xml_sections 给未解转义的段内原文，容器路径只解一趟" {
  let doc = "<ListBucketResult><Contents><Key>a&amp;lt;b</Key>" +
    "<Size>3</Size></Contents></ListBucketResult>"
  let sections = @oss.xml_sections(doc, "Contents")
  assert_eq(sections.length(), 1)
  if !sections[0].contains("a&amp;lt;b") {
    fail("切段那一步不许先解一趟：" + sections[0])
  }
  assert_eq(@oss.xml_first(sections[0], "Key"), Some("a&lt;b"))
}

///|
/// 一层嵌套里同名标签不能串到下一段去：两行 `Contents` 各取各的 `Key`。
test "两行容器各取各的字段，不按整文顺序配对" {
  let doc = "<Result><Contents><Key>one</Key><Size>1</Size></Contents>" +
    "<Contents><Key>two</Key><Size>2</Size></Contents></Result>"
  let keys : Array[String] = []
  let sizes : Array[Int32] = []
  for section in @oss.xml_sections(doc, "Contents") {
    keys.push(@oss.xml_first(section, "Key").unwrap_or("<none>"))
    let size_text = @oss.xml_first(section, "Size").unwrap_or("0")
    sizes.push(@string.parse_int(size_text.view(), base=10))
  }
  assert_eq(keys, ["one", "two"])
  assert_eq(sizes, [1, 2])
}
