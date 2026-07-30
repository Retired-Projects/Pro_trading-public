-- =============================================================
-- 1. profiles.total_asset 컬럼 안전 추가 (이미 있으면 무시)
-- =============================================================
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS total_asset DOUBLE PRECISION;

-- =============================================================
-- 2. 리더보드 RPC 함수 (SECURITY DEFINER — RLS 우회 후 안전한 컬럼만 반환)
-- =============================================================
-- profiles 테이블에 RLS "select own" 정책이 있으면 직접 SELECT가 차단됩니다.
-- SECURITY DEFINER 함수는 함수 소유자(postgres) 권한으로 실행되어 RLS를 우회하지만,
-- nickname과 total_asset 두 컬럼만 노출하므로 개인 식별 정보(balance, email 등)는 숨겨집니다.

CREATE OR REPLACE FUNCTION get_leaderboard()
RETURNS TABLE(nickname TEXT, total_asset DOUBLE PRECISION)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COALESCE(p.nickname, '트레이더') AS nickname,
    COALESCE(p.total_asset, p.balance, 0)::DOUBLE PRECISION AS total_asset
  FROM profiles p
  WHERE
    p.total_asset IS NOT NULL
    OR p.balance IS NOT NULL
  ORDER BY COALESCE(p.total_asset, p.balance, 0) DESC NULLS LAST
  LIMIT 100;
$$;

-- 인증된 사용자 및 익명 클라이언트 모두 호출 가능
GRANT EXECUTE ON FUNCTION get_leaderboard() TO authenticated, anon;

-- =============================================================
-- 3. 성능 인덱스 추가
-- =============================================================

-- 리더보드 정렬 최적화 (total_asset DESC)
CREATE INDEX IF NOT EXISTS idx_profiles_leaderboard
  ON profiles(total_asset DESC NULLS LAST)
  WHERE total_asset IS NOT NULL;

-- 보유 종목 조회 최적화
CREATE INDEX IF NOT EXISTS idx_holdings_user_stock
  ON holdings(user_id, stock_code);

-- 주문 상태별 조회 최적화
CREATE INDEX IF NOT EXISTS idx_orders_user_status_date
  ON orders(user_id, status, created_at DESC);

-- 종목별 체결 내역 조회 최적화
CREATE INDEX IF NOT EXISTS idx_trade_logs_stock_date
  ON trade_logs(stock_code, executed_at DESC);
