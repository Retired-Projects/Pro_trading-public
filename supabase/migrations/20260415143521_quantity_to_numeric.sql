-- holdings, orders, trade_logs 테이블의 quantity 컬럼을
-- integer → numeric(18,8) 으로 변경 (코인 소숫점 거래 지원)

ALTER TABLE holdings
  ALTER COLUMN quantity TYPE numeric(18,8) USING quantity::numeric(18,8);

ALTER TABLE orders
  ALTER COLUMN quantity TYPE numeric(18,8) USING quantity::numeric(18,8),
  ALTER COLUMN filled_quantity TYPE numeric(18,8) USING filled_quantity::numeric(18,8);

ALTER TABLE trade_logs
  ALTER COLUMN quantity TYPE numeric(18,8) USING quantity::numeric(18,8);
