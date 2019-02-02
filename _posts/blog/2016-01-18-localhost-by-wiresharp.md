---
layout: post
title: 使用wiresharp监听本地通信
category: network
keywords: network,wiresharp,2016
---
## wiresharp 监听本地通信

- 在开发过程中，经常把本机作为服务器和客户端。
- 当把本机当做服务端，又作为客户端时，使用wiresharp抓取通信数据，默认情况下无法抓取到数据。需要对本机路由进行设置。
- cmd以管理员方式启动，然后

```
route add 192.168.64.211 mask 255.255.255.255 192.168.64.1 添加路由管理
格式 ： route add ip mask 255.255.255.255 gateway
```

- 此时重新监听本地通信，即可抓取通信数据。