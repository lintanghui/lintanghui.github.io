---
layout: post
title: 使用clumsy模拟网络延迟
category: network
keywords: network,wiresharp,clumsy,delay,2016
---
## 为何模拟网络延迟
- 由于最近打算做及时对战类的游戏，对于及时对战类的游戏，首先要解决的问题就是网络延迟的问题。网络延迟对于游戏的体验至关重要。那么开发一款网络游戏要怎么解决这一问题呢。
- 想要解决网络延迟，首先就要模拟网络延迟。那么在开发的过程中如何模拟网络的延迟并找到对应的解决方案呢？

## 如何模拟网络延迟
- 在开发过程中，网络环境往往是在本机上模拟多个客户端或者在局域网内的多台机器上模拟多个客户端，本机通信以及局域网的网速都很快，很难出现网络延迟的情况。这时就需要我们自己去模拟网络延迟的情况了。
- 模拟网络延迟，我使用的是clumsy这个工具。使用clumsy可以人为地在本地机器上造成网络延迟的情况。

### clumsy使用方法

#### 延迟本地数据包
- 在开发的时候，我们往往会在本地搭建一个服务器，此时只要打开clumsy，在过滤条件中设置为如下

![本机延迟](https://github.com/lintanghui/lintanghui.github.io/blob/master/images/delay.png?raw=true)

- 通过lag选项可以设置延迟时间，需要注意的是，由于监听的是本地的数据包，数据发送和接收都会被监听，因此如果设置lag的delay为50ms，实际造成的延迟将是100ms。
- 还可以通过设置其他选项设置其他的网络过滤条件。

#### 本机模拟多个客户端不同延迟
- 上面提到的方法会对进出服务器的数据造成人为的延迟。那么如果我们需要的是模拟多个客户端，每一个客户端的延迟不一样呢。使用clumsy照样可以在本机上模拟这一环境。
- 首先先使用抓包工具[wiresharp][1]获取客户端与服务端通信的端口。
- 在此例子中，服务端监听本地的8888端口。（192.168.64.211为内网地址）然后开启两个客户端与服务端进行连接通信。通过wiresharp抓包可以获取如下信息

![wiresharp抓包](https://github.com/lintanghui/lintanghui.github.io/blob/master/images/tcpcatch.png?raw=true)

- wiresharp的过滤条件为 
```
ip.src==192.168.64.211 and ip.dst==192.168.64.211
```
- 在wiresharp设置这一过滤条件，wiresharp会捕获192.168.64.211上的所有数据包.需要注意的是，由于捕获的是本机的数据包，需要添加本地的路由，具体如何设置参考[使用wiresharp监听本地通信][1]

- 由抓取到的数据包可以看到，客户端与服务端的通信端口分别为24287和24289.知道客户端的通信端口后，就可以对指定客户端进行延迟模拟了。
- 现在对使用端口为24789的客户端开启延迟模拟。对指定端口设置延迟可以通过设置过滤条件为tcp.DstPort==port来进行设置。([更多clumsy过滤设置][2])
![客户端延迟](https://github.com/lintanghui/lintanghui.github.io/blob/master/images/clientdelay.png?raw=true)

- 通过上面的设置后，在本地的两个客户端与本地的服务端通信就可以出现不同的延迟情况了。这样就可以很方便地在本地模拟网络对战游戏中不同客户端延迟的情况了。

[1]:http://lintanghui.com/2016/01/18/localhost-by-wiresharp.html
[2]:https://reqrypt.org/windivert-doc.html#divert_iphdr