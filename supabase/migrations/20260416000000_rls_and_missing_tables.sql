-- =============================================================
-- 1. 누락된 테이블 생성 (watchlist, ai_reports)
-- =============================================================

CREATE TABLE IF NOT EXISTS watchlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  stock_code  TEXT NOT NULL,
  stock_name  TEXT NOT NULL,
  market      TEXT NOT NULL DEFAULT 'KR',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, stock_code)
);

CREATE TABLE IF NOT EXISTS ai_reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  report_date  DATE NOT NULL,
  content      TEXT NOT NULL,
  trade_count  INTEGER NOT NULL DEFAULT 0,
  total_asset  DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_return DOUBLE PRECISION NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, report_date)
);

-- =============================================================
-- 2. 누락된 인덱스 추가
-- =============================================================

CREATE INDEX IF NOT EXISTS idx_watchlist_user
  ON watchlist(user_id);

CREATE INDEX IF NOT EXISTS idx_ai_reports_user
  ON ai_reports(user_id);

CREATE INDEX IF NOT EXISTS idx_ai_reports_user_date
  ON ai_reports(user_id, report_date DESC);

CREATE INDEX IF NOT EXISTS idx_trade_logs_user_date
  ON trade_logs(user_id, executed_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_user
  ON orders(user_id);

-- =============================================================
-- 3. RLS 활성화
-- =============================================================

ALTER TABLE profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE holdings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_reports ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- 4. RLS 정책 — profiles
-- =============================================================

CREATE POLICY "profiles: select own"
  ON profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "profiles: insert own"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "profiles: update own"
  ON profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "profiles: delete own"
  ON profiles FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================
-- 5. RLS 정책 — holdings
-- =============================================================

CREATE POLICY "holdings: select own"
  ON holdings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "holdings: insert own"
  ON holdings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "holdings: update own"
  ON holdings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "holdings: delete own"
  ON holdings FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================
-- 6. RLS 정책 — orders
-- =============================================================

CREATE POLICY "orders: select own"
  ON orders FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "orders: insert own"
  ON orders FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "orders: update own"
  ON orders FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "orders: delete own"
  ON orders FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================
-- 7. RLS 정책 — trade_logs
-- =============================================================

CREATE POLICY "trade_logs: select own"
  ON trade_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "trade_logs: insert own"
  ON trade_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "trade_logs: delete own"
  ON trade_logs FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================
-- 8. RLS 정책 — watchlist
-- =============================================================

CREATE POLICY "watchlist: select own"
  ON watchlist FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "watchlist: insert own"
  ON watchlist FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "watchlist: delete own"
  ON watchlist FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================================
-- 9. RLS 정책 — ai_reports
-- =============================================================

CREATE POLICY "ai_reports: select own"
  ON ai_reports FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "ai_reports: insert own"
  ON ai_reports FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "ai_reports: upsert own"
  ON ai_reports FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "ai_reports: delete own"
  ON ai_reports FOR DELETE
  USING (auth.uid() = user_id);
