# iOS Development Guide (Weekyii)

This document defines the engineering standards to build the Weekyii iOS app **entirely offline**.  
It translates the current file-based system (repo data layer + CLI rules) into a local, deterministic iOS implementation with **no networking**.

---

## 1) Scope & Principles

- **Offline-first, local-only**: No network access, no external databases.
- **Deterministic rules**: All behaviors must follow `AGENTS.md` and `README.md`.
- **Conflict resolution**: If this document conflicts with `AGENTS.md`, follow `AGENTS.md`.
- **Single source of truth**: The local file‑database inside the app sandbox (`STATE.md` + `Past/Present/Pending` structure and contents).
- **State machine**: Day/Week states must transition exactly per rules.
- **Auditability**: All changes are file-based and human-readable.

---

## 2) Data Model (Canonical)

Use the canonical structures defined in `AGENTS.md` **as development references**.  
Runtime data lives only in the app’s local file‑database.

### 2.1 Directory Layout (Local App Sandbox)

- `Documents/STATE.md`
- `Documents/Past/YYYY/YYYY-Www/week.md`
- `Documents/Past/YYYY/YYYY-Www/YYYY-MM-DD/day.md`
- `Documents/Present/YYYY/YYYY-Www/week.md`
- `Documents/Present/YYYY/YYYY-Www/YYYY-MM-DD/day.md`
- `Documents/Pending/YYYY/YYYY-Www/week.md`
- `Documents/Pending/YYYY/YYYY-Www/YYYY-MM-DD/day.md`

### 2.2 Data Formats

- `STATE.md`, `week.md`, `day.md` must follow templates defined in `AGENTS.md`.
- No JSON/YAML to replace the canonical files unless explicitly approved.
- All dates are stored as `YYYY-MM-DD`, times as `HH:MM`, weeks as `YYYY-Www`.
- Input dates may be `YY/MM/DD`, `YYYY/MM/DD`, or `YYYY-MM-DD` but must normalize to `YYYY-MM-DD`.

---

## 3) App Architecture

### 3.1 Modules (Suggested)

- `App/`：App 入口与导航协调
- `Core/Models/`：Day / Week / State / TaskItem / Enums
- `Core/Services/`：FileStore / TimeProvider / NotificationScheduler
- `Core/Parsers/`：Markdown Parser / Renderer
- `Core/StateMachine/`：Rollover / Expiry 逻辑
- `Core/Commands/`：CommandEngine / CommandHandlers
- `Core/Validators/`：日期与输入规范化
- `Features/`：Today / Present / Pending / Past / DayDetail
- `UI/`：通用组件、样式、动效

### 3.2 Core Services

- `FileStore`: Read/write the canonical markdown files.
- `TimeProvider`: Current date/time (injectable for tests).
- `StateMachine`: Applies rules from `AGENTS.md` (rollover, expiry, transitions).
- `Parser`: Parse `.md` into Swift models and render back to `.md`.
- `CommandEngine`: Executes “pseudo-commands” in code.

---

## 4) State Machine Rules (Must Match AGENTS.md)

Implement the following in **exact order** before every command execution:

1. **Compare system date vs STATE.md current_date**.
2. **Cross-day processing**:
   - If yesterday = execute and incomplete → expire it.
   - If yesterday = draft and not started → expire (expired_count = 0, clear details).
3. **Cross-week processing**:
   - Move old Present week to Past.
   - If new week exists in Pending → move to Present; else create empty week.
4. **Kill time**:
   - If current time > kill_time and status = execute → expire immediately.

These steps are mandatory before any command changes files.

---

## 5) Command Engine (API Contract)

Each user action must map to the following commands. The command set is **closed**; no extra commands are allowed.

- `weekyii init`
- `weekyii today create -m "..."`
- `weekyii today update -m "instruction"`
- `weekyii today start`
- `weekyii today done focus_zone`
- `weekyii today show -focus_zone/-frozen_zone/-complete_zone/-all`
- `weekyii today change-kill-time -t "HH:MM"`
- `weekyii past show all`
- `weekyii past show precise-day -t "YY/MM/DD"`
- `weekyii pending create precise-day -t "YY/MM/DD"`
- `weekyii pending crate week` (alias of `pending create week`)
- `weekyii pending create week -t "YYYY-Www"`
- `weekyii pending show week -t "YYYY-Www"`
- `weekyii pending show month -t "YYYY-MM"`
- `weekyii past show month -t "YYYY-MM"`
- `weekyii present show week`
- `weekyii present show today`
- `weekyii today copy-to -t "YYYY-MM-DD"`
- `weekyii week copy-day -from "YYYY-MM-DD" -to "YYYY-MM-DD"`

### Output Format

- Success: `[OK] <简短说明>`
- Failure: `[ERR] <原因>`

### Command Semantics (Must Be Exact)

- **weekyii init**
  - Create `Past/Present/Pending` and `STATE.md` if missing.
  - Must not overwrite existing data; if initialized, return `[OK] 已初始化`.

- **weekyii today create -m "..."**
  - Create or edit **today's** Draft task flow.
  - If today is `execute/completed/expired`, return error.
  - Split tasks by newline or `;` / `；`.
  - Task type must be chosen in UI; default to `regular`.

- **weekyii today update -m "instruction"**
  - Draft-only edits with **re-numbering** after changes.
  - Supported edits:
    - Add: `新增：任务A；任务B` (append)
    - Insert: `在第2条前插入：任务X`
    - Delete: `删除：第3条` or `删除：T03`
    - Rewrite: `把第2条改成：任务Y`
    - Reorder: `把第4条移到第1条`
  - If today is not draft, return error.

- **weekyii today start**
  - Draft must exist and be non-empty.
  - Set status to `execute`, record `initiated_at`.
  - Move first task to Focus, others to Frozen.
  - If kill_time is empty, set to `20:00`.
  - Increase `days_started_count` **only once per day**.

- **weekyii today done focus_zone**
  - Move Focus to Complete with `ended_at`.
  - If Frozen has tasks, move next into Focus.
  - If Frozen empty, set day status to `completed` and record `closed_at`.

- **weekyii today show -focus_zone/-frozen_zone/-complete_zone/-all**
  - Read and present the relevant sections of today's `day.md`.

- **weekyii today change-kill-time -t "HH:MM"**
  - Allowed only in `draft/execute`.
  - If current time is already past today's kill_time, return error.

- **weekyii past show all**
  - Output summary for all Past weeks with completed/expired counts only.

- **weekyii past show precise-day -t "YY/MM/DD"**
  - Show a single Past day: completed task details + expired count only.

- **weekyii pending create precise-day -t "YY/MM/DD"**
  - Create the entire week containing the target date in Pending (skip if exists).
  - If the target day already has Draft, keep it.

- **weekyii pending create week -t "YYYY-Www"**
  - Create the specified future week in Pending (skip if exists).

- **weekyii pending crate week**
  - Alias of `pending create week`.

- **weekyii pending show week -t "YYYY-Www"**
  - Show the specified future week summary with each day status.

- **weekyii pending show month -t "YYYY-MM"**
  - Show future month grouped by weeks.

- **weekyii past show month -t "YYYY-MM"**
  - Show past month grouped by weeks; expired details hidden.

- **weekyii present show week**
  - Show the current week's 7-day summary.

- **weekyii present show today**
  - Show `days_started_count` + today's summary + kill_time.

- **weekyii today copy-to -t "YYYY-MM-DD"**
  - Copy today's **Draft** list into target day (only if target not started).
  - If target day doesn't exist, create its week in Pending.

- **weekyii week copy-day -from "YYYY-MM-DD" -to "YYYY-MM-DD"**
  - Copy Draft from source day to target day (target must be unstarted).

### Parameter Validation (All Commands)

- Date input accepts `YY/MM/DD`, `YYYY/MM/DD`, `YYYY-MM-DD` and must normalize to `YYYY-MM-DD`.
- Time input must be `HH:MM` (24h).
- Week input must be `YYYY-Www`.

### Command Execution Order (Mandatory Checklist)

1. Read `STATE.md` and compare with system date/time.
2. Run **State Machine** (cross-day → cross-week → kill_time).
3. Validate parameters and target object existence.
4. Execute command-specific mutations.
5. Update `STATE.md` (`current_*`, `last_rollover_at`).
6. Render and persist modified files atomically.
7. Return output in `[OK]/[ERR]` format.

---

## 6) Behavioral Boundaries & Invariants

- **Present 单周原则**：Present 只能存在当前周一个周文件夹。
- **不可回滚**：`today start` 后不可编辑当日任务流。
- **仅今日可启动**：非当天的 `day.md` 不允许 start。
- **不可跳过 Focus**：`today done focus_zone` 只能完成当前 Focus，不能跨越。
- **过期即遗忘**：过期任务只保留数量，不保留详情。
- **任务类型**：任务类型由用户在 UI 中显式选择（regular/ddl/leisure）；未选择则默认为 regular。
- **kill_time 规则**：
  - 仅 draft/execute 可修改。
  - 当前时间已超过今日 kill_time 时，禁止延长。
  - 若在超过 kill_time 后执行 start，会进入 execute 并立即过期。
- **days_started_count** 仅在“当天首次 start”时 +1。
- **STATE.md** 在每次命令后必须同步更新 `current_*` 与 `last_rollover_at`。
- **参数必须明确**：日期、范围或目标对象不清晰时不得执行，需提示用户补充。
- **today create/update**：
  - 仅在当日为 draft 时允许编辑。
  - 当日为 execute/completed/expired 时必须返回错误。
- **today start**：
  - Draft 列表必须存在且非空。
  - 若 kill_time 为空，默认设置为 20:00。
- **today done focus_zone**：
  - 完成 Focus → 进入 Complete，并记录结束时间。
  - Frozen 仍有任务则下一条进入 Focus；否则当日 completed 并记录 closed_at。
- **today change-kill-time**：
  - draft/execute 可改；completed/expired 不可改。
- **today copy-to**：
  - 仅复制 Draft 任务流。
  - 目标日若不存在，必须创建其所属周到 Pending。
  - 目标日已 start 则拒绝复制。
- **week copy-day**：
  - 仅允许复制未启动的 Draft。
- **pending create precise-day**：
  - 必须创建目标日期所属整周到 Pending。
  - 已存在则跳过，不覆盖已有内容。
- **show 输出**：
  - 必须符合 `[OK]/[ERR]` 规范。
  - 过期任务详情不可在 Past 中展示。

---

## 7) Parsing & Rendering Rules

- **No lossy parsing**: Must preserve order and content.
- **Strict headings**: Use the exact section names from templates.
- **Task IDs**:
  - `T01`, `T02`...
  - Fixed after `today start`.
- **Draft**:
  - Only `Draft_Mission_List` is populated.
  - Other zones must be empty.
- **Execute**:
  - Draft locked; use Focus/Frozen/Complete.
- **Completed**:
  - Focus/Frozen empty, Complete has details, Expired_Summary stays as count.
- **Expired**:
  - Only keep `Complete_Zone` (if completed tasks exist) and `Expired_Summary`.
  - Do not keep details for expired tasks.

---

## 8) iOS App Features

### 8.1 Required Views

- **Today**: current day focus + summary.
- **Present Week**: 7-day overview (status per day).
- **Pending**: future weeks & months.
- **Past**: history with summary only for expired tasks.
- **Day Detail**: complete view of day.md.

### 8.2 Notifications (Local Only)

- Use the system local notification framework.
- Schedule a daily notification at `kill_time`.
- If `kill_time` changes, reschedule.
- No remote notifications.

---

## 9) Swift Coding Standards

### 9.1 Naming

- Types: `UpperCamelCase`
- Methods/vars: `lowerCamelCase`
- Files match type names.
- Enums for state: `DayStatus`, `WeekStatus`.

### 9.2 Error Handling

- Use `throws` with typed errors:
  - `WeekyiiError.dateFormatInvalid`
  - `WeekyiiError.killTimePassed`
  - `WeekyiiError.todayAlreadyStarted`

### 9.3 Dates & Time

- Use the system calendar with fixed locale `en_US_POSIX`.
- Normalize all date inputs to `YYYY-MM-DD`.
- Week start is Monday.

---

## 10) File Access & Persistence

- Use the app sandbox **Documents** directory as the data root.
- Always read/write **entire file** atomically.
- If concurrent writes might occur, use coordinated file access provided by the system.

---

## 11) Testing Strategy

### 11.1 Unit Tests

- Parsing/Rendering: round-trip tests for `.md`.
- State transitions across:
  - start → execute
  - execute → completed
  - execute → expired (kill_time)
  - draft → expired (next day)
- Cross-week moves: Present → Past, Pending → Present.

### 11.2 Snapshot Tests

- Validate `today show -all` output.

---

## 12) App Store Compliance (Offline App)

- No network permissions needed.
- Include local-only privacy policy.
- No analytics or tracking.

---

## 13) Development Checklist

- [ ] Implement file templates exactly.
- [ ] Implement state machine before every command.
- [ ] Validate output format `[OK]/[ERR]`.
- [ ] Ensure local notifications set per kill_time.
- [ ] Confirm app can run fully offline.

---

## 14) Future Extensions (Optional)

- iCloud Drive backup (must be optional, not required).
- Export to Markdown/ZIP for manual backup.

---

## 15) Project Structure Guidance (No Code)

- The app should be layered: App entry → Core → Features → UI → Tests.
- `Resources/Templates` must store the canonical markdown templates copied from `AGENTS.md`.
- `CommandEngine` must be the only entry that mutates files.
- `StateMachine` must run **before** every command.

---

## 16) Parser/Renderer Spec (No Examples)

- Parse headings exactly by name (`# Day:`, `## Draft_Mission_List`, etc.).
- Preserve task order, IDs, labels, and blank lines.
- For `day.md`, only the correct zones are populated based on status:
  - draft → Draft only
  - execute → Focus/Frozen/Complete
  - completed → Complete only
  - expired → Complete (if any) + Expired_Summary only
- Rendering must be stable: parse → render → parse should not change meaning or order.

---

## 17) Local Notification Workflow

### 17.1 Scheduling Rules

- Schedule a **daily** notification at `kill_time` for the current day.
- If `kill_time` changes, cancel and reschedule.
- If day status becomes `completed` or `expired`, cancel same-day notification.

### 17.2 Suggested Implementation

- Use the system local notification framework.
- Notification identifiers should include the date to ensure uniqueness.
- On app launch and whenever `today` changes:
  - Run the state machine.
  - If today is `draft` or `execute`, schedule notification at `kill_time`.

### 17.3 Payload

- Title: `Weekyii`
- Body: `今日任务流到期提醒`
- No sound or badge changes unless user opts in.

---

## 18) Frontend UI Specification (SwiftUI-Aligned)

This section translates the **README.md** product philosophy into iOS UI requirements, while avoiding Swift/SwiftUI pitfalls.

### 18.1 Core UI Principles (From README)

- **Focus-first**: The current task must be unmistakably prominent (single-task focus).
- **Commitment over flexibility**: After `start`, the daily flow is locked; UI must clearly disable edits.
- **Time boundary is visible**: kill_time is always visible on Today screen.
- **Forget the expired**: Past view must not reveal expired task details.
- **Week as the primary unit**: Current week is the main navigation scope.

### 18.2 Required Screens & Hierarchy

- **Home / Today**
  - Shows: days_started_count, today status, kill_time, Focus task.
  - Actions: create/update (draft only), start, done focus, change kill_time.
- **Week Overview (Present)**
  - 7-day list with status badges (draft/execute/completed/expired/empty).
- **Day Detail**
  - For non-today days: view-only; edit only if draft and in current week.
- **Pending**
  - Month/Week navigation to create future week/day.
- **Past**
  - Month view; day detail shows completed tasks only + expired count.

### 18.3 Interaction Rules (UI Must Enforce)

- Disable edit controls when status ≠ draft.
- Disable `start` when Draft is empty.
- Disable `change kill_time` when status ∈ {expired, completed}.
- Do not allow completing non-Focus tasks.
- If current time > kill_time and status = execute, force expire on next UI action.

### 18.4 SwiftUI Behavior Constraints (Avoid Common Pitfalls)

- **Main-thread UI updates only**: File writes must not block UI; update models on main thread.
- **State consistency**: Single source of truth per screen; avoid duplicated derived state.
- **Lifecycle updates**: On app launch/foreground, always run state machine before rendering.
- **Navigation updates**: After a command, re-read the affected files and refresh view state.
- **Long operations**: File operations must be short; if not, show a brief loading indicator.

### 18.5 Visual Language (iOS-appropriate)

- Use system typography and dynamic type; do not hard-code font sizes.
- Prefer native components (lists, sections, toggles) to keep iOS consistency.
- Use clear status chips (draft/execute/completed/expired/empty).
- Keep one primary action per screen to align with “one focus task” philosophy.

### 18.6 Localization & Accessibility

- All user-facing strings are localizable.
- Support VoiceOver for task lists and action buttons.
- Ensure contrast meets iOS accessibility guidelines.
