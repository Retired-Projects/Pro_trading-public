-- app_config: 앱 버전 관리 및 강제 업데이트 설정
CREATE TABLE IF NOT EXISTS app_config (
  id     bigint PRIMARY KEY DEFAULT 1,
  min_version        text NOT NULL DEFAULT '1.0.0',
  store_url_android  text,
  store_url_ios      text,
  updated_at         timestamptz DEFAULT now(),
  CONSTRAINT single_row CHECK (id = 1)
);

-- 기본값 삽입
INSERT INTO app_config (id, min_version, store_url_android, store_url_ios)
VALUES (
  1,
  '1.0.0',
  'https://play.google.com/store/apps/details?id=com.protrading.app.protrading',
  'https://apps.apple.com/app/id_PLACEHOLDER'
)
ON CONFLICT (id) DO NOTHING;

-- 비로그인 상태에서도 읽기 가능 (버전 체크는 로그인 전에 발생)
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_app_config"
  ON app_config FOR SELECT
  TO anon, authenticated
  USING (true);
