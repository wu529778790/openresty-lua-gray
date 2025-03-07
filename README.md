# front-saas-gray

本应用使用 Lua 脚本实现了一种灰度发布策略。

这个 Lua 脚本用于实现灰度发布的功能。脚本首先定义了一个变量 cacheExpireTime，表示缓存数据的过期时间，

然后定义了一个函数 getUserInfo()，用于从 cookie 中获取 userId 和 corpId。

接下来，脚本封装了 Redis 连接函数 connectRedis(dbIndex) 和获取数据函数 getDataFromRedis(redisKey)。

如果缓存字典未定义，则直接从 Redis 中获取数据；否则，先从缓存中获取数据，如果缓存中不存在数据，则从 Redis 中获取数据，并将数据添加到缓存中。

然后，脚本封装了一个函数 checkGray()，用于遍历灰度命名空间列表，检查用户是否属于灰度发布组。

该函数先调用 getUserInfo() 函数获取用户信息，然后从 Redis 中获取灰度命名空间列表，遍历命名空间列表，检查命名空间中的规则列表，遍历规则列表，

根据规则类型匹配要查询的字段，检查是否命中灰度规则，并检查是否在时间范围内。如果命中灰度规则，则函数返回 true，否则返回 false。

最后，脚本检查用户是否属于灰度发布组，如果是，则将请求重定向到 @gray 位置；否则，将请求重定向到 @prod 位置。

## 调用流程

1. 首先调用 `getUserInfo()` 函数从 cookie 获取用户信息（ userId 和 corpId ）。

2. 然后调用 `getDataFromRedis(redisKey)` 函数从缓存中获取数据，如果缓存中不存在，则从Redis中获取数据，获取的键为 "GRAY_NAMESPACE_REDIS"。

3. 遍历灰度规则列表，判断用户是否属于灰度发布组以及是否命中灰度规则。

4. 如果命中灰度规则，则根据规则判断是否在时间范围内，如果在时间范围内则执行灰度发布，否则执行生产环境。

## 流程图

- 从Cookie解析用户身份信息（userId/corpId）
- 连接Redis获取灰度配置数据
- 遍历namespaceList和ruleList进行规则匹配
- 根据规则类型（企业ID/用户ID）进行匹配检查
- 命中规则后检查时间有效性
- 最终路由到灰度或生产环境

需要特别注意的异常处理点：

- Redis连接失败直接走生产环境
- 数据解析失败会终止流程
- 空数组会自动跳过当前循环
- 时间有效性检查包含永久生效（ruleEffect=1）的特殊情况

![灰度发布检查流程图](https://gcore.jsdelivr.net/gh/wu529778790/image/blog/灰度发布检查流程图.svg)
