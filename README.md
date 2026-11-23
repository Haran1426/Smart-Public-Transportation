# 언제와

자주 타는 서울 버스와 지하철의 도착 정보를 Android 홈 화면에서 확인하는 앱입니다.

## 사용 방법

1. [GitHub Releases](https://github.com/Haran1426/Smart-Public-Transportation/releases)에서 APK를 받아 Android 기기에 설치합니다.
2. 처음 실행하면 녹사평역 6호선 응암 방면과 용산03 삼각지역 정류장(03567)의 예시를 볼 수 있습니다. 다른 구간은 **구간 추가**에서 등록합니다. 버스 정류장은 정류장 번호와 다음 정류장을 보고 선택할 수 있습니다.
3. 카드의 **위젯 추가**를 누르고 Android 홈 화면에 배치합니다. 홈 화면을 길게 눌러 위젯 목록에서 **언제와**를 추가하고 구간을 선택할 수도 있습니다.
4. 위젯의 새로고침 버튼을 누르면 앱을 열지 않고 다시 조회할 수 있습니다. 자동 갱신은 Android가 관리하며 지연될 수 있습니다. 위젯에 표시된 마지막 조회 시각을 확인해 주세요.

## 실시간 연결

설정의 **실시간 연결**에서 이용할 교통수단의 API 키를 저장합니다. 처음 보이는 예시 도착 시각은 키 없이 기능을 체험할 수 있도록 표시됩니다.

- 지하철은 서울 열린데이터광장의 지하철 API 인증키를 사용합니다. [서울시 지하철 실시간 도착정보](https://data.seoul.go.kr/dataList/OA-12764/F/1/datasetView.do)
- 버스는 공공데이터포털에서 버스도착정보조회 서비스 이용 승인을 받은 키를 사용합니다. [서울특별시 버스도착정보조회 서비스](https://www.data.go.kr/data/15000314/openapi.do)

키는 기기에 저장되고 조회할 때 각 제공자가 문서화한 HTTP 엔드포인트로 전달됩니다. 버스 노선과 정류장 검색에는 서울시의 2026년 9월 2일 자료를 사용합니다. [서울시 버스 노선 정보 조회](https://data.seoul.go.kr/dataList/OA-1095/L/1/datasetView.do)

## 개발

Flutter 3.44.6과 Android SDK로 빌드할 수 있습니다.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

초기 APK는 설치 테스트를 위해 디버그 키로 서명한 미리보기입니다.
