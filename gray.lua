-- 缓存数据的过期时间（单位：秒）
local cacheExpireTime = 600 -- 设置为 600 秒，即 10 分钟

-- 从cookie中获取 userId 和 corpId
local function getUserInfo()
    local jwt_token = ngx.var.http_cookie and ngx.var.http_cookie:match("cloud.saas.sid=([^;]+)")
    if not jwt_token then
        ngx.log(ngx.ERR, "未能从cookie中提取JWT令牌")
        -- 处理无法提取JWT令牌的情况
        return nil, nil
    end

    local b64 = require "ngx.base64"
    local jwt_data = b64.decode_base64url(jwt_token:match("^[^%.]+%.([^.]+)%."))
    if not jwt_data then
        ngx.log(ngx.ERR, "解码JWT令牌失败")
        -- 处理无法解码JWT令牌的情况
        return nil, nil
    end
    local cjson = require("cjson")
    local data, err = cjson.decode(jwt_data)
    if not data then
        ngx.log(ngx.ERR, "无法解析 JSON 数据: ", err)
        return nil, nil
    end
    local userId = data.userId
    local corpId = data.corpId
    return userId, corpId
end

-- 封装Redis连接函数
local function connectRedis()
    ngx.log(ngx.ERR, 'Redis连接')

    -- 读取 JSON 配置文件
    local cjson = require("cjson")
    local file = io.open("config.json", "r")
    local content = file:read("*a")
    file:close()

    -- 解析 JSON 内容为 Lua 对象
    local config = cjson.decode(content)

    -- 访问配置项
    local redisHost = config.redis.host
    local redisPort = config.redis.port
    local redisPassword = config.redis.password
    local redisDatabase = config.redis.database

    local redis = require("resty.redis")
    local red = redis:new()
    local ok1, err1 = red:connect(redisHost, redisPort)
    if not ok1 then
        ngx.log(ngx.ERR, "无法连接 Redis: ", err1)
        return nil
    end
    local ok2, err2 = red:auth(redisPassword)
    if not ok2 then
        ngx.log(ngx.ERR, "Redis 认证失败: ", err2)
        return nil
    end
    local ok3, err3 = red:select(redisDatabase)
    if not ok3 then
        ngx.log(ngx.ERR, "无法选择 Redis 库: ", err3)
        return nil
    end
    return red
end

-- 封装获取数据的函数
local function getDataFromRedis(redisKey)
    local dict = ngx.shared.cache_dict
    local dataJSON
    local function handlerConnectRedis()
        -- 缓存中不存在数据，从Redis中获取
        local red = connectRedis()
        if not red then
            -- 处理连接到Redis失败的情况
            ngx.log(ngx.ERR, "无法连接 Redis")
            return nil
        end
        dataJSON = red:get(redisKey)
        if not dataJSON or type(dataJSON) ~= "string" then
            -- 处理无法从Redis中获取值的情况
            ngx.log(ngx.ERR, "无法从 Redis 中获取键[", redisKey, "]")
            -- 如果redis没有数据，那么就存一个字符串'dataJSON'
            dict:set(redisKey, 'dataJSON', cacheExpireTime)
            return nil
        end
        ngx.log(ngx.ERR, "dataJSON: ", dataJSON)
        -- 将数据添加到缓存中
        dict:set(redisKey, dataJSON, cacheExpireTime)
        ngx.log(ngx.ERR, "已将键[", redisKey, "]存入缓存")
        local cjson = require("cjson")
        local data, err = cjson.decode(dataJSON)
        if not data then
            ngx.log(ngx.ERR, "无法解析 JSON 数据: ", err)
            return nil
        end
        return data
    end
    if not dict then
        ngx.log(ngx.ERR, "没有缓存，直接从Redis中获取数据")
        return handlerConnectRedis()
    end
    -- 如果缓存是 'dataJSON'
    if dict == 'dataJSON' then
        return nil
    end
    dataJSON = dict:get(redisKey)
    if not dataJSON then
        ngx.log(ngx.ERR, "无法从缓存中获取键[", redisKey, "]")
        return handlerConnectRedis()
    end
    local cjson = require("cjson")
    local data, err = cjson.decode(dataJSON)
    if not data then
        ngx.log(ngx.ERR, "无法解析 JSON 数据: ", err)
        return nil
    end
    return data
end

-- 遍历 grayNamespace.namespaceList 数组
local function checkGray()
    -- 获取用户信息
    local userId, corpId = getUserInfo()
    -- 获取 GRAY_NAMESPACE_REDIS 键对应的值
    local grayNamespace = getDataFromRedis("GRAY_NAMESPACE_REDIS")
    if not grayNamespace then
        ngx.log(ngx.ERR, "无法获取 GRAY_NAMESPACE_REDIS 键对应的值")
        return false
    end
    local cjson = require("cjson")
    grayNamespace = cjson.decode(grayNamespace)
    -- 检查 grayNamespace.namespaceList 的类型和长度
    if type(grayNamespace.namespaceList) ~= "table" or #grayNamespace.namespaceList == 0 then
        ngx.log(ngx.ERR, "grayNamespace.namespaceList 为空或不是一个数组")
        return false
    end
    for i, namespace in ipairs(grayNamespace.namespaceList) do
        -- 检查 namespace.ruleList 的类型和长度
        if type(namespace.ruleList) ~= "table" or #namespace.ruleList == 0 then
            ngx.log(ngx.ERR, "grayNamespace.namespaceList[", i, "].ruleList 为空或不是一个数组")
            goto continue -- 跳过当前循环
        end

        -- 遍历 namespace.ruleList 数组
        for j, rule in ipairs(namespace.ruleList) do
            -- 检查 rule.ruleValue 的类型和长度
            if type(rule.ruleValue) ~= "table" or #rule.ruleValue == 0 then
                ngx.log(ngx.ERR, "grayNamespace.namespaceList[", i, "].ruleList[", j, "].ruleValue 为空或不是一个数组")
                goto continue -- 跳过当前循环
            end

            -- 根据 ruleType 判断要匹配的字段
            local name
            if rule.ruleType == "GRAY_RULE_CORP_ID" then
                name = corpId
            elseif rule.ruleType == "GRAY_RULE_USER_ID" then
                name = userId
            else
                ngx.log(ngx.ERR, "未知的灰度规则类型：", rule.ruleType)
                goto continue -- 跳过当前循环
            end

            -- 检查是否命中灰度规则
            local matched = false
            -- 输出 ruleValue 数组中的所有元素
            for k, v in ipairs(rule.ruleValue) do
                if v == name then
                    matched = true
                    break
                end
            end

            -- 如果命中灰度规则，则检查是否在时间范围内
            if matched then
                if rule.ruleEffect == 0 then
                    -- 如果不是一直生效，则检查开始时间和结束时间
                    local now = ngx.now()
                    local beginTime = rule.ruleBeginTime or 0
                    local endTime = rule.ruleEndTime or now
                    if now >= beginTime and now <= endTime then
                        local cjson = require("cjson")
                        ngx.log(ngx.ERR, "用户 ", userId, " 命中了灰度规则：", cjson.encode(rule))
                        return true
                    end
                else
                    local cjson = require("cjson")
                    ngx.log(ngx.ERR, "用户 ", userId, " 命中了永久灰度规则：", cjson.encode(rule))
                    return true
                end
            end
        end
        ::continue:: -- 定义标签，用于跳过当前循环
    end
    return false
end

-- 检查用户是否属于灰度发布组
local isInGrayRelease = checkGray()

-- 如果用户属于灰度发布组，则执行灰度发布的逻辑
if isInGrayRelease then
    ngx.exec('@gray')
else
    ngx.exec('@prod')
end
