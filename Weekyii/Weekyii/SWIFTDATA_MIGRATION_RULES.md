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

## CloudKit 上线后的追加约束

1. V7 是首个 CloudKit-compatible 基线；V1–V7 均视为已发布历史，禁止原地修改。
2. 新增持久化字段或实体必须创建 V8、V9 等新版本，并补齐上一生产版本到当前版本的真实文件迁移测试。
3. 同步实体不得使用 SwiftData `unique`，非可选属性必须有默认值，关系必须可选并声明 inverse，删除规则不得使用 `deny`。
4. 已部署到 CloudKit production 的 Record Type 和字段只允许追加；不得删除字段、改字段类型或复用旧字段表达新语义。
5. 业务唯一性由 `DataInvariantRepairService` 收敛。新增稳定业务键时，必须同时提供重复记录合并测试，并证明不会丢失子对象。
6. Schema 变更先在 CloudKit development 环境与同账号双真机验证，确认后再部署到 production；部署后再上传对应 TestFlight 构建。
