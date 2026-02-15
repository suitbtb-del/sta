# Limbo 세션 매니저 (n8n) - 확장형 API 자동 실행 디자인 (안정화 버전)

주신 요구사항 반영:
1. API 키/토큰 값: **저장소 하드코딩 금지**, 환경변수로만 주입
2. OTP 코드가 구글메일로 옴: `otpCode` 입력 또는 `BET_OTP_CODE` env로 전달 가능
3. 성공 응답 필드 불명확: **다중 휴리스틱 성공판정 노드** 추가
4. 실패 최소화 요청: **재시도 + 실패 안전 STOP 경로** 추가

---

## 구조 요약

`Manual Trigger → Edit Fields(balance,result,otpCode) → Build Runtime Context → Code`

이후 분기:
- `PAUSE` → `Wait` → `Discord` → `Google Sheets`
- `BET/STOP` → `IF (BET + Auto Enabled?)`
  - false: `Discord` → `Google Sheets`
  - true: `Switch Bet Provider`
    - `generic_http` → `IF (Dry Run?)`
      - true: `Mark Dry Run` → `Discord` → `Google Sheets`
      - false: `Execute Bet API`(재시도 3회) → `IF (API Success?)`
        - success: `Mark API Success` → `Discord` → `Google Sheets`
        - fail/unknown: `Mark API Failed(=STOP)` → `Discord` → `Google Sheets`
    - fallback: `Mark Unsupported Provider(=STOP)` → `Discord` → `Google Sheets`

---

## 안정화 포인트

1. **HTTP 재시도**
- Execute Bet API 노드: `retryOnFail=true`, `maxTries=3`, `waitBetweenTries=3000ms`

2. **응답 성공판정 휴리스틱**
- 다음 중 하나면 성공으로 간주:
  - `success === true`
  - `status/result/state`가 `ok|success|placed|accepted|done`
  - `id|betId|orderId|transactionId` 존재
- 그 외는 실패로 처리하여 `STOP`

3. **OTP 코드 대응**
- 입력 필드 `otpCode` 추가
- `X-OTP-Code` 헤더로 API 전달
- 운영 편의를 위해 `BET_OTP_CODE` env도 지원

4. **관측성 확장**
- Google Sheets에 `otpProvided`, `executionMode`, `betProvider`, `dryRun` 등 기록

---

## 환경변수

- `ENABLE_AUTO_BET` (`true|false`)
- `BET_PROVIDER` (기본 `generic_http`)
- `BET_API_URL`
- `BET_API_KEY`
- `BET_OTP_CODE` (선택)
- `BET_CURRENCY` (기본 `CAD`)
- `AUTO_BET_DRY_RUN` (`true|false`)
- `DISCORD_WEBHOOK_URL`
- `GSHEET_DOC_ID`
- `BET_API_URL` and `BET_API_KEY`는 live 실행 시 필수 (dry-run 제외)

---

## 바로 테스트 권장 순서

1. `ENABLE_AUTO_BET=true`, `AUTO_BET_DRY_RUN=true`
2. `balance/result/otpCode` 넣고 실행
3. Discord/Sheets에 reason/action/log 컬럼 확인
4. dry-run off 전환 후 소액으로 API 실실행 검증

## 파일
- 워크플로우 export JSON: `n8n/limbo-semi-auto-workflow.json`
- 설명 문서: `n8n/README.md`


---

## 적용법 (바로 실행 가능한 순서)

### 0) 준비물
- n8n 인스턴스 접근 권한
- Google Sheets OAuth2 credential
- Discord webhook URL
- Bet API URL / API KEY

### 1) 워크플로우 가져오기
1. n8n 접속 → **Workflows**
2. 우측 상단 **Import from File**
3. `n8n/limbo-semi-auto-workflow.json` 선택
4. 저장(Save)

### 2) 자격증명/환경변수 세팅
n8n 환경변수(또는 Docker env) 설정:
- `ENABLE_AUTO_BET=true` (초기 테스트는 true 유지)
- `AUTO_BET_DRY_RUN=true` (**처음엔 반드시 true 권장**)
- `BET_PROVIDER=generic_http`
- `BET_API_URL=<실제 베팅 API>`
- `BET_API_KEY=<실제 API 키>`
- `BET_OTP_CODE=` (옵션, 없으면 실행 시 `otpCode` 수동입력)
- `BET_CURRENCY=CAD`
- `DISCORD_WEBHOOK_URL=<디스코드 웹훅>`
- `GSHEET_DOC_ID=<시트 문서 ID>`

그리고 워크플로우에서:
- Google Sheets 노드 2개에 credential 연결



### 2-1) n8n API로 워크플로우 바로 적용 (토큰 사용)
주신 값처럼 **n8n Public API 키**가 있으면 UI import 없이 반영할 수 있습니다.

```bash
export N8N_BASE_URL="https://<your-n8n-host>"
export N8N_API_KEY="<여기에 n8n api 키>"
./n8n/scripts/apply_via_n8n_api.sh
```

- 동작: 같은 이름의 워크플로우가 있으면 `PUT` 업데이트, 없으면 `POST` 생성
- 스크립트 파일: `n8n/scripts/apply_via_n8n_api.sh`
- 보안: API 키는 파일에 하드코딩하지 말고 환경변수로만 주입



### 2-2) 운영 키 적용(로컬 env 주입)
아래는 **로컬 쉘에서만** 실행하세요. (보안상 저장소 파일에는 키를 넣지 않음)

```bash
export DISCORD_WEBHOOK_URL='<discord_webhook_url>'
export BET_API_KEY='<bet_api_key>'
export N8N_BASE_URL='https://<your-n8n-host>'
export N8N_API_KEY='<your n8n public api key>'
export ENABLE_AUTO_BET='true'
export AUTO_BET_DRY_RUN='true'   # 먼저 dry-run
export BET_PROVIDER='generic_http'
export BET_API_URL='https://<your-stake-endpoint>'
export BET_CURRENCY='CAD'
export GSHEET_DOC_ID='<google-sheet-id>'

./n8n/scripts/apply_via_n8n_api.sh
```

실제 베팅 전환:
```bash
export AUTO_BET_DRY_RUN='false'
```

> ⚠️ 키/웹훅은 저장소/채팅에 붙여넣지 말고, 노출 이력이 있으면 즉시 재발급(rotate)하세요.

### 3) 시트 컬럼 생성
Google Sheets `session_log` 시트에 아래 헤더를 1행에 생성:
`timestamp,action,reason,executionMode,betProvider,currency,dryRun,balance,result,pnl,pnlPct,streak,tries,nextBet,nextMultiplier,cooldownUntil,modelName,regime,streakFactor,regimeFactor,hitRateFactor,recentHitRate,otpProvided`

### 4) Dry-run 테스트(실베팅 없음)
1. `Manual Trigger` 실행
2. `Edit Fields`에 입력
   - `balance`: 예) `100`
   - `result`: `win` 또는 `loss`
   - `otpCode`: 메일로 받은 코드(없으면 빈값)
3. Execute Workflow
4. 확인 포인트
   - Discord 메시지 도착
   - Google Sheets 행 추가
   - reason/action이 기대대로 기록

### 5) 소액 실베팅 전환
1. `AUTO_BET_DRY_RUN=false` 변경
2. 아주 작은 금액 상태에서 1~2회 실행
3. API 서버/거래내역에서 실제 주문 반영 확인
4. 이상 없으면 정식 운용

### 6) 장애 시 즉시 안전조치
- `ENABLE_AUTO_BET=false`로 즉시 자동 실행 차단
- reason이 `api_bet_failed_or_unknown_response`면 API 스펙/응답필드 확인
- OTP 실패면 `otpCode` 최신값으로 재실행

### 7) 운영 팁
- 초기 1~2일은 `AUTO_BET_DRY_RUN=true`로 로그만 충분히 수집
- 이후에도 STOP/PAUSE reason을 주기적으로 점검
- provider 확장 시 `Switch Bet Provider`에서 새 브랜치 추가
