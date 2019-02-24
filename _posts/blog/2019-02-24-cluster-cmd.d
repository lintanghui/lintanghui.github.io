## cluster 管理命令及实现

### cluster管理

#### cluster reset
```
cluster reset [hard|soft]
```
cluster reset 分为soft reset和hard reset，不指定的情况下为soft
执行reset后：
1. 所有节点会被forget
2. 所有已指派过的slot会被释放清空
3. node会变更为master
4. nodes.conf 文件会被更新并且cluster state被修改
5. 如果node是slave，数据会被flush
6. (hard) 生成新的nodeid
7. (hard) epoch 被重置为0

#### cluster bumpepoch
```
cluster bumpepoch 
```
这是一个redis的隐藏命令。bumpepoch检查执行命令的节点当前的epoch,并与集群的最大epoch比较，如果当前
节点的epoch为0，或者小于集群的maxEpoch，则将集群的epoch加1，并且节点的configEpoch设置为等于currentEpoch。

#### cluster info 
```
cluster info
```
获取当前节点的集群信息，
包括集群状态 slot分配状态 epoch。

### node管理

#### cluster meet
```
cluster meet ip port
```

cluster meet 进行节点间的握手，握手成功后，新节点加入到集群。
```
if (!strcasecmp(c->argv[1]->ptr, "meet") && c->argc == 4)
{
	// 校验ip port正确后开始进行握手
	if (clusterStartHandshake(c->argv[2]->ptr, port) == 0 &&errno == EINVAL)
}
```
```
int clusterStartHandshake(char *ip, int port)
{
	// ... ip port 合法性校验
	{
		 // ip 不合法，返回EINVAL
        errno = EINVAL;
        return 0;
	}
	// 已经处于握手中，返回错误 EAGAIN
	if (clusterHandshakeInProgress(norm_ip, port))
    {
        errno = EAGAIN;
        return 0;
	}
	// 创建cluster node对象
	n = createClusterNode(NULL, CLUSTER_NODE_HANDSHAKE | CLUSTER_NODE_MEET);
    memcpy(n->ip, norm_ip, sizeof(n->ip));
	n->port = port;
	// 将新的node加入到集群。
	// 此时，cluster state的node列表该节点还是处于handshake状态，只有后续心跳同步到其他节点后才会更新节点状态
    clusterAddNode(n);
}
```
clusterAddNode只是把node加入到cluster->nodes的map中
并且flags被设置为handshake|meet。clusterCron任务会向该新节点发起tcp连接，并通过心跳gossip发送meet状态指令，
发送玩meet后，meet flags会被清空。meet flag被清空后，下一次心跳降发送ping指令，当收到pong响应后，如果该节点还处于
handshake，则handshake flags将被清空，节点成功加入cluster。

#### cluster nodes
nodes 返回集群所有的节点信息,通过clusterGenNodeDescription生成node 信息的描述
包括 nodeid ip:port slots 信息

### slot管理
#### cluster flushslots
清空该节点所有已分配的slots，删除node的slot信息。

#### cluster addslots|delslots
```
cluster addslots [slot] ...
cluster delslots [slot] ... 
```
添加删除slot只是简单地更新node的slot标记位，唯一需要注意的是，如果添加的slot处于importing状态
因为该node已经拥有了这个slot，因此需要清空这个slot的importing状态。

#### cluster setslot
```
SETSLOT 10 MIGRATING <node ID>
SETSLOT 10 IMPORTING <node ID>
SETSLOT 10 STABLE
SETSLOT 10 NODE <node ID>
```
cluster setslot 用于在集群节点间的dlot迁移。setslot命令只能在master节点上执行。
migrating将当前节点的slot迁移到nodeid，
```
if (!strcasecmp(c->argv[3]->ptr, "migrating") && c->argc == 5)
{
	// 必须在当前节点执行
    if (server.cluster->slots[slot] != myself)
    {
        addReplyErrorFormat(c, "I'm not the owner of hash slot %u", slot);
        return;
	}
	// nodeid 必须是已知的节点
    if ((n = clusterLookupNode(c->argv[4]->ptr)) == NULL)
    {
        addReplyErrorFormat(c, "I don't know about node %s",
                            (char *)c->argv[4]->ptr);
        return;
	}
	// 添加migrating节点到migrating slots当中
    server.cluster->migrating_slots_to[slot] = n;
}
```
* importing将slot从目标节点nodeid导入到当前节点，相应的该slot不应该属于当前节点。  
* stable回滚slot的迁移状态，清除migrating和importing的标识。 
* node将slot指派给nodeid所在节点，完成指派之前，需要判断当前slot是否还有key，如果还有，则无法完成slot的指派。
如果当前节点的slot之前处于importing状态，则需要更新epoch，以便slot的更新信息更新为最新的version同步到整个集群。

