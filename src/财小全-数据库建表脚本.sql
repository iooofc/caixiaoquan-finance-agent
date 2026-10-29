-- ============================================================================
--  财小全 · 财务中枢  数据库结构脚本（v2.1 · 忠实原作挂载链）
--  版本：v2.1   日期：2026-10-14   数据库：MySQL 8.0+
--
--  【模型说明 · 与原演示包一一对应】
--  原作链子（财小全.html 中的 ACCOUNTS / PERMS / attach）：
--    ① 一个自然人在 企业/个人/家庭 三种模式下各有一个「身份」，
--       身份分主账号(main)与子账号(sub)，并挂一个角色标签
--    ② 每个身份有一本「自己的账本」，自己可读写
--    ③ 主账号身份把自己的账本以某个角色「挂载」给子账号身份（attach），
--       子账号获得只读视图，主账号可随时收回
--    ④ 权限按「模式:账号身份」判定（PERMS），技能按权限门控（hasPerm）
--  本脚本把这四条链子落成表：account → account_identity → book / book_share
--
--  规模：21 表 + 4 视图。不设法人与管理员（小微场景，见配置方案）。
-- ============================================================================

DROP DATABASE IF EXISTS caixiaoquan;
CREATE DATABASE caixiaoquan DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE caixiaoquan;

-- ============================================================================
-- 第一部分：账号 · 身份 · 角色 · 权限（对应原作 ACCOUNTS / PERMS）
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. 账号 —— 自然人。王建国是一个账号，不是三个
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS account;
CREATE TABLE account (
  account_id      VARCHAR(32)   NOT NULL                COMMENT '账号ID',
  login_id        VARCHAR(64)   NOT NULL                COMMENT '登录标识（手机号）',
  name            VARCHAR(64)   NOT NULL                COMMENT '姓名/主体名称',
  acct_kind       ENUM('个人','企业','家庭') NOT NULL DEFAULT '个人' COMMENT '账号类型',
  phone           VARCHAR(20)   NULL                    COMMENT '绑定手机号',
  status          ENUM('active','disabled') NOT NULL DEFAULT 'active' COMMENT '状态',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (account_id),
  UNIQUE KEY uk_acct_login (login_id)
) ENGINE=InnoDB COMMENT='账号——自然人或主体，一个账号可在三种模式下各有一个身份';

-- ---------------------------------------------------------------------------
-- 2. 账号身份 —— 核心实体。对应原作 ACCOUNTS[mode] 的每一个条目
--    「企业:operator」「个人:self」「家庭:keeper」…每个都是一个身份
--    身份分主账号(main)/子账号(sub)，并挂一个角色
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS account_identity;
CREATE TABLE account_identity (
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '身份ID（=原作 模式:账号）',
  account_id      VARCHAR(32)   NOT NULL                COMMENT '所属账号',
  mode            ENUM('enterprise','personal','family') NOT NULL COMMENT '模式',
  level           ENUM('main','sub') NOT NULL           COMMENT '主账号/子账号',
  role_id         VARCHAR(32)   NOT NULL                COMMENT '角色',
  display_name    VARCHAR(64)   NULL                    COMMENT '显示名称（如 晨曦科技）',
  elder_mode      TINYINT(1)    NOT NULL DEFAULT 0      COMMENT '是否关怀模式（大字+语音）',
  status          ENUM('active','disabled') NOT NULL DEFAULT 'active' COMMENT '状态',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (identity_id),
  UNIQUE KEY uk_ident_acct_mode (account_id, mode),
  KEY idx_ident_role (role_id),
  CONSTRAINT fk_ident_acct FOREIGN KEY (account_id) REFERENCES account(account_id) ON DELETE CASCADE,
  CONSTRAINT fk_ident_role FOREIGN KEY (role_id)    REFERENCES role(role_id)       ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='账号身份——一个账号在每种模式下有一个身份，权限按身份判定';

-- ---------------------------------------------------------------------------
-- 3. 角色 —— 对应原作各身份上的 role 标签
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS role;
CREATE TABLE role (
  role_id         VARCHAR(32)   NOT NULL                COMMENT '角色ID',
  role_code       VARCHAR(32)   NOT NULL                COMMENT '角色码',
  role_name       VARCHAR(64)   NOT NULL                COMMENT '角色名称（经营者/投资人/顾问…）',
  role_level      ENUM('main','sub') NOT NULL           COMMENT '适用层级',
  domain_mode     ENUM('enterprise','personal','family') NOT NULL COMMENT '适用模式',
  sort_no         INT           NOT NULL DEFAULT 0      COMMENT '排序号',
  description     VARCHAR(255)  NULL                    COMMENT '职责说明',
  PRIMARY KEY (role_id),
  UNIQUE KEY uk_role_code (role_code)
) ENGINE=InnoDB COMMENT='角色';

-- ---------------------------------------------------------------------------
-- 4. 权限 —— 对应原作 PERMS 里的 read / write / main
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS permission;
CREATE TABLE permission (
  perm_id         VARCHAR(32)   NOT NULL                COMMENT '权限ID',
  perm_code       VARCHAR(32)   NOT NULL                COMMENT '权限码',
  perm_name       VARCHAR(64)   NOT NULL                COMMENT '权限名称',
  perm_group      VARCHAR(32)   NOT NULL                COMMENT '权限分组',
  sort_no         INT           NOT NULL DEFAULT 0      COMMENT '排序号',
  description     VARCHAR(255)  NULL                    COMMENT '权限说明',
  PRIMARY KEY (perm_id),
  UNIQUE KEY uk_perm_code (perm_code)
) ENGINE=InnoDB COMMENT='权限';

DROP TABLE IF EXISTS role_permission;
CREATE TABLE role_permission (
  rp_id           VARCHAR(32)   NOT NULL                COMMENT '关联ID',
  role_id         VARCHAR(32)   NOT NULL                COMMENT '角色',
  perm_id         VARCHAR(32)   NOT NULL                COMMENT '权限',
  PRIMARY KEY (rp_id),
  UNIQUE KEY uk_rp_role_perm (role_id, perm_id),
  KEY idx_rp_perm (perm_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (role_id) REFERENCES role(role_id)         ON DELETE CASCADE,
  CONSTRAINT fk_rp_perm FOREIGN KEY (perm_id) REFERENCES permission(perm_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='角色-权限关联';

-- ============================================================================
-- 第二部分：账本与挂载（对应原作 book / attach）—— 授权的核心链
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 5. 账本 —— 每个身份一本「自己的账本」，本身份可读写
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS book;
CREATE TABLE book (
  book_id         VARCHAR(32)   NOT NULL                COMMENT '账本ID',
  owner_identity  VARCHAR(64)   NOT NULL                COMMENT '所有者身份（自己的账本）',
  name            VARCHAR(128)  NOT NULL                COMMENT '账本名称',
  book_type       ENUM('public','private') NOT NULL    COMMENT '对公/对私',
  caliber         ENUM('business','household','consolidated') NOT NULL DEFAULT 'business'
                                COMMENT '口径：经营/家庭/综合所得',
  status          ENUM('active','archived') NOT NULL DEFAULT 'active' COMMENT '状态',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (book_id),
  UNIQUE KEY uk_book_owner (owner_identity),
  CONSTRAINT fk_book_owner FOREIGN KEY (owner_identity) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='账本——每个身份一本自己的账本，本身份可读写';

-- ---------------------------------------------------------------------------
-- 6. 账本挂载 —— 对应原作 attach。授权的核心实体
--    主账号身份把自己的账本以某角色挂载给子账号身份：
--      · 子账号对挂载进来的账本只有只读
--      · mount_role 决定子账号以什么角色看这本账（如 投资人/顾问/消费成员）
--      · 主账号可随时收回（status → revoked）
--      · denied_perm 可在挂载层显式禁掉某些权限
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS book_share;
CREATE TABLE book_share (
  share_id        VARCHAR(32)   NOT NULL                COMMENT '挂载ID',
  host_identity   VARCHAR(64)   NOT NULL                COMMENT '主账号身份（账本所有方）',
  guest_identity  VARCHAR(64)   NOT NULL                COMMENT '子账号身份（被授权方）',
  book_id         VARCHAR(32)   NOT NULL                COMMENT '被挂载的账本',
  mount_role      VARCHAR(64)   NOT NULL                COMMENT '挂载角色（子账号以此角色看这本账）',
  view_level      ENUM('detail','summary','conclusion') NOT NULL DEFAULT 'detail'
                                COMMENT '可见粒度：detail=完整明细 / summary=通俗摘要 / conclusion=测算结论（对应原作 GRAN_TICKS 三级）',
  denied_perm     VARCHAR(255)  NULL                    COMMENT '显式禁用的权限码（逗号分隔）',
  status          ENUM('active','revoked') NOT NULL DEFAULT 'active' COMMENT '状态',
  note            VARCHAR(255)  NULL                    COMMENT '授权说明',
  shared_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '挂载时间',
  revoked_at      DATETIME      NULL                    COMMENT '收回时间',
  PRIMARY KEY (share_id),
  UNIQUE KEY uk_share_unique (guest_identity, book_id),
  KEY idx_share_host (host_identity, status),
  KEY idx_share_book (book_id),
  CONSTRAINT fk_share_host FOREIGN KEY (host_identity)  REFERENCES account_identity(identity_id) ON DELETE CASCADE,
  CONSTRAINT fk_share_guest FOREIGN KEY (guest_identity) REFERENCES account_identity(identity_id) ON DELETE CASCADE,
  CONSTRAINT fk_share_book  FOREIGN KEY (book_id)        REFERENCES book(book_id)                 ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='账本挂载——主账号身份把账本以某角色挂给子账号身份，只读、可收回';

-- ---------------------------------------------------------------------------
-- 6.1 月度财务口径 —— 健康分与 DTI 的输入（对应原作 LOAN_MODEL 的 income / cash）
--     原件里这几个数是显式数据，不由流水推算；刚性支出 = 房租+工资+水电 类固定支出
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS fin_profile;
CREATE TABLE fin_profile (
  profile_id      VARCHAR(32)   NOT NULL                COMMENT '口径ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份',
  monthly_income  DECIMAL(14,2) NOT NULL DEFAULT 0      COMMENT '月收入（原件 LOAN_MODEL.income）',
  deposit_cash    DECIMAL(14,2) NOT NULL DEFAULT 0      COMMENT '存款余额（原件 LOAN_MODEL.cash）',
  fixed_expense   DECIMAL(14,2) NOT NULL DEFAULT 0      COMMENT '月度刚性支出（缓冲月数分母）',
  duty_amount     DECIMAL(14,2) NULL                    COMMENT '应担责任额（保障缺口的责任方，NULL=未测算）',
  stat_month      CHAR(7)       NOT NULL                COMMENT '统计月份 YYYY-MM',
  PRIMARY KEY (profile_id),
  UNIQUE KEY uk_fin_identity_month (identity_id, stat_month),
  CONSTRAINT fk_fin_identity FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='月度财务口径——月收入/存款/刚性支出/应担责任，健康分与缺口的输入';

-- ---------------------------------------------------------------------------
-- 6.2 银行卡 —— 对应原作 CARDS：流水归集与账单提醒都从卡上来
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS bank_card;
CREATE TABLE bank_card (
  card_id         VARCHAR(32)   NOT NULL                COMMENT '卡ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份',
  card_type       ENUM('储蓄卡','信用卡') NOT NULL      COMMENT '卡类型',
  card_no_masked  VARCHAR(32)   NOT NULL                COMMENT '掩码卡号（只存后四位）',
  bank_name       VARCHAR(64)   NOT NULL                COMMENT '银行',
  account_name    VARCHAR(128)  NOT NULL                COMMENT '户名（含主体）',
  purpose         ENUM('流水归集','账单提醒') NOT NULL  COMMENT '用途',
  sync_note       VARCHAR(64)   NULL                    COMMENT '同步情况（如 已同步 18 笔 / 每月 15 日账单日）',
  bill_day        TINYINT       NULL                    COMMENT '账单日（信用卡，1-28）',
  status          ENUM('active','unbound') NOT NULL DEFAULT 'active' COMMENT '状态',
  PRIMARY KEY (card_id),
  KEY idx_card_identity (identity_id),
  CONSTRAINT fk_card_identity FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='银行卡——流水的来源，对应原作 CARDS';

-- ---------------------------------------------------------------------------
-- 6.3 银企账户授权 —— 对应原作 AUTHORIZED：授权某卡用于流水归集 / 账单提醒
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS bank_auth;
CREATE TABLE bank_auth (
  auth_id         VARCHAR(32)   NOT NULL                COMMENT '授权ID',
  card_id         VARCHAR(32)   NOT NULL                COMMENT '被授权的卡',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '授权方身份',
  scope           ENUM('流水归集','账单提醒') NOT NULL  COMMENT '授权用途',
  authorized_at   DATE          NOT NULL                COMMENT '授权日期',
  status          ENUM('active','revoked') NOT NULL DEFAULT 'active' COMMENT '状态',
  PRIMARY KEY (auth_id),
  KEY idx_auth_card (card_id),
  CONSTRAINT fk_auth_card     FOREIGN KEY (card_id)     REFERENCES bank_card(card_id)             ON DELETE CASCADE,
  CONSTRAINT fk_auth_identity FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id)   ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='银企账户授权——原件 AUTHORIZED 列表';

-- ---------------------------------------------------------------------------
-- 6.4 脱敏/可见性规则 —— 对应原作 hidden 列表 + PERSP_DATA 三视角
--     同一份账本，不同挂载粒度看到的内容不同：哪些主题对哪一级隐藏
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS visibility_rule;
CREATE TABLE visibility_rule (
  rule_id         VARCHAR(32)   NOT NULL                COMMENT '规则ID',
  book_id         VARCHAR(32)   NOT NULL                COMMENT '适用账本（NULL=全部账本）',
  view_level      ENUM('detail','summary','conclusion') NOT NULL COMMENT '适用可见粒度',
  hidden_topic    VARCHAR(64)   NOT NULL                COMMENT '隐藏的内容主题（如 员工薪资明细）',
  rule_note       VARCHAR(255)  NULL                    COMMENT '说明',
  PRIMARY KEY (rule_id),
  KEY idx_vis_book (book_id, view_level),
  CONSTRAINT fk_vis_book FOREIGN KEY (book_id) REFERENCES book(book_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='脱敏规则——原件 hidden：经营者可见全部，投资人/顾问被隐藏薪酬、户名、逐笔凭证号、卡号';

-- ---------------------------------------------------------------------------
-- 6.5 入组申请 —— 对应原作 PENDING / APPROVED：子账号申请加入某模式的某角色
--     小微版默认「主账号挂载即生效」，如需留痕可开启申请制；本表同时记录已通过的授权来源
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS join_request;
CREATE TABLE join_request (
  req_id          VARCHAR(32)   NOT NULL                COMMENT '申请ID',
  account_id      VARCHAR(32)   NOT NULL                COMMENT '申请人账号',
  identity_id     VARCHAR(64)   NULL                    COMMENT '获批后生成的身份',
  mode            ENUM('enterprise','personal','family') NOT NULL COMMENT '目标模式',
  role_id         VARCHAR(32)   NOT NULL                COMMENT '目标角色',
  scope_note      VARCHAR(255)  NULL                    COMMENT '申请查看范围说明',
  status          ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending' COMMENT '状态',
  applied_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '申请时间',
  decided_by      VARCHAR(64)   NULL                    COMMENT '审批人身份',
  decided_at      DATETIME      NULL                    COMMENT '审批时间',
  PRIMARY KEY (req_id),
  KEY idx_req_status (status),
  CONSTRAINT fk_req_account  FOREIGN KEY (account_id)  REFERENCES account(account_id)            ON DELETE CASCADE,
  CONSTRAINT fk_req_identity FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id)   ON DELETE SET NULL,
  CONSTRAINT fk_req_role     FOREIGN KEY (role_id)     REFERENCES role(role_id)
) ENGINE=InnoDB COMMENT='入组申请——原件 PENDING 待批 / APPROVED 已通过';

-- ---------------------------------------------------------------------------
-- 6.6 还款与账单提醒 —— 对应原作 pending 提醒（房贷每月 5 日 ¥6,800 / 消费贷每月 8 日）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS reminder;
CREATE TABLE reminder (
  reminder_id     VARCHAR(32)   NOT NULL                COMMENT '提醒ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份',
  ref_type        ENUM('贷款','信用卡','保单','对账') NOT NULL COMMENT '提醒对象类型',
  ref_id          VARCHAR(32)   NULL                    COMMENT '对象ID',
  due_day         TINYINT       NULL                    COMMENT '每月第几日',
  amount          DECIMAL(14,2) NULL                    COMMENT '金额',
  text            VARCHAR(255)  NOT NULL                COMMENT '提醒文案',
  lead_days       TINYINT       NOT NULL DEFAULT 1      COMMENT '提前几天提醒',
  status          ENUM('active','done','off') NOT NULL DEFAULT 'active' COMMENT '状态',
  PRIMARY KEY (reminder_id),
  KEY idx_rem_identity (identity_id, status),
  CONSTRAINT fk_rem_identity FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE,
  CONSTRAINT fk_rem_loan     FOREIGN KEY (ref_id)      REFERENCES loan(loan_id)                ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='还款与账单提醒——原件 pending 里的固定支出提醒';

-- ---------------------------------------------------------------------------
-- 6.7 健康分档规则 —— 对应原作 HEALTH_FORMULA：每一维先分档得 0-100 分，再按 40/30/30 加权
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS health_rule;
CREATE TABLE health_rule (
  rule_id         VARCHAR(32)   NOT NULL                COMMENT '规则ID',
  dimension       ENUM('负债压力','现金缓冲','保障覆盖') NOT NULL COMMENT '维度',
  lower_bound     DECIMAL(8,4)  NOT NULL                COMMENT '区间下界（含）',
  upper_bound     DECIMAL(8,4)  NULL                    COMMENT '区间上界（不含，NULL=无穷）',
  score           TINYINT       NOT NULL                COMMENT '该区间得分（0-100）',
  weight_pct      TINYINT       NOT NULL                COMMENT '维度权重（%）',
  note            VARCHAR(128)  NULL                    COMMENT '口径说明',
  PRIMARY KEY (rule_id),
  KEY idx_hr_dim (dimension, lower_bound)
) ENGINE=InnoDB COMMENT='健康分档规则——原件 HEALTH_FORMULA 的分档映射与 40/30/30 权重';

-- ---------------------------------------------------------------------------
-- 7. 敏感动作 —— 关键操作需二次确认并留痕
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS sensitive_action;
CREATE TABLE sensitive_action (
  action_id       VARCHAR(32)   NOT NULL                COMMENT '动作ID',
  action_code     VARCHAR(32)   NOT NULL                COMMENT '动作码',
  action_name     VARCHAR(64)   NOT NULL                COMMENT '动作名称',
  target_type     VARCHAR(32)   NOT NULL                COMMENT '作用对象类型',
  confirm_way     ENUM('password','sms','none') NOT NULL DEFAULT 'password' COMMENT '确认方式',
  who_can_exec    ENUM('main','sub','both') NOT NULL DEFAULT 'both' COMMENT '谁可以执行',
  sort_no         INT           NOT NULL DEFAULT 0      COMMENT '排序号',
  PRIMARY KEY (action_id),
  UNIQUE KEY uk_action_code (action_code)
) ENGINE=InnoDB COMMENT='敏感动作配置';

-- ---------------------------------------------------------------------------
-- 8. 审计日志
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS audit_log;
CREATE TABLE audit_log (
  audit_id        VARCHAR(32)   NOT NULL                COMMENT '审计ID',
  actor_identity  VARCHAR(64)   NOT NULL                COMMENT '操作身份',
  action          VARCHAR(64)   NOT NULL                COMMENT '操作动作',
  target_type     VARCHAR(32)   NULL                    COMMENT '对象类型',
  target_id       VARCHAR(64)   NULL                    COMMENT '对象ID',
  detail          JSON          NULL                    COMMENT '明细',
  ip              VARCHAR(46)   NULL                    COMMENT '操作IP',
  is_confirmed    TINYINT(1)    NOT NULL DEFAULT 0      COMMENT '是否经过二次确认',
  created_at      DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (audit_id),
  KEY idx_audit_actor (actor_identity, created_at),
  KEY idx_audit_action (action),
  CONSTRAINT fk_audit_actor FOREIGN KEY (actor_identity) REFERENCES account_identity(identity_id) ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='审计日志——每个身份可查自己的操作，主账号身份可查其账本相关全部';

-- ============================================================================
-- 第三部分：账域（挂在账本下）
-- ============================================================================

DROP TABLE IF EXISTS txn;
CREATE TABLE txn (
  txn_id          VARCHAR(32)   NOT NULL                COMMENT '流水ID',
  book_id         VARCHAR(32)   NOT NULL                COMMENT '账本',
  txn_no          VARCHAR(64)   NOT NULL                COMMENT '业务流水号',
  amount          DECIMAL(18,2) NOT NULL                COMMENT '金额（正=收入，负=支出）',
  direction       ENUM('in','out') NOT NULL             COMMENT '收支方向',
  counterparty    VARCHAR(128)  NULL                    COMMENT '交易对方',
  txn_date        DATE          NOT NULL                COMMENT '记账日期',
  voucher_no      VARCHAR(64)   NULL                    COMMENT '凭证号',
  channel         ENUM('bank','alipay','wechat','cash','other') NOT NULL DEFAULT 'bank' COMMENT '渠道',
  status          ENUM('normal','void','reversed') NOT NULL DEFAULT 'normal' COMMENT '状态：一经导入不可编辑',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (txn_id),
  UNIQUE KEY uk_txn_no (book_id, txn_no),
  KEY idx_txn_date (book_id, txn_date),
  CONSTRAINT fk_txn_book FOREIGN KEY (book_id) REFERENCES book(book_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='银行流水';

DROP TABLE IF EXISTS receipt;
CREATE TABLE receipt (
  receipt_id      VARCHAR(32)   NOT NULL                COMMENT '票据ID',
  txn_id          VARCHAR(32)   NULL                    COMMENT '关联流水（缺票时为空）',
  book_id         VARCHAR(32)   NOT NULL                COMMENT '账本',
  receipt_type    ENUM('小票','收据','其他') NOT NULL   COMMENT '票据类型',
  amount          DECIMAL(18,2) NOT NULL                COMMENT '金额',
  receipt_date    DATE          NOT NULL                COMMENT '票据日期',
  handler_identity VARCHAR(64)  NULL                    COMMENT '上传身份',
  file_ref        VARCHAR(255)  NULL                    COMMENT '影像件地址',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (receipt_id),
  KEY idx_receipt_txn (txn_id),
  CONSTRAINT fk_receipt_txn  FOREIGN KEY (txn_id)           REFERENCES txn(txn_id)                 ON DELETE CASCADE,
  CONSTRAINT fk_receipt_book FOREIGN KEY (book_id)          REFERENCES book(book_id)               ON DELETE CASCADE,
  CONSTRAINT fk_receipt_hand FOREIGN KEY (handler_identity) REFERENCES account_identity(identity_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='票据/小票';

DROP TABLE IF EXISTS invoice;
CREATE TABLE invoice (
  invoice_id      VARCHAR(32)   NOT NULL                COMMENT '发票ID',
  receipt_id      VARCHAR(32)   NULL                    COMMENT '关联票据',
  book_id         VARCHAR(32)   NOT NULL                COMMENT '账本',
  invoice_no      VARCHAR(32)   NOT NULL                COMMENT '发票号码',
  invoice_type    ENUM('专票','普票','电子专票','电子普票') NOT NULL DEFAULT '普票' COMMENT '发票类型',
  amount          DECIMAL(18,2) NOT NULL                COMMENT '价税合计',
  tax_rate        DECIMAL(6,4)  NOT NULL DEFAULT 0      COMMENT '税率',
  tax_amount      DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '税额',
  invoice_date    DATE          NOT NULL                COMMENT '开票日期',
  seller_name     VARCHAR(128)  NULL                    COMMENT '销售方名称',
  cert_status     ENUM('none','certified','deducted') NOT NULL DEFAULT 'none' COMMENT '认证状态',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (invoice_id),
  UNIQUE KEY uk_inv_no (invoice_no),
  KEY idx_inv_receipt (receipt_id),
  CONSTRAINT fk_inv_receipt FOREIGN KEY (receipt_id) REFERENCES receipt(receipt_id) ON DELETE SET NULL,
  CONSTRAINT fk_inv_book    FOREIGN KEY (book_id)    REFERENCES book(book_id)       ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='发票';

DROP TABLE IF EXISTS recon_anomaly;
CREATE TABLE recon_anomaly (
  recon_id        VARCHAR(32)   NOT NULL                COMMENT '对账异常ID',
  txn_id          VARCHAR(32)   NOT NULL                COMMENT '关联流水',
  invoice_id      VARCHAR(32)   NULL                    COMMENT '关联发票',
  anomaly_type    ENUM('缺票','金额不符','重复入账','其他') NOT NULL COMMENT '异常类型',
  diff_amount     DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '差额',
  status          ENUM('open','fixed','ignored') NOT NULL DEFAULT 'open' COMMENT '处理状态',
  handled_by      VARCHAR(64)   NULL                    COMMENT '处理身份',
  handled_at      DATETIME      NULL                    COMMENT '处理时间',
  PRIMARY KEY (recon_id),
  KEY idx_recon_txn (txn_id),
  CONSTRAINT fk_recon_txn FOREIGN KEY (txn_id)     REFERENCES txn(txn_id)         ON DELETE CASCADE,
  CONSTRAINT fk_recon_inv FOREIGN KEY (invoice_id) REFERENCES invoice(invoice_id) ON DELETE SET NULL
) ENGINE=InnoDB COMMENT='对账异常';

DROP TABLE IF EXISTS evidence;
CREATE TABLE evidence (
  evidence_id     VARCHAR(32)   NOT NULL                COMMENT '证据ID',
  txn_id          VARCHAR(32)   NULL                    COMMENT '关联流水',
  receipt_id      VARCHAR(32)   NULL                    COMMENT '关联票据',
  invoice_id      VARCHAR(32)   NULL                    COMMENT '关联发票',
  token           VARCHAR(64)   NOT NULL                COMMENT '溯源令牌',
  ev_type         ENUM('流水','小票','发票','合同','保单') NOT NULL COMMENT '证据类型',
  source_ref      VARCHAR(128)  NULL                    COMMENT '证据来源（原件 src：上传者/开票方/放款机构）',
  ocr_conf        DECIMAL(5,2)  NULL                    COMMENT 'OCR 识别置信度 %（原件 ocr）',
  rule_note       VARCHAR(255)  NULL                    COMMENT '判定规则（原件 rule：为何标记异常）',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (evidence_id),
  UNIQUE KEY uk_ev_token (token),
  KEY idx_ev_txn (txn_id)
) ENGINE=InnoDB COMMENT='凭证/证据链';

-- ============================================================================
-- 第四部分：税务域
-- ============================================================================

DROP TABLE IF EXISTS taxpayer;
CREATE TABLE taxpayer (
  taxpayer_id     VARCHAR(32)   NOT NULL                COMMENT '纳税人ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份（企业或个人身份）',
  tax_no          VARCHAR(32)   NOT NULL                COMMENT '纳税人识别号',
  scale_type      ENUM('小规模纳税人','一般纳税人','自然人') NOT NULL COMMENT '规模类型',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (taxpayer_id),
  UNIQUE KEY uk_tax_no (tax_no),
  CONSTRAINT fk_tax_ident FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='纳税人';

DROP TABLE IF EXISTS tax_type;
CREATE TABLE tax_type (
  tax_type_id     VARCHAR(32)   NOT NULL                COMMENT '税种ID',
  tax_name        VARCHAR(64)   NOT NULL                COMMENT '税种名称',
  tax_code        VARCHAR(32)   NOT NULL                COMMENT '税种代码',
  default_rate    DECIMAL(6,4)  NOT NULL DEFAULT 0      COMMENT '默认征收率',
  file_cycle      ENUM('月度','季度','年度','一次性') NOT NULL COMMENT '申报周期',
  sort_no         INT           NOT NULL DEFAULT 0      COMMENT '排序号',
  PRIMARY KEY (tax_type_id),
  UNIQUE KEY uk_tax_type_code (tax_code)
) ENGINE=InnoDB COMMENT='税种';

DROP TABLE IF EXISTS rate_table;
CREATE TABLE rate_table (
  rate_id         VARCHAR(32)   NOT NULL                COMMENT '税率ID',
  tax_type_id     VARCHAR(32)   NOT NULL                COMMENT '税种',
  scale_type      ENUM('小规模纳税人','一般纳税人','自然人') NOT NULL COMMENT '适用规模',
  rate            DECIMAL(6,4)  NOT NULL                COMMENT '税率',
  valid_from      DATE          NOT NULL                COMMENT '生效日',
  valid_to        DATE          NULL                    COMMENT '失效日',
  PRIMARY KEY (rate_id),
  KEY idx_rate_tax (tax_type_id, valid_from),
  CONSTRAINT fk_rate_tax FOREIGN KEY (tax_type_id) REFERENCES tax_type(tax_type_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='税率表——按生效期版本化，只增不改';

DROP TABLE IF EXISTS deduction;
CREATE TABLE deduction (
  deduction_id    VARCHAR(32)   NOT NULL                COMMENT '扣除ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份（个人身份）',
  item_code       VARCHAR(32)   NOT NULL                COMMENT '项目代码',
  item_name       VARCHAR(64)   NOT NULL                COMMENT '项目名称',
  standard_amount DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '扣除标准',
  amount          DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '实际扣除金额',
  tax_year        YEAR          NOT NULL                COMMENT '所属年度',
  PRIMARY KEY (deduction_id),
  UNIQUE KEY uk_ded_ident (identity_id, item_code, tax_year),
  CONSTRAINT fk_ded_ident FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='专项附加扣除（7 项标准，纯个人事项）';

DROP TABLE IF EXISTS tax_policy;
CREATE TABLE tax_policy (
  policy_id       VARCHAR(32)   NOT NULL                COMMENT '政策ID',
  policy_no       VARCHAR(32)   NOT NULL                COMMENT '政策编号',
  name            VARCHAR(255)  NOT NULL                COMMENT '政策名称',
  apply_cond      TEXT          NULL                    COMMENT '适用条件',
  valid_from      DATE          NOT NULL                COMMENT '生效日',
  valid_to        DATE          NULL                    COMMENT '失效日',
  source_url      VARCHAR(512)  NULL                    COMMENT '原文链接',
  PRIMARY KEY (policy_id),
  UNIQUE KEY uk_policy_no (policy_no)
) ENGINE=InnoDB COMMENT='税收政策';

-- ============================================================================
-- 第五部分：信贷与保障
-- ============================================================================

DROP TABLE IF EXISTS loan;
CREATE TABLE loan (
  loan_id         VARCHAR(32)   NOT NULL                COMMENT '贷款ID',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份',
  contract_no     VARCHAR(64)   NOT NULL                COMMENT '合同号',
  lender          VARCHAR(128)  NOT NULL                COMMENT '贷款机构',
  balance         DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '当前余额',
  monthly_pay     DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '月供',
  interest_rate   DECIMAL(8,6)  NOT NULL DEFAULT 0      COMMENT '年利率',
  repay_day       TINYINT       NOT NULL DEFAULT 1      COMMENT '每月还款日',
  loan_type       ENUM('经营贷','房贷','消费贷','其他') NOT NULL DEFAULT '经营贷' COMMENT '贷款类型',
  start_date      DATE          NOT NULL                COMMENT '起贷日',
  end_date        DATE          NULL                    COMMENT '到期日',
  PRIMARY KEY (loan_id),
  UNIQUE KEY uk_loan_contract (contract_no),
  CONSTRAINT fk_loan_ident FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='贷款账户';

DROP TABLE IF EXISTS insurance_policy;
CREATE TABLE insurance_policy (
  policy_id       VARCHAR(32)   NOT NULL                COMMENT '保单号',
  identity_id     VARCHAR(64)   NOT NULL                COMMENT '所属身份',
  holder_name     VARCHAR(64)   NOT NULL                COMMENT '投保人',
  insured_name    VARCHAR(64)   NOT NULL                COMMENT '被保人/受益人',
  insurer         VARCHAR(128)  NOT NULL                COMMENT '保险公司',
  product_name    VARCHAR(128)  NULL                    COMMENT '产品名称',
  sum_assured     DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '保额',
  premium         DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '保费',
  pay_cycle       ENUM('趸交','年交','月交','季交') NOT NULL DEFAULT '年交' COMMENT '缴费周期',
  start_date      DATE          NOT NULL                COMMENT '保障起始',
  end_date        DATE          NOT NULL                COMMENT '保障届满',
  status          ENUM('生效','待生效','已失效','已退保') NOT NULL DEFAULT '生效' COMMENT '保单状态',
  PRIMARY KEY (policy_id),
  KEY idx_ins_ident (identity_id),
  CONSTRAINT fk_ins_ident FOREIGN KEY (identity_id) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='保单';

DROP TABLE IF EXISTS coverage;
CREATE TABLE coverage (
  coverage_id     VARCHAR(32)   NOT NULL                COMMENT '保障责任ID',
  policy_id       VARCHAR(32)   NOT NULL                COMMENT '保单',
  cover_type      ENUM('重疾','医疗','寿险','意外','失能') NOT NULL COMMENT '责任类型',
  sum_assured     DECIMAL(18,2) NOT NULL DEFAULT 0      COMMENT '保额',
  PRIMARY KEY (coverage_id),
  CONSTRAINT fk_cov_policy FOREIGN KEY (policy_id) REFERENCES insurance_policy(policy_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='保障责任';

-- ============================================================================
-- 第六部分：技能与会话
-- ============================================================================

DROP TABLE IF EXISTS skill;
CREATE TABLE skill (
  skill_id        VARCHAR(32)   NOT NULL                COMMENT '技能ID',
  domain          VARCHAR(32)   NOT NULL                COMMENT '所属业务域（对应原作 SKILL_DOMAINS）',
  name            VARCHAR(64)   NOT NULL                COMMENT '技能名称（对应原作 SKILLS[].name）',
  icon            VARCHAR(32)   NULL                    COMMENT '图标标识（对应原作 SKILLS[].icon）',
  required_perm   VARCHAR(32)   NOT NULL                COMMENT '所需权限码（对应原作 SKILLS[].perm）',
  summary         VARCHAR(255)  NULL                    COMMENT '一句话说明',
  output_desc     VARCHAR(255)  NULL                    COMMENT '输出物',
  sort_no         INT           NOT NULL DEFAULT 0      COMMENT '排序号',
  PRIMARY KEY (skill_id),
  UNIQUE KEY uk_skill_name (name)
) ENGINE=InnoDB COMMENT='技能——对应原作 SKILLS 数组（18 个），按当前身份的权限门控';

DROP TABLE IF EXISTS conversation;
CREATE TABLE conversation (
  conv_id         VARCHAR(32)   NOT NULL                COMMENT '会话ID',
  owner_identity  VARCHAR(64)   NOT NULL                COMMENT '归属身份（对应原作会话 owner=模式:账号）',
  title           VARCHAR(128)  NOT NULL                COMMENT '会话标题',
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (conv_id),
  KEY idx_conv_owner (owner_identity, updated_at),
  CONSTRAINT fk_conv_owner FOREIGN KEY (owner_identity) REFERENCES account_identity(identity_id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='会话——归属身份';

DROP TABLE IF EXISTS kb_entry;
CREATE TABLE kb_entry (
  kb_id           VARCHAR(32)   NOT NULL                COMMENT '知识库条目ID',
  category        VARCHAR(64)   NOT NULL                COMMENT '分类',
  title           VARCHAR(255)  NOT NULL                COMMENT '标题',
  content         MEDIUMTEXT    NOT NULL                COMMENT '正文',
  source_ref      VARCHAR(512)  NULL                    COMMENT '来源',
  effective_from  DATE          NULL                    COMMENT '生效日',
  PRIMARY KEY (kb_id),
  KEY idx_kb_cat (category)
) ENGINE=InnoDB COMMENT='知识库条目——对应原作 knowledge_base/财税知识库';

-- ============================================================================
-- 第七部分：派生视图（实时算出，不建表）
-- ============================================================================

-- 7.1 身份的有效权限：身份 → 角色 → 权限（替代原作 PERMS["模式:账号"]）
CREATE OR REPLACE VIEW v_identity_perm AS
SELECT DISTINCT
  i.identity_id,
  i.mode,
  i.level,
  i.role_id,
  p.perm_code,
  p.perm_name
FROM account_identity i
JOIN role_permission rp ON rp.role_id = i.role_id
JOIN permission p       ON p.perm_id = rp.perm_id;

-- 7.2 子账号身份可见的账本：自己的（读写）+ 被挂载的（只读）
CREATE OR REPLACE VIEW v_identity_books AS
SELECT
  i.identity_id,
  b.book_id,
  b.name AS book_name,
  'own'  AS access_type,
  '读写' AS access_label,
  NULL   AS mount_role
FROM account_identity i
JOIN book b ON b.owner_identity = i.identity_id
UNION ALL
SELECT
  s.guest_identity,
  b.book_id,
  b.name,
  'shared',
  '只读',
  s.mount_role
FROM book_share s
JOIN book b ON b.book_id = s.book_id
WHERE s.status = 'active';

-- 7.3 信贷健康 DTI：分子 = 该身份【全部】贷款月供之和（原件：企业 8,900+1,200=10,100）
--     分母 = fin_profile.monthly_income（原件 LOAN_MODEL.income），不用流水推算
CREATE OR REPLACE VIEW v_credit_health AS
SELECT
  f.identity_id,
  SUM(l.monthly_pay)                                   AS total_pay,
  f.monthly_income,
  ROUND(SUM(l.monthly_pay) / NULLIF(f.monthly_income,0) * 100, 2) AS dti_pct,
  CASE
    WHEN f.monthly_income = 0 THEN '数据不足'
    WHEN SUM(l.monthly_pay) / f.monthly_income <= 0.10 THEN '健康'
    WHEN SUM(l.monthly_pay) / f.monthly_income <= 0.30 THEN '适中'
    WHEN SUM(l.monthly_pay) / f.monthly_income <= 0.50 THEN '偏大'
    ELSE '超限'
  END                                                  AS dti_level
FROM fin_profile f
LEFT JOIN loan l ON l.identity_id = f.identity_id AND l.status = '正常'
GROUP BY f.identity_id, f.monthly_income;

-- 7.4 现金缓冲：存款 ÷ 月度刚性支出 = 可支撑月数（原件：企业 86,000÷29,000≈3.0）
CREATE OR REPLACE VIEW v_cash_buffer AS
SELECT
  identity_id,
  deposit_cash,
  fixed_expense,
  ROUND(deposit_cash / NULLIF(fixed_expense,0), 1) AS buffer_months,
  CASE
    WHEN fixed_expense = 0 THEN '数据不足'
    WHEN deposit_cash / fixed_expense >= 6 THEN '充足'
    WHEN deposit_cash / fixed_expense >= 3 THEN '一般'
    ELSE '偏紧'
  END AS buffer_level
FROM fin_profile;

-- 7.5 保障缺口：应担责任 − 已有保额（责任额来自 fin_profile.duty_amount，
--     原件企业 902,000 / 家庭 1,540,000 都是显式配置，不由贷款反推）
CREATE OR REPLACE VIEW v_coverage_gap AS
SELECT
  f.identity_id,
  f.duty_amount                                        AS duty,
  IFNULL(p.total_assured, 0)                           AS total_assured,
  ROUND(IFNULL(p.total_assured,0) / NULLIF(f.duty_amount,0) * 100, 1) AS cover_pct,
  GREATEST(f.duty_amount - IFNULL(p.total_assured,0), 0) AS gap_amount
FROM fin_profile f
LEFT JOIN (
  SELECT identity_id, SUM(sum_assured) AS total_assured
  FROM insurance_policy WHERE status = '生效'
  GROUP BY identity_id
) p ON p.identity_id = f.identity_id
WHERE f.duty_amount IS NOT NULL;

-- 7.6 健康分：三维先按 health_rule 分档得 0-100 分，再按 40/30/30 加权
--     （原件：企业 95×.4 + 72×.3 + 35×.3 ≈ 70 分，与演示值一致）
CREATE OR REPLACE VIEW v_health_score AS
SELECT
  h.identity_id,
  h.dti_pct,
  h.dti_level,
  cb.buffer_months,
  cb.buffer_level,
  cg.cover_pct,
  cg.gap_amount,
  ROUND(
      IFNULL(r_debt.score, 50) * (SELECT weight_pct FROM health_rule WHERE dimension='负债压力' LIMIT 1) / 100
    + IFNULL(r_cash.score, 50) * (SELECT weight_pct FROM health_rule WHERE dimension='现金缓冲' LIMIT 1) / 100
    + IFNULL(r_cov.score , 50) * (SELECT weight_pct FROM health_rule WHERE dimension='保障覆盖' LIMIT 1) / 100
  , 0) AS health_score
FROM v_credit_health h
LEFT JOIN v_cash_buffer  cb ON cb.identity_id = h.identity_id
LEFT JOIN v_coverage_gap cg ON cg.identity_id = h.identity_id
LEFT JOIN health_rule r_debt ON r_debt.dimension = '负债压力'
     AND h.dti_pct        >= r_debt.lower_bound
     AND (r_debt.upper_bound IS NULL OR h.dti_pct < r_debt.upper_bound)
LEFT JOIN health_rule r_cash ON r_cash.dimension = '现金缓冲'
     AND cb.buffer_months >= r_cash.lower_bound
     AND (r_cash.upper_bound IS NULL OR cb.buffer_months < r_cash.upper_bound)
LEFT JOIN health_rule r_cov  ON r_cov.dimension = '保障覆盖'
     AND cg.cover_pct     >= r_cov.lower_bound
     AND (r_cov.upper_bound IS NULL OR cg.cover_pct < r_cov.upper_bound);

-- ============================================================================
-- 第八部分：种子数据（与原演示包 7 个身份一一对应）
-- ============================================================================

-- 8.1 账号（自然人/主体）
INSERT INTO account (account_id, login_id, name, acct_kind, phone) VALUES
('A_WJG',  '13900006789','王建国',     '个人','138****6789'),
('A_CX',   '13600001111','晨曦科技',   '企业','136****1111'),
('A_LM',   '13600001112','李明',       '个人','136****1112'),
('A_LMEI', '13700003333','李梅',       '个人','137****3333'),
('A_ZNN',  '13700004444','张奶奶',     '个人','137****4444'),
('A_ADV',  '13500002222','李顾问',     '个人','135****2222');

-- 8.2 角色（7 个，与原作 role 标签一一对应）
INSERT INTO role (role_id, role_code, role_name, role_level, domain_mode, sort_no, description) VALUES
('R_OP','operator','经营者','main','enterprise',1,'数据所有者 · 可授权、可收回'),
('R_INV','investor','投资人','sub','enterprise',2,'自己的出资台账 + 只读被授权的经营数据'),
('R_SELF','self','本人','main','personal',3,'全部个人数据'),
('R_ADV','advisor','顾问','sub','personal',4,'只读测算结论 · 不看原始流水明细'),
('R_KEEP','keeper','管钱者','main','family',5,'全家账本 · 成员授权与提醒设置'),
('R_MEMBER','member','消费成员','sub','family',6,'本人收支 + 家庭公共账'),
('R_ELDER','elder','长辈','sub','family',7,'大字只读 · 语音播报（关怀模式）');

-- 8.3 权限（与原作 PERMS 的三个权限码一致，另加导出与配置）
INSERT INTO permission (perm_id, perm_code, perm_name, perm_group, sort_no, description) VALUES
('PM_R',   'read', '只读','数据',1,'查看授权范围内的数据'),
('PM_W',   'write','可写','数据',2,'录入或修改业务数据（数据导出等敏感写操作需二次确认）'),
('PM_MAIN','main', '主账号','系统',3,'管理子账号、挂载与收回、配置政策与技能（原件 PERM_META 仅此三码）');

-- 8.4 角色-权限（对应原作 PERMS 映射）
INSERT INTO role_permission (rp_id, role_id, perm_id) VALUES
('RP01','R_OP','PM_R'),('RP02','R_OP','PM_W'),('RP03','R_OP','PM_MAIN'),
('RP04','R_INV','PM_R'),
('RP05','R_SELF','PM_R'),('RP06','R_SELF','PM_W'),('RP07','R_SELF','PM_MAIN'),
('RP08','R_ADV','PM_R'),
('RP09','R_KEEP','PM_R'),('RP10','R_KEEP','PM_W'),('RP11','R_KEEP','PM_MAIN'),
('RP12','R_MEMBER','PM_R'),
('RP13','R_ELDER','PM_R');

-- 8.5 账号身份（与原作 ACCOUNTS 七个条目一一对应）
INSERT INTO account_identity (identity_id, account_id, mode, level, role_id, display_name, elder_mode) VALUES
('enterprise:operator','A_WJG','enterprise','main','R_OP','王建国 · 暖阳烘焙工作室',0),
('enterprise:investor','A_CX', 'enterprise','sub', 'R_INV','晨曦科技（李明）',0),
('personal:self',      'A_WJG','personal',  'main','R_SELF','王建国 · 个人账本',0),
('personal:advisor',   'A_ADV','personal',  'sub', 'R_ADV','李顾问',0),
('family:keeper',      'A_WJG','family',    'main','R_KEEP','王建国 · 家庭管钱者',0),
('family:member',      'A_LMEI','family',   'sub', 'R_MEMBER','李梅',0),
('family:elder',       'A_ZNN','family',    'sub', 'R_ELDER','张奶奶',1);

-- 8.6 自己的账本（每个身份一本，与原作 book 字段一致）
INSERT INTO book (book_id, owner_identity, name, book_type, caliber) VALUES
('BOOK_E','enterprise:operator','暖阳烘焙工作室账本','public','business'),
('BOOK_INV','enterprise:investor','晨曦科技投资台账','private','business'),
('BOOK_P','personal:self','王建国的个人账本','private','consolidated'),
('BOOK_ADV','personal:advisor','李顾问的顾问工作台账','private','business'),
('BOOK_F','family:keeper','王建国家庭账本','private','household'),
('BOOK_M','family:member','李梅的个人收支本','private','household'),
('BOOK_EL','family:elder','张奶奶的养老金账本','private','household');

-- 8.7 账本挂载（与原作 attach 一一对应：主账号账本 → 子账号，带挂载角色）
INSERT INTO book_share (share_id, host_identity, guest_identity, book_id, mount_role, view_level, note) VALUES
('SH01','enterprise:operator','enterprise:investor','BOOK_E','投资人','conclusion','只读 · 数据已做通俗化处理'),
('SH02','personal:self','personal:advisor','BOOK_P','顾问','conclusion','只读测算结论 · 不看原始流水明细'),
('SH03','family:keeper','family:member','BOOK_F','消费成员','detail','本人收支 + 家庭公共账'),
('SH04','family:keeper','family:elder','BOOK_F','长辈','summary','大字只读 · 语音播报');

-- 8.8 敏感动作
INSERT INTO sensitive_action (action_id, action_code, action_name, target_type, confirm_way, who_can_exec, sort_no) VALUES
('SA01','export_data','导出数据','book','password','both',1),
('SA02','share_book','挂载账本给子账号','book_share','password','main',2),
('SA03','revoke_share','收回挂载','book_share','password','main',3),
('SA04','insure_change','保单变更','insurance_policy','password','main',4),
('SA05','loan_add','新增贷款','loan','password','main',5),
('SA06','txn_void','流水作废','txn','password','both',6);

-- 8.9 经营流水（原件口径 2026-07 ~ 09：收入 108,000 / 114,500 / 120,000）
INSERT INTO txn (txn_id, book_id, txn_no, amount, direction, counterparty, txn_date, status) VALUES
('T001','BOOK_E','A004',9600.00,'out','采购食材','2026-09-05','normal'),
('T002','BOOK_E','A007',2300.00,'out','供电公司','2026-09-08','normal'),
('T003','BOOK_E','A018',6800.00,'out','设备租赁','2026-09-12','normal'),
('T004','BOOK_E','B001',120000.00,'in','门店营业收入','2026-09-30','normal'),
('T005','BOOK_E','B008',114500.00,'in','门店营业收入','2026-08-31','normal'),
('T006','BOOK_E','B007',108000.00,'in','门店营业收入','2026-07-31','normal');

INSERT INTO recon_anomaly (recon_id, txn_id, anomaly_type, diff_amount, status) VALUES
('RA001','T001','缺票',0,'open'),
('RA002','T003','缺票',0,'open'),
('RA003','T002','金额不符',100.00,'open');

-- 8.10 信贷与保障（严格按原件 LOAN_MODEL 与 EVIDENCE 保单重建）
--     DTI 分子：企业 8,900+1,200=10,100 ÷ 120,000 = 8.4%；家庭 8,000 ÷ 39,860 = 20.1%
INSERT INTO loan (loan_id, identity_id, contract_no, lender, balance, monthly_pay, interest_rate, repay_day, loan_type, start_date, status) VALUES
('LN001','enterprise:operator','LN2025010233','演示银行',240000.00,8900.00,0.043500,15,'经营贷','2025-01-15','正常'),
('LN002','enterprise:operator','LN2024030876','演示银行',120000.00,1200.00,0.072000, 8,'消费贷','2024-03-08','正常'),
('LN003','personal:self',      'LN2024030877','演示银行',192000.00,8000.00,0.072000, 8,'消费贷','2024-03-08','正常'),
('LN004','family:keeper',      'LN2020052001','建设银行',1200000.00,6800.00,0.038500, 5,'房贷','2020-05-20','正常'),
('LN005','family:keeper',      'LN2024030878','演示银行',120000.00,1200.00,0.072000, 8,'消费贷','2024-03-08','正常');

INSERT INTO insurance_policy (policy_id, identity_id, holder_name, insured_name, insurer, product_name, sum_assured, premium, pay_cycle, start_date, end_date, status) VALUES
('POL-2024-5220','enterprise:operator','暖阳烘焙工作室','员工','演示财险','雇主责任险',500000.00,4200.00,'年交','2024-05-20','2027-05-19','生效'),
('POL-2023-4006','enterprise:operator','暖阳烘焙工作室','员工','演示财险','团体意外险',300000.00,2600.00,'年交','2023-04-10','2026-04-09','生效'),
('POL-2022-1188','family:keeper','王建国','王建国','演示人寿','寿险',500000.00,8600.00,'年交','2022-11-08','2032-11-07','生效'),
('POL-2023-2201','family:keeper','王建国','王建国','演示财险','意外险',300000.00,1200.00,'年交','2023-06-15','2026-06-14','生效');

INSERT INTO coverage (coverage_id, policy_id, cover_type, sum_assured) VALUES
('CV001','POL-2024-5220','雇主责任',500000.00),
('CV002','POL-2023-4006','团体意外',300000.00),
('CV003','POL-2022-1188','寿险',500000.00),
('CV004','POL-2023-2201','意外',300000.00);

-- 8.10.1 月度财务口径（原件 LOAN_MODEL.income / cash，刚性支出与应担责任为演示口径）
-- 注：原件 HEALTH 里企业「已有保障 ¥160,000」与 EVIDENCE 两张保单合计 ¥800,000 矛盾，
--     本方案以保单实际合计为准；若按原件 160,000 口径，企业健康分=95×.4+72×.3+35×.3≈70 分。
INSERT INTO fin_profile (profile_id, identity_id, monthly_income, deposit_cash, fixed_expense, duty_amount, stat_month) VALUES
('FP01','enterprise:operator',120000.00,86000.00,29000.00, 902000.00,'2026-09'),
('FP02','personal:self',       15000.00,52000.00, 7000.00,       NULL,'2026-09'),
('FP03','family:keeper',       39860.00,96000.00,14000.00,1540000.00,'2026-09');

-- 8.10.2 银行卡（原件 CARDS 六张）
INSERT INTO bank_card (card_id, identity_id, card_type, card_no_masked, bank_name, account_name, purpose, sync_note, bill_day) VALUES
('CARD01','enterprise:operator','储蓄卡','**** **** **** 6789','招商银行','暖阳烘焙工作室 · 对公户','流水归集','已同步 18 笔',NULL),
('CARD02','enterprise:operator','信用卡','**** **** **** 4321','中信银行','主卡人 王建国',      '账单提醒','每月 15 日账单日',15),
('CARD03','personal:self',      '储蓄卡','**** **** **** 9012','招商银行','王建国个人储蓄户',    '流水归集','已同步 112 笔',NULL),
('CARD04','personal:self',      '信用卡','**** **** **** 4321','中信银行','主卡人 王建国',      '账单提醒','每月 15 日账单日',15),
('CARD05','family:keeper',      '储蓄卡','**** **** **** 5678','招商银行','家庭共用账户 · 房贷代扣','流水归集','房贷 6,800 / 月',NULL),
('CARD06','family:keeper',      '信用卡','**** **** **** 4321','中信银行','主卡人 王建国',      '账单提醒','每月 15 日账单日',15);

-- 8.10.3 银企账户授权（原件 AUTHORIZED 两条）
INSERT INTO bank_auth (auth_id, card_id, identity_id, scope, authorized_at, status) VALUES
('BA01','CARD01','enterprise:operator','流水归集','2026-06-01','active'),
('BA02','CARD02','enterprise:operator','账单提醒','2026-03-15','active');

-- 8.10.4 脱敏规则（原件 hidden：三本账各自隐藏什么）
INSERT INTO visibility_rule (rule_id, book_id, view_level, hidden_topic, rule_note) VALUES
('VR01','BOOK_E','summary','员工薪资明细','投资人只看结论，看不到薪酬'),
('VR02','BOOK_E','summary','供应商与客户户名','客户与供应商信息不外泄'),
('VR03','BOOK_E','summary','逐笔凭证号','只给金额与结论，不给凭证编号'),
('VR04','BOOK_E','summary','对公户卡号','卡号仅经营者可见'),
('VR05','BOOK_E','conclusion','原始流水明细','顾问只看测算结论与口径'),
('VR06','BOOK_P','summary','原始流水明细','个人账本对外只给结论'),
('VR07','BOOK_F','summary','其他成年成员的私人明细','家庭公共账不暴露个人明细'),
('VR08','BOOK_F','summary','成员各自的流水号','同上'),
('VR09','BOOK_M','summary','其他成年成员的私人明细','成员只见公共账与本人账'),
('VR10','BOOK_EL','summary','家里其他人的私人明细','长辈关怀视图只给汇总');

-- 8.10.5 入组申请（原件 PENDING 三条待批 + APPROVED 四条已通过）
INSERT INTO join_request (req_id, account_id, mode, role_id, scope_note, status, applied_at, decided_by, decided_at) VALUES
('RQ01','A_WJG','enterprise','R_ADV', '查看范围：经营收支与税负结论（只读，不含薪酬明细）','pending','2026-10-04 11:20',NULL,NULL),
('RQ02','A_WJG','family',    'R_MEMBER','查看范围：本人收支 + 家庭公共账','pending','2026-10-05 09:05',NULL,NULL),
('RQ03','A_WJG','family',    'R_ELDER','查看范围：大字摘要 + 异常提醒（只读）','pending','2026-10-05 10:12',NULL,NULL);

INSERT INTO join_request (req_id, account_id, identity_id, mode, role_id, scope_note, status, applied_at, decided_by, decided_at) VALUES
('RQ04','A_CX',  'enterprise:investor','enterprise','R_INV',   '企业模式 · 投资人 · 只读经营结论','approved','2026-05-28 10:00','enterprise:operator','2026-06-01 09:00'),
('RQ05','A_ADV', 'personal:advisor',  'personal',  'R_ADV',   '个人模式 · 顾问 · 只读测算结论','approved','2026-06-10 14:00','personal:self','2026-06-11 09:00'),
('RQ06','A_LMEI','family:member',     'family',    'R_MEMBER','家庭模式 · 本人收支 + 家庭公共账','approved','2026-07-01 20:00','family:keeper','2026-07-02 08:00'),
('RQ07','A_ZNN', 'family:elder',      'family',    'R_ELDER', '家庭模式 · 大字只读 · 异常提醒','approved','2026-07-01 20:10','family:keeper','2026-07-02 08:00');

-- 8.10.6 还款与账单提醒（原件 pending 提醒）
INSERT INTO reminder (reminder_id, identity_id, ref_type, ref_id, due_day, amount, text, lead_days, status) VALUES
('RM01','family:keeper',      '贷款','LN004', 5,6800.00,'房贷 · 每月 5 日 ¥6,800，请提前一日留足余额',1,'active'),
('RM02','family:keeper',      '贷款','LN005', 8,1200.00,'消费贷 · 每月 8 日 ¥1,200，请留意扣款',1,'active'),
('RM03','personal:self',      '贷款','LN003', 8,8000.00,'消费贷 · 每月 8 日 ¥8,000，月供占收入 53.3%',1,'active'),
('RM04','enterprise:operator','贷款','LN001',15,8900.00,'经营贷 · 每月 15 日 ¥8,900',1,'active'),
('RM05','enterprise:operator','信用卡','CARD02',15,NULL ,'信用卡账单日 · 每月 15 日',3,'active');

-- 8.10.7 健康分档规则（原件 HEALTH_FORMULA；权重 40 / 30 / 30）
INSERT INTO health_rule (rule_id, dimension, lower_bound, upper_bound, score, weight_pct, note) VALUES
('HR01','负债压力', 0.0000, 0.1000, 95,40,'DTI ≤10% 负债压力很小'),
('HR02','负债压力',10.0000,30.0000, 70,40,'10–30% 负债适中'),
('HR03','负债压力',30.0000,50.0000, 50,40,'30–50% 负债偏大'),
('HR04','负债压力',50.0000,NULL   , 35,40,'>50% 月供占收入一半以上'),
('HR05','现金缓冲', 0.0000, 2.5000, 40,30,'不足 2.5 个月'),
('HR06','现金缓冲', 2.5000, 6.0000, 72,30,'2.5–6 个月（原件把 ≈3.0 个月判为 72 分）'),
('HR07','现金缓冲', 6.0000,NULL   , 95,30,'≥6 个月，充足'),
('HR08','保障覆盖', 0.0000,20.0000, 35,30,'<20% 缺口大'),
('HR09','保障覆盖',20.0000,40.0000, 45,30,'20–40%'),
('HR10','保障覆盖',40.0000,60.0000, 55,30,'40–60%'),
('HR11','保障覆盖',60.0000,80.0000, 80,30,'60–80%'),
('HR12','保障覆盖',80.0000,NULL   , 90,30,'≥80% 覆盖充足');

-- 8.11 技能（严格按原件 SKILLS：6 域 × 3 项，权限码只有 read/write/main）
INSERT INTO skill (skill_id, domain, name, icon, required_perm, summary, output_desc, sort_no) VALUES
('S01','账务域','智能对账','ledger','write','流水与票据自动比对，标记异常','异常清单',1),
('S02','账务域','收支分析','pie','read','分类占比、环比、大额异常','分析卡片',2),
('S03','账务域','预算规划','target','write','按历史设定预算并跟踪','执行进度',3),
('S04','税务域','增值税测算','receipt','read','按账目推算应纳增值税','应纳税额',4),
('S05','税务域','个税汇算','wallet','read','专项附加扣除后综合所得汇算','汇算结果',5),
('S06','税务域','政策匹配','book','read','匹配可享税收政策','可享清单',6),
('S07','信贷域','还款提醒','calendar','read','按还款日提前提醒','提醒清单',7),
('S08','信贷域','DTI 健康度','scale','read','测算负债收入比与档位','健康度评分',8),
('S09','信贷域','提前还款模拟','card','write','测算提前还款的节省与方案','方案对比',9),
('S10','保障域','保障缺口分析','shield','read','家庭责任与已保额差额','缺口金额',10),
('S11','保障域','保单归集','folder','write','多张保单归集与台账','保单台账',11),
('S12','保障域','续保提醒','bell','read','按到期日提醒续保','提醒清单',12),
('S13','审计域','证据链追溯','link','read','点开凭证看原始依据与判定规则','完整链路',13),
('S14','审计域','操作审计回放','rewind','read','回放操作与变更历史','审计报告',14),
('S15','审计域','数据沙盒','flow','read','查看数据在系统里的流转','数据流图',15),
('S16','协作域','成员授权','users','main','管理子账号与挂载（主账号专属）','权限变更',16),
('S17','协作域','权限矩阵','grid','main','查看各身份权限（主账号专属）','权限矩阵',17),
('S18','协作域','数据导出','download','write','导出账目与报告（需二次确认并留痕）','CSV / 报告',18);

-- 8.12 审计日志示例
INSERT INTO audit_log (audit_id, actor_identity, action, target_type, target_id, detail, is_confirmed) VALUES
('AU001','enterprise:operator','挂载账本','book_share','SH01','{"给":"enterprise:investor","角色":"投资人"}',1),
('AU002','enterprise:operator','导出数据','book','BOOK_E','{"范围":"2026年9月"}',1),
('AU003','enterprise:investor','查看对账结果','book','BOOK_E','{"来源":"被授权挂载"}',0);

-- ============================================================================
-- 第九部分：校验查询
-- ============================================================================

-- 9.1 每个身份能看到哪些账本（自己的读写 + 被挂载的只读）—— 授权链一眼看清
-- SELECT v.identity_id AS 身份, v.book_name AS 账本, v.access_label AS 权限, v.mount_role AS 挂载角色
-- FROM v_identity_books v ORDER BY v.identity_id, v.access_type;

-- 9.2 每个身份的有效权限（替代原作 PERMS）
-- SELECT identity_id, GROUP_CONCAT(perm_code) AS 权限 FROM v_identity_perm GROUP BY identity_id;

-- 9.3 子账号越权检查：挂载为 summary 的身份不应看到原始流水
-- SELECT s.guest_identity, s.mount_role, s.view_level FROM book_share s WHERE s.view_level='summary';

-- 9.4 负债率（月供 10100+6800=16900 / 月收入 120000 ≈ 14%）
-- SELECT identity_id, monthly_pay, monthly_income, dti_pct, dti_level FROM v_credit_health;

-- 9.5 保障缺口
-- SELECT identity_id, total_assured, family_duty, gap_amount FROM v_coverage_gap;

-- 9.6 主账号专属技能检查：子账号是否被授予了 main 权限（应返回空）
-- SELECT i.identity_id FROM account_identity i
-- JOIN v_identity_perm v ON v.identity_id = i.identity_id
-- WHERE i.level='sub' AND v.perm_code='main';

-- ============================================================================
-- 脚本结束
-- ============================================================================