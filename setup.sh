#!/bin/bash
# ======================================================
# Pro-Trading 프로젝트 초기 설정 스크립트
# 실행: chmod +x setup.sh && ./setup.sh
# ======================================================

set -e

echo "🚀 Pro-Trading 초기 설정을 시작합니다..."
echo ""

# 1. Flutter 의존성 설치
echo "📦 [1/4] Flutter 의존성 설치 중..."
flutter pub get
echo "✅ 의존성 설치 완료"
echo ""

# 2. iOS Pod 설치 (macOS인 경우)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 [2/4] iOS CocoaPods 설치 중..."
  cd ios && pod install && cd ..
  echo "✅ CocoaPods 설치 완료"
else
  echo "⏭️  [2/4] macOS가 아니므로 iOS Pod 건너뜀"
fi
echo ""

# 3. 빌드 분석
echo "🔍 [3/4] 코드 분석 중..."
flutter analyze
echo "✅ 코드 분석 통과"
echo ""

# 4. 앱 실행
echo "📱 [4/4] 앱을 실행합니다..."
echo ""
echo "============================================"
echo "  Pro-Trading 설정 완료!"
echo ""
echo "  실행 명령어:"
echo "    flutter run              (기본 디바이스)"
echo "    flutter run -d chrome    (웹 브라우저)"
echo "    flutter run -d macos     (macOS 앱)"
echo ""
echo "  종목: 삼성전자, SK하이닉스, LG에너지솔루션,"
echo "        삼성바이오로직스, 현대차, 기아,"
echo "        셀트리온, POSCO홀딩스"
echo ""
echo "  API: 네이버 금융 (실시간 시세, 무제한)"
echo "============================================"

flutter run
