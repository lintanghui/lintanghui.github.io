---
layout: post
title: go语言中json tag field的使用
category: golang
keywords: golang,json,2016
---

## struct序列化为json
- golang中，struct序列化为json。对应的字段会序列化为key-value格式。
- json序列化的导出规则和golang一样，对于golang中的非导出字段，序列化后被忽略掉。

```
type Message struct {
    Name string
    Age int64
    inner string
}
var input = Message{"lintnaghui", 23, "hello"}
ouput, _ := json.Marshal(input)
fmt.Println(string(output))

output:
{"Name":"lintnaghui","Age":23}
```

## 自定义导出tag
- 序列化的时候还可以通过自定义tag来指定导出字段以及json的key

```
var a int = 1
type jsonData struct {
	Name       string `json:"name"`
	Ignore     string `json:"-"`
	Describe   string `json:",omitempty"`
	Int2String int    `json:",string"`
	Point      *int   `json:"point"`
	Omit       int    `json:"omit,omitempty"`
}
var input = jsonData{"lth", "ignore", "", 1, &a, 2}
ouput, _ := json.Marshal(input)
fmt.Println(string(output))

output:
{"name":"lth","Int2String":"1","point":1,"omit":2}

```

- 对于导出的字段的key值，可以通过`json:"key"`来指定key的值，key的值必须是string。
- 对于指定了omitempty的字段，如果字段的值为nil point，0或者nil interface则该字段被忽略。
- 通过 "," 指定多个tag
- tag字段为 "-"，则该字段直接被忽略
- 还可以通过指定类型对字段的类型进行序列化转换。Int2String指定为string，序列化后的值直接转化为string类型。