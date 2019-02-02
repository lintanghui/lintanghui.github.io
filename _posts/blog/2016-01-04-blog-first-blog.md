---
layout: post
title: 独立博客搭建
category: tips
keywords: 博客,2016
---

## 域名购买

- 搭建独立博客首先要有一个自己独立的域名，域名可以在域名提供商处购买。在此我选择了从阿里云购买。购买完域名后就是把自己的域名和github的blog地址关联起来了。

## 域名绑定

- 在github个人博客项目下新建一个CNAME文件（文件名必须大写）。文件内容为你自己购买的域名。我购买的域名为lintnaghui.com 。所以CNAME的内容即为lintanguui.com。
- 前往阿里云的域名管理中心进行域名解析。添加如下域名解析记录.

![解析配置](https://github.com/lintanghui/lintanghui.github.io/blob/master/images/cname.png?raw=true)

- 稍等一段时间后，访问lintnaghui.com即可访问懂啊你的个人博客了