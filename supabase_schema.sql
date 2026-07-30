-- Pro-Trading Supabase Schema

-- 사용자 프로필
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  nickname TEXT NOT NULL DEFAULT '트레이더',
  balance DOUBLE PRECISION NOT NULL DEFAULT 100000000, -- 예수금 1억원
  total_asset DOUBLE PRECISION NOT NULL DEFAULT 100000000, -- 총 자산 (예수금 + 보유종목)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 보유 종목
CREATE TABLE IF NOT EXISTS holdings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  stock_code TEXT NOT NULL,
  stock_name TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  avg_price DOUBLE PRECISION NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, stock_code)
);

-- 주문
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  stock_code TEXT NOT NULL,
  stock_name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('market', 'limit')),
  side TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
  price DOUBLE PRECISION NOT NULL,
  quantity INTEGER NOT NULL,
  filled_quantity INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'filled', 'partiallyFilled', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  filled_at TIMESTAMPTZ
);

-- 체결 이력
CREATE TABLE IF NOT EXISTS trade_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES orders(id),
  stock_code TEXT NOT NULL,
  stock_name TEXT NOT NULL,
  side TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
  price DOUBLE PRECISION NOT NULL,
  quantity INTEGER NOT NULL,
  fee DOUBLE PRECISION NOT NULL DEFAULT 0,
  tax DOUBLE PRECISION NOT NULL DEFAULT 0,
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 관심종목
CREATE TABLE IF NOT EXISTS watchlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  stock_code  TEXT NOT NULL,
  stock_name  TEXT NOT NULL,
  market      TEXT NOT NULL DEFAULT 'KR',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, stock_code)
);

-- AI 리포트
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

-- Index
CREATE INDEX IF NOT EXISTS idx_holdings_user        ON holdings(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_status   ON orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_user          ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_trade_logs_user      ON trade_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_trade_logs_stock     ON trade_logs(stock_code);
CREATE INDEX IF NOT EXISTS idx_trade_logs_user_date ON trade_logs(user_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_watchlist_user       ON watchlist(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_reports_user_date ON ai_reports(user_id, report_date DESC);

-- RLS
ALTER TABLE profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE holdings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders     ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: own"   ON profiles   FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "holdings: own"   ON holdings   FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "orders: own"     ON orders     FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "trade_logs: own" ON trade_logs FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "watchlist: own"  ON watchlist  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ai_reports: own" ON ai_reports FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
