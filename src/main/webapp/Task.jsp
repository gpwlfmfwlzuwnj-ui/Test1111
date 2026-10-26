<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.net.URL, java.net.HttpURLConnection" %>
<%@ page import="java.io.BufferedReader, java.io.InputStreamReader, java.io.StringReader" %>
<%@ page import="java.time.LocalDateTime, java.time.format.DateTimeFormatter" %>
<%@ page import="javax.xml.parsers.DocumentBuilderFactory, javax.xml.parsers.DocumentBuilder" %>
<%@ page import="org.w3c.dom.Document, org.w3c.dom.Element, org.w3c.dom.NodeList" %>
<%@ page import="org.xml.sax.InputSource" %>
<%@ page import="java.util.*, java.text.*, com.weather.dao.weather" %>

<%
    request.setCharacterEncoding("UTF-8");

    // 1. 선택 파라미터 및 좌표 전달받기
    String step1 = request.getParameter("step1");
    String step2 = request.getParameter("step2");
    String step3 = request.getParameter("step3");
    String nx = request.getParameter("nx");
    String ny = request.getParameter("ny");

    // 초기 접속 시 기본값 (전북특별자치도 순천시 매곡동 기준: 70, 70)
    if (step1 == null || step1.isEmpty()) step1 = "전북특별자치도";
    if (step2 == null || step2.isEmpty()) step2 = "순천시";
    if (step3 == null || step3.isEmpty()) step3 = "매곡동";
    if (nx == null || nx.isEmpty()) nx = "70";
    if (ny == null || ny.isEmpty()) ny = "70";

    // 2. 현재 시각 기준 기상청 API base_time 계산 (매시 45분 이전이면 1시간 전 30분 데이터 사용)
    LocalDateTime currentNow = LocalDateTime.now();
    String displayExactHour = currentNow.format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:00"));

    LocalDateTime apiNow = currentNow;
    if (apiNow.getMinute() < 45) { 
        apiNow = apiNow.minusHours(1); 
    }
    
    String baseDate = apiNow.format(DateTimeFormatter.ofPattern("yyyyMMdd"));
    String baseTime = apiNow.format(DateTimeFormatter.ofPattern("HH")) + "30";
    String serviceKey = "236574ac78cdead11605282237659f54d547c934f441c46e1734dab4d2d65f19";

    // 3. 기상청 초단기예보 API 호출
    String apiURL = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtFcst"
                  + "?serviceKey=" + serviceKey 
                  + "&pageNo=1&numOfRows=1000&dataType=XML"
                  + "&base_date=" + baseDate 
                  + "&base_time=" + baseTime 
                  + "&nx=" + nx 
                  + "&ny=" + ny;

    String temp = "0";      // T1H (기온)
    String humidity = "0";  // REH (습도)
    String prec = "0";      // RN1 (강수량)
    boolean isSuccess = false;
    String errorMsg = "";

    try {
        URL url = new URL(apiURL);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        
        BufferedReader rd = new BufferedReader(new InputStreamReader(
            (conn.getResponseCode() >= 200 && conn.getResponseCode() <= 300) ? conn.getInputStream() : conn.getErrorStream(), "UTF-8"));
            
        StringBuilder xmlData = new StringBuilder();
        String line;
        while ((line = rd.readLine()) != null) xmlData.append(line);
        rd.close();
        conn.disconnect();

        DocumentBuilder docBuilder = DocumentBuilderFactory.newInstance().newDocumentBuilder();
        Document doc = docBuilder.parse(new InputSource(new StringReader(xmlData.toString())));
        
        NodeList itemList = doc.getElementsByTagName("item");
        if (itemList.getLength() > 0) {
            isSuccess = true;
            for (int i = 0; i < itemList.getLength(); i++) {
                Element element = (Element) itemList.item(i);
                String category = element.getElementsByTagName("category").item(0).getTextContent();
                String fcstValue = element.getElementsByTagName("fcstValue").item(0).getTextContent();

                if ("T1H".equals(category) && "0".equals(temp)) temp = fcstValue;
                if ("REH".equals(category) && "0".equals(humidity)) humidity = fcstValue;
                if ("RN1".equals(category) && "0".equals(prec)) prec = fcstValue;
            }
        } else {
            errorMsg = "API 연동 결과 데이터가 존재하지 않습니다.";
        }
    } catch (Exception e) { 
        errorMsg = e.getMessage();
    }

    // =========================================================================
    // 4. [하단 DB 기록 및 통계 연동 로직]
    // =========================================================================
    String startDate = request.getParameter("startDate");
    String endDate = request.getParameter("endDate");

    // 기본 조회 날짜 설정 (최근 7일)
    SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
    Calendar cal = Calendar.getInstance();
    if (endDate == null || endDate.trim().isEmpty()) {
        endDate = sdf.format(cal.getTime());
    }
    if (startDate == null || startDate.trim().isEmpty()) {
        cal.add(Calendar.DATE, -7);
        startDate = sdf.format(cal.getTime());
    }

    // 💡 핵심: 3단계를 선택하셨더라도 DB 조회를 위해 1단계 + 2단계 조합으로만 정제
    String targetDbRegion = "";
    if (step1 != null && !step1.trim().isEmpty()) {
        if (step2 != null && !step2.trim().isEmpty()) {
            targetDbRegion = step1.trim() + " " + step2.trim();
        } else {
            targetDbRegion = step1.trim(); // 이어도 등 1단계 단독 지역
        }
    }

    // DB 데이터 및 통계 변수 선언
    List<Map<String, Object>> historyList = new ArrayList<>();
    double avgTemp = 0.0, maxTemp = -999.0, minTemp = 999.0, avgHumidity = 0.0;
    int dataCount = 0;

    if (!targetDbRegion.isEmpty()) {
        weather weatherDAO = new weather();
        historyList = weatherDAO.getHistoryData(targetDbRegion, startDate, endDate);

        if (!historyList.isEmpty()) {
            double sumTemp = 0.0;
            double sumHum = 0.0;
            dataCount = historyList.size();

            for (Map<String, Object> row : historyList) {
                double t = (Double) row.get("temp");
                double h = (Double) row.get("humidity");

                sumTemp += t;
                sumHum += h;
                if (t > maxTemp) maxTemp = t;
                if (t < minTemp) minTemp = t;
            }
            avgTemp = Math.round((sumTemp / dataCount) * 10.0) / 10.0;
            avgHumidity = Math.round((sumHum / dataCount) * 10.0) / 10.0;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>행정구역 선택 날씨 조회 (Task.jsp)</title>
<!-- Chart.js CDN 추가 -->
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

<style>
    body { font-family: 'Noto Sans KR', sans-serif; margin: 30px; background-color: #f8f9fa; }
    .card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); width: 680px; margin-bottom: 20px; }
    select { padding: 8px; margin-right: 8px; border: 1px solid #ced4da; border-radius: 4px; min-width: 140px; }
    button { padding: 8px 18px; background: #0d6efd; color: white; border: none; border-radius: 4px; cursor: pointer; font-weight: bold; }
    button:hover { background: #0b5ed7; }
    table { border-collapse: collapse; width: 100%; margin-top: 15px; text-align: center; }
    th, td { border: 1px solid #dee2e6; padding: 10px; }
    th { background: #0d6efd; color: white; }
    .location-badge { background: #e7f5ff; color: #1c7ed6; padding: 4px 10px; border-radius: 4px; font-weight: bold; }

    /* 하단 통계 및 그래프 스타일 */
    .stats-grid {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 12px;
        margin: 15px 0;
    }
    .stat-card {
        padding: 12px;
        background: #f8f9fa;
        border-radius: 6px;
        text-align: center;
        border-left: 4px solid #0d6efd;
    }
    .stat-card h4 { margin: 0 0 5px 0; font-size: 13px; color: #6c757d; }
    .stat-card p { margin: 0; font-size: 18px; font-weight: bold; color: #212529; }
    .chart-box {
        position: relative;
        height: 320px;
        margin-top: 15px;
    }
</style>
</head>
<body>

<!-- 1. 행정구역 선택 카탈로그 -->
<div class="card">
    <h2>📍 행정구역 선택 (1단계 ➔ 2단계 ➔ 3단계)</h2>
    <form method="get" action="Task.jsp" id="weatherForm">
        <!-- 3단계 선택 박스 -->
        <select id="step1Select" onchange="onStep1Change()"><option value="">1단계 선택</option></select>
        <select id="step2Select" onchange="onStep2Change()"><option value="">2단계 선택</option></select>
        <select id="step3Select" onchange="onStep3Change()"><option value="">3단계 선택</option></select>

        <!-- 서버로 넘길 Hidden 좌표 및 지역 정보 -->
        <input type="hidden" name="step1" id="step1Input" value="<%= step1 %>">
        <input type="hidden" name="step2" id="step2Input" value="<%= step2 %>">
        <input type="hidden" name="step3" id="step3Input" value="<%= step3 %>">
        <input type="hidden" name="nx" id="nxInput" value="<%= nx %>">
        <input type="hidden" name="ny" id="nyInput" value="<%= ny %>">

        <button type="submit">날씨 조회</button>
    </form>
</div>

<!-- 2. 선택 지역 실시간 날씨 정보 -->
<div class="card">
    <h2>🌤️ 선택된 지역의 실시간 날씨 정보</h2>
    <p><b>선택 위치:</b> <span class="location-badge"><%= step1 %> <%= step2 %> <%= step3 %></span></p>
    <p><b>자동 검색된 격자 좌표 (nx, ny):</b> (<%= nx %>, <%= ny %>)</p>
    <p><b>조회 기준 시간:</b> <%= displayExactHour %></p>

    <% if (isSuccess) { %>
    <table>
        <tr>
            <th>항목명</th>
            <th>측정/예보 값</th>
        </tr>
        <tr>
            <td><b>기온 (T1H)</b></td>
            <td><%= temp %> ℃</td>
        </tr>
        <tr>
            <td><b>습도 (REH)</b></td>
            <td><%= humidity %> %</td>
        </tr>
        <tr>
            <td><b>강수량 (RN1)</b></td>
            <td><%= prec %> mm</td>
        </tr>
    </table>
    <% } else { %>
    <p style="color:red;"><b>조회 실패:</b> <%= errorMsg %></p>
    <% } %>
</div>

<!-- 3. 과거 DB 날씨 기록, 통계 및 그래프 표시 영역 -->
<div class="card">
    <h2>📊 과거 날씨 기록 및 통계 분석</h2>
    
    <!-- 기간 선택 서브 폼 -->
    <form method="get" action="Task.jsp" style="margin-bottom: 15px;">
        <!-- 선택된 지역 파라미터 유지용 hidden 태그 -->
        <input type="hidden" name="step1" value="<%= step1 %>">
        <input type="hidden" name="step2" value="<%= step2 %>">
        <input type="hidden" name="step3" value="<%= step3 %>">
        <input type="hidden" name="nx" value="<%= nx %>">
        <input type="hidden" name="ny" value="<%= ny %>">

        <label><b>조회 기간:</b> </label>
        <input type="date" name="startDate" value="<%= startDate %>" style="padding: 5px; border: 1px solid #ced4da; border-radius: 4px;"> ~ 
        <input type="date" name="endDate" value="<%= endDate %>" style="padding: 5px; border: 1px solid #ced4da; border-radius: 4px;">
        <button type="submit" style="padding: 6px 12px; margin-left: 5px;">기록 조회</button>
    </form>

    <% if (!targetDbRegion.isEmpty()) { %>
        <p style="font-size: 0.95em; color: #495057;">
            <b>DB 검색 매핑 키:</b> <span class="location-badge" style="background: #e6fcf5; color: #0ca678;"><%= targetDbRegion %></span>
            <br><span style="color: #868e96; font-size: 0.85em;">* 3단계를 선택하셨더라도 DB에 저장된 1·2단계 기준 키로 정확히 매핑하여 조회합니다.</span>
        </p>

        <% if (dataCount > 0) { %>
            <!-- 통계 요약 카드 4종 -->
            <div class="stats-grid">
                <div class="stat-card" style="border-left-color: #2b8a3e;">
                    <h4>평균 기온</h4>
                    <p><%= avgTemp %> ℃</p>
                </div>
                <div class="stat-card" style="border-left-color: #e03131;">
                    <h4>최고 기온</h4>
                    <p><%= maxTemp %> ℃</p>
                </div>
                <div class="stat-card" style="border-left-color: #15aabf;">
                    <h4>최저 기온</h4>
                    <p><%= minTemp %> ℃</p>
                </div>
                <div class="stat-card" style="border-left-color: #f59f00;">
                    <h4>평균 습도</h4>
                    <p><%= avgHumidity %> %</p>
                </div>
            </div>

            <!-- Chart.js 꺾은선 그래프 영역 -->
            <div class="chart-box">
                <canvas id="weatherChart"></canvas>
            </div>

            <script>
                const labels = [];
                const tempData = [];
                const humData = [];

                <% for (Map<String, Object> row : historyList) { %>
                    labels.push("<%= row.get("obs_time").toString().substring(5, 16) %>");
                    tempData.push(<%= row.get("temp") %>);
                    humData.push(<%= row.get("humidity") %>);
                <% } %>

                const ctx = document.getElementById('weatherChart').getContext('2d');
                new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [
                            {
                                label: '기온 (℃)',
                                data: tempData,
                                borderColor: '#e03131',
                                backgroundColor: 'rgba(224, 49, 49, 0.1)',
                                borderWidth: 2,
                                tension: 0.2,
                                yAxisID: 'y'
                            },
                            {
                                label: '습도 (%)',
                                data: humData,
                                borderColor: '#1c7ed6',
                                backgroundColor: 'rgba(28, 126, 214, 0.1)',
                                borderWidth: 2,
                                tension: 0.2,
                                yAxisID: 'y1'
                            }
                        ]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                type: 'linear',
                                display: true,
                                position: 'left',
                                title: { display: true, text: '기온 (℃)' }
                            },
                            y1: {
                                type: 'linear',
                                display: true,
                                position: 'right',
                                grid: { drawOnChartArea: false },
                                title: { display: true, text: '습도 (%)' }
                            }
                        }
                    }
                });
            </script>
        <% } else { %>
            <div style="padding: 20px; text-align: center; background: #fff5f5; border: 1px solid #ffc9c9; border-radius: 6px; color: #c92a2a; margin-top: 10px;">
                ⚠️ 선택하신 기간(<b><%= startDate %> ~ <%= endDate %></b>) 동안 DB에 수집된 날씨 기록이 없습니다.
            </div>
        <% } %>
    <% } %>
</div>

<script>
let rawData = [];

// 1. location.json 로드
fetch('./location.json')
    .then(response => {
        if (!response.ok) {
            throw new Error("location.json 파일을 찾을 수 없습니다. (HTTP " + response.status + ")");
        }
        return response.json();
    })
    .then(data => {
        rawData = data;
        console.log("JSON 데이터 로드 완료:", rawData.length, "건");
        initStep1Options("<%= step1 %>", "<%= step2 %>", "<%= step3 %>");
    })
    .catch(err => {
        console.error("오류 발생:", err);
        alert("지역 목록 데이터(location.json)를 불러오지 못했습니다.\n파일 위치를 확인해주세요.\n\n" + err.message);
    });

// 1단계 옵션 생성
function initStep1Options(target1, target2, target3) {
    const s1Select = document.getElementById("step1Select");
    s1Select.innerHTML = '<option value="">1단계 선택</option>';

    const step1Set = new Set();
    rawData.forEach(item => {
        let val1 = item["1단계"] || item["1단계 "] || item["step1"];
        if (val1 && val1.trim() !== "") {
            step1Set.add(val1.trim());
        }
    });

    step1Set.forEach(val => {
        let opt = new Option(val, val);
        if (val === target1) opt.selected = true;
        s1Select.add(opt);
    });

    if (target1 && step1Set.has(target1)) {
        onStep1Change(target2, target3);
    }
}

// 1단계 변경 시 -> 2단계 옵션 갱신
function onStep1Change(target2, target3) {
    const s1Val = document.getElementById("step1Select").value;
    const s2Select = document.getElementById("step2Select");
    const s3Select = document.getElementById("step3Select");
    
    s2Select.innerHTML = '<option value="">2단계 선택</option>';
    s3Select.innerHTML = '<option value="">3단계 선택</option>';

    if (!s1Val) return;
    document.getElementById("step1Input").value = s1Val;

    const step2Set = new Set();
    rawData.filter(item => {
        let val1 = item["1단계"] || item["1단계 "] || item["step1"];
        return val1 && val1.trim() === s1Val;
    }).forEach(item => {
        let val2 = item["2단계"] || item["2단계 "] || item["step2"];
        if (val2 && val2.trim() !== "") {
            step2Set.add(val2.trim());
        }
    });

    step2Set.forEach(val => {
        let opt = new Option(val, val);
        if (val === target2) opt.selected = true;
        s2Select.add(opt);
    });

    if (target2 && step2Set.has(target2)) {
        onStep2Change(target3);
    }
}

// 2단계 변경 시 -> 3단계 옵션 갱신
function onStep2Change(target3) {
    const s1Val = document.getElementById("step1Select").value;
    const s2Val = document.getElementById("step2Select").value;
    const s3Select = document.getElementById("step3Select");

    s3Select.innerHTML = '<option value="">3단계 선택</option>';

    if (!s1Val || !s2Val) return;
    document.getElementById("step2Input").value = s2Val;

    const step3Set = new Set();
    rawData.filter(item => {
        let val1 = item["1단계"] || item["1단계 "] || item["step1"];
        let val2 = item["2단계"] || item["2단계 "] || item["step2"];
        return val1 && val1.trim() === s1Val && val2 && val2.trim() === s2Val;
    }).forEach(item => {
        let val3 = item["3단계"] || item["3단계 "] || item["step3"];
        if (val3 && val3.trim() !== "") {
            step3Set.add(val3.trim());
        }
    });

    step3Set.forEach(val => {
        let opt = new Option(val, val);
        if (val === target3) opt.selected = true;
        s3Select.add(opt);
    });

    if (target3 && step3Set.has(target3)) {
        onStep3Change();
    }
}

// 3단계 변경 시 -> 격자 X, Y 좌표 매핑
function onStep3Change() {
    const s1Val = document.getElementById("step1Select").value;
    const s2Val = document.getElementById("step2Select").value;
    const s3Val = document.getElementById("step3Select").value;

    if (!s1Val || !s2Val || !s3Val) return;
    document.getElementById("step3Input").value = s3Val;

    const matchedItem = rawData.find(item => {
        let val1 = (item["1단계"] || item["step1"] || "").trim();
        let val2 = (item["2단계"] || item["step2"] || "").trim();
        let val3 = (item["3단계"] || item["step3"] || "").trim();
        return val1 === s1Val && val2 === s2Val && val3 === s3Val;
    });

    if (matchedItem) {
        let nx = matchedItem["격자 X"] || matchedItem["격자X"] || matchedItem["nx"];
        let ny = matchedItem["격자 Y"] || matchedItem["격자Y"] || matchedItem["ny"];
        document.getElementById("nxInput").value = nx;
        document.getElementById("nyInput").value = ny;
    }
}
</script>

</body>
</html>