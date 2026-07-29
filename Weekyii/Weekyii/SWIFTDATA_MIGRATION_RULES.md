# SwiftData 迁移约束

## 本次事故根因

`WeekyiiSchemaV2`、`WeekyiiSchemaV3` 引用了当前全局模型类型。

新增 V5 字段后，历史 Schema 被同步改变，导致多个迁移阶段生成相同 checksum，真机启动时崩溃：

`Duplicate version checksums across stages detected`

## 强制规则

1. 历史 `VersionedSchema` 必须使用冻结的历史模型，禁止引用当前全局模型。
2. 已发布的 Schema 结构和版本号禁止修改。
3. 新字段只能加入新版本 Schema，并追加迁移阶段。
4. 每次 Schema 变更必须测试所有历史版本到当前版本的持久化迁移。
5. 必须完成真机 arm64 构建和持久化启动验证。
6. 禁止通过删除数据库、删除迁移阶段或跳过版本掩盖迁移错误。
