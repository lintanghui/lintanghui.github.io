---
layout: post
title: 源码阅读之cluster（一）基本结构及gossip
category: cache
keywords: redis，cache，cluster
---


##  cluster基本结构
### clusterNode 
clusternode定义如下
```
typedef struct clusterNode {
    mstime_t ctime;  // 该node创建时间
	char name[CLUSTER_NAMELEN]; // 40位的node名字
	 // node 状态标识通过投CLUSTER_NODE 定义。
	 // 包括  maser slave self pfail fail handshake noaddr meet migrate_to null_name 这些状态
	int flags;     
	// 本节点最新epoch
	uint64_t configEpoch; 
	// 当前node负责的slot 通过bit表示
    unsigned char slots[CLUSTER_SLOTS/8]; 
    int numslots;   
    int numslaves; 
	struct clusterNode **slaves; 
	// 如果该node为从 则指向master节点
    struct clusterNode *slaveof; 
    mstime_t ping_sent;      /* Unix time we sent latest ping */
    mstime_t pong_received;  /* Unix time we received the pong */
    mstime_t fail_time;      /* Unix time when FAIL flag was set */
    mstime_t voted_time;     /* Last time we voted for a slave of this master */
    mstime_t repl_offset_time;  /* Unix time we received offset for this node */
    mstime_t orphaned_time;     /* Starting time of orphaned master condition */
    long long repl_offset;      /* Last known repl offset for this node. */
    char ip[NET_IP_STR_LEN];  /* Latest known IP address of this node */
	int port;                   /* Latest known port of this node */
	
	clusterLink *link;          
	// 将该节点标记为失败的node list
	// 节点收到gossip消息后，如果gossip里标记该节点为pfail则加入改list
	// 比如：节点a向b发送gossip，消息包含了 c 节点且出于pfail，则a将被加入c的link。
    list *fail_reports;         
} clusterNode;
```
### clusterMsgData 节点间消息协议
clusterMsgData定义了节点间通讯的数据结构
包含了 ping fail publish update四种类型
 ping消息定义为
 ```
  struct {
        /* Array of N clusterMsgDataGossip structures */
        clusterMsgDataGossip gossip[1];
    } ping;
 ```
 节点间通过ping保持心跳以及进行gossip集群状态同步，每次心跳时，节点会带上多个clusterMsgDataGossip消息体，经过多次心跳，该节点包含的其他节点信息将
 同步到其他节点。

 ### clusterState集群状态
 定义了完整的集群信息
 ```
 struct clusterState{
	// 集群最新的epoch，为64位的自增序列 
	uint64_t currentEpoch;
	// 包含的所有节点信息
	dict *nodes; 
	// 每个slot所属于的节点，包括处于migrating和importinng状态的slot
	clusterNode *migrating_slots_to[CLUSTER_SLOTS];
    clusterNode *importing_slots_from[CLUSTER_SLOTS];
	clusterNode *slots[CLUSTER_SLOTS]; 
	// 当前节点所包含的key 用于在getkeysinslot的时候返回key信息
	zskiplist *slots_to_keys;
	...   
 }
 ```
 redis启动，判断是否允许cluster模式，如果允许，则调用clusterInit进行cluster信息的初始化。clusterState被初始化为初始值。
 在后续节点meet及ping过程逐步更新clusterState信息。

 ## Gossip实现
 ### Send Ping
 节点创建成功后，节点会向已知的其他节点发送ping消息保持心跳，ping消息体同时会携带已知节点的信息，
 并通过gossip同步到集群的其他节点。
 ``
 #### Ping节点选择
 * ping周期  

node的ping由clusterCron负责调用，服务启动时，在serverCron内部会注册
clusterCron，该函数没秒执行10次，在clusterCron内部，维护着static变量iteration记录该函数被执行的次数
通过if (!(iteration % 10)){}的判断，使得node每秒发送一次心跳。

* ping节点选择  
ping节点选择的代码逻辑如下
```
void clusterCron(void)
{
	// ...
	// 如果没有设置handshake超时，则默认超时未1s
	handshake_timeout = server.cluster_node_timeout;
    if (handshake_timeout < 1000)
        handshake_timeout = 1000;

	// 遍历nodes列表
	while ((de = dictNext(di)) != NULL)
    {
		//  删除handshake超时的节点
        if (nodeInHandshake(node) && now - node->ctime > handshake_timeout)
        {
            clusterDelNode(node);
            continue;
		}
		// 如果该节点的link为空，则为该节点新建连接，并且初始化ping初始时间
		if (node->link == NULL)
		{
		// 如果该节点处于meet状态，则直接发送meet让节点加入集群
		// 否则发送向该节点发送ping
		clusterSendPing(link, node->flags & CLUSTER_NODE_MEET ? CLUSTERMSG_TYPE_MEET : CLUSTERMSG_TYPE_PING);
		}
		// 函数每被调动10次，则发送一次ping，因此ping间隔为1s
		if (!(iteration % 10))
    	{
		int j;
		for (j = 0; j < 5; j++)
        {
			// 随机选取节点并过滤link为空的以及self
            de = dictGetRandomKey(server.cluster->nodes);
            clusterNode *this = dictGetVal(de);
            if (this->link == NULL || this->ping_sent != 0)
                continue;
            if (this->flags & (CLUSTER_NODE_MYSELF | CLUSTER_NODE_HANDSHAKE))
				continue;
			
			// 挑选距离上次pong间隔最久的节点
			// redis会尽量选择距离上次ping间隔最久的节点，
			// 以此防止随机不均匀导致某些节点一直收不到ping
            if (min_pong_node == NULL || min_pong > this->pong_received)
            {
                min_pong_node = this;
                min_pong = this->pong_received;
            }
        }
	}
}
```
redis挑选node发送ping的时候，会优先给新加入的节点发送ping，其实再选择最久没被更新的节点，
通过对旧节点选择的加权，尽可能地保证了集群最新状态的一致。

 #### Gossip携带节点选择
 每次ping请求，node会从已知的nodes里面随机选取n个节点（n=1/10*len(nodes)&& n>=3）,一段时间后，该节点已知的nodes将被同步到集群的其他节点，
 集群状态信息达成最终一致。具体实现代码如下（只列出部分代码，完整代码见cluster.c/clusterSendPing）
 ```c
 void clusterSendPing(clusterLink *link, int type)
{
	// 选取1/10 的节点数并且要求大于3.
	// 1/10是个魔数，为啥是1/10在源码里有解释
	int freshnodes = dictSize(server.cluster->nodes) - 2;	
	 wanted = floor(dictSize(server.cluster->nodes) / 10);
    if (wanted < 3)
        wanted = 3;
    if (wanted > freshnodes)
		wanted = freshnodes;
	while (freshnodes > 0 && gossipcount < wanted && maxiterations--)
    {
	// 通过随机函数随机选择一个节点，保证所有节点尽可能被同步到整个集群
	dictEntry *de = dictGetRandomKey(server.cluster->nodes);
	clusterNode *this = dictGetVal(de);
	// 为了保证失败的节点尽可能快地同步到集群其他节点，
	// 优先选取处于pfail以及fail状态的节点
	if (maxiterations > wanted * 2 &&
    !(this->flags & (CLUSTER_NODE_PFAIL | CLUSTER_NODE_FAIL)))
    continue;
	}
	// 如果被选中的节点处于
	// 1.handshake 并且noaddr状态
	// 2.其他节点没有包含该节点的信息，并且该节点没有拥有slot
	// 则跳过该节点并且将可用的节点数减1，以较少gossip数据同步的开销
	if (this->flags & (CLUSTER_NODE_HANDSHAKE | CLUSTER_NODE_NOADDR) ||
    (this->link == NULL && this->numslots == 0))
	{
    freshnodes--; /* Tecnically not correct, but saves CPU. */
    continue;
	}
}
 ```
 通过随机选取合适数量的节点，以及对节点状态的过滤，保证了尽可能快的达成最终一致性的
 同时，减少gossip的网络开销。

 ### Receive Ping
 cluster监听cluster 端口，并通过clusterAcceptHandler接受集群节点发起的连接请求， 
 通过aeCreateFileEvent将clusterReadHandler注册进事件回调里面，读取node发送的数据包。
 clusterReadHandler读取到完整的数据包后，调用clusterProcessPacket处理包请求。
 clusterProcessPacket包含收到数据包后完整的处理逻辑。
 ```
 int clusterProcessPacket(clusterLink *link)
{
	// 判断是否为ping请求并校验数据包长度
	if (type == CLUSTERMSG_TYPE_PING || type == CLUSTERMSG_TYPE_PONG ||
        type == CLUSTERMSG_TYPE_MEET)
    {
        uint16_t count = ntohs(hdr->count);
        uint32_t explen; /* expected length of this packet */

        explen = sizeof(clusterMsg) - sizeof(union clusterMsgData);
        explen += (sizeof(clusterMsgDataGossip) * count);
        if (totlen != explen)
            return 1;
	}	
	// ...
	
	// 是否为已知节点
	sender = clusterLookupNode(hdr->sender);
    if (sender && !nodeInHandshake(sender))
    {
		//  比较epoch并更新为最大的epoch
		if (senderCurrentEpoch > server.cluster->currentEpoch)
            server.cluster->currentEpoch = senderCurrentEpoch;
        /* Update the sender configEpoch if it is publishing a newer one. */
        if (senderConfigEpoch > sender->configEpoch)
        {
            sender->configEpoch = senderConfigEpoch;
            clusterDoBeforeSleep(CLUSTER_TODO_SAVE_CONFIG |
                                 CLUSTER_TODO_FSYNC_CONFIG);
        }
	}
	// 回复pong数据包
	clusterSendPing(link, CLUSTERMSG_TYPE_PONG);

	// 获取gossip消息并处理gossip请求
	if (sender)
    clusterProcessGossipSection(hdr, link);
}
 ```
clusterProcessGossipSection 读取携带的gossip node内容，并判断这些node是否failover

```
void clusterProcessGossipSection(clusterMsg *hdr, clusterLink *link)
{
	// ...


	if (flags & (CLUSTER_NODE_FAIL | CLUSTER_NODE_PFAIL))
{
    if (clusterNodeAddFailureReport(node, sender))
    {
        serverLog(LL_VERBOSE,
                  "Node %.40s reported node %.40s as not reachable.",
                  sender->name, node->name);
    }
    markNodeAsFailingIfNeeded(node);
}
else
{
	// 如果该node并非出于fail状态，则从fail link里删除该node
    if (clusterNodeDelFailureReport(node, sender))
    {
        serverLog(LL_VERBOSE,
                  "Node %.40s reported node %.40s is back online.",
                  sender->name, node->name);
    }
}
}
```

```
int clusterNodeDelFailureReport(clusterNode *node, clusterNode *sender)
{
	while ((ln = listNext(&li)) != NULL)
    {
        fr = ln->value;
        if (fr->node == sender)
            break;
	}
	if (!ln)
	return 0;
	// 如果之前被标记为失败，则从失败list里删除
	listDelNode(l, ln);
}
```

cluster会根据收到的gossip包里的msgdata来更新集群的状态信息，包括epoch，以及其余节点的状态。
如果node被标记为pfail或fail，则被加入fail_reports，当fail_reports
