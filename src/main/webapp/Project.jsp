<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="java.io.*, java.net.*, java.util.*, java.time.*, java.time.format.*" %>
<%@ page import="javax.xml.parsers.*, org.w3c.dom.*" %>
<%
    // 1. 요청 파라미터 수신 및 기본값 설정 (기본: 전북특별자치도 군산시 옥산면)
    String step1 = request.getParameter("step1");
    String step2 = request.getParameter("step2");
    String step3 = request.getParameter("step3");
    String nxStr = request.getParameter("nx");
    String nyStr = request.getParameter("ny");

    if (step1 == null || step1.trim().isEmpty()) step1 = "전북특별자치도";
    if (step2 == null || step2.trim().isEmpty()) step2 = "군산시";
    if (step3 == null || step3.trim().isEmpty()) step3 = "옥산면";
    if (nxStr == null || nxStr.trim().isEmpty()) nxStr = "56";
    if (nyStr == null || nyStr.trim().isEmpty()) nyStr = "92";

    // 2. 기상청 초단기예보 API 호출 (실시간 날씨 + 최근 6시간 추이 파싱)
    String curTemp = "-", curHum = "-", curPrec = "-";
    List<Map<String, Object>> sixHourList = new ArrayList<>();

    try {
        LocalDateTime now = LocalDateTime.now();
        if (now.getMinute() < 45) {
            now = now.minusHours(1);
        }
        String baseDate = now.format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        String baseTime = now.format(DateTimeFormatter.ofPattern("HH")) + "30";

        // 💡 본인의 공공데이터포럼 기상청 일반 인증키를 넣어주세요.
        String serviceKey = "236574ac78cdead11605282237659f54d547c934f441c46e1734dab4d2d65f19"; 
        
        String apiURL = "http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtFcst"
                     + "?serviceKey=" + serviceKey
                     + "&pageNo=1&numOfRows=60&dataType=XML"
                     + "&base_date=" + baseDate
                     + "&base_time=" + baseTime
                     + "&nx=" + nxStr + "&ny=" + nyStr;

        URL url = new URL(apiURL);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(5000);

        if (conn.getResponseCode() == 200) {
            DocumentBuilderFactory dbFactory = DocumentBuilderFactory.newInstance();
            DocumentBuilder dBuilder = dbFactory.newDocumentBuilder();
            Document doc = dBuilder.parse(conn.getInputStream());
            doc.getDocumentElement().normalize();

            NodeList nList = doc.getElementsByTagName("item");
            Map<String, Map<String, String>> timeMap = new LinkedHashMap<>();

            for (int i = 0; i < nList.getLength(); i++) {
                Element element = (Element) nList.item(i);
                String category = element.getElementsByTagName("category").item(0).getTextContent();
                String fcstTime = element.getElementsByTagName("fcstTime").item(0).getTextContent();
                String fcstValue = element.getElementsByTagName("fcstValue").item(0).getTextContent();

                // 실시간 현재 기상 데이터 추출
                if ("T1H".equals(category) && "-".equals(curTemp)) curTemp = fcstValue;
                if ("REH".equals(category) && "-".equals(curHum)) curHum = fcstValue;
                if ("RN1".equals(category) && "-".equals(curPrec)) curPrec = fcstValue;

                // 시각별 예보/관측 데이터 그룹핑 (6시간 범위)
                timeMap.putIfAbsent(fcstTime, new HashMap<>());
                timeMap.get(fcstTime).put(category, fcstValue);
            }

            // 6시간 데이터 리스트 구성
            int count = 0;
            for (String time : timeMap.keySet()) {
                if (count >= 6) break;
                Map<String, String> catMap = timeMap.get(time);
                
                Map<String, Object> map = new HashMap<>();
                String formattedTime = time.substring(0, 2) + ":" + time.substring(2, 4);
                map.put("time", formattedTime);
                map.put("temp", Double.parseDouble(catMap.getOrDefault("T1H", "0")));
                map.put("hum", Double.parseDouble(catMap.getOrDefault("REH", "0")));
                sixHourList.add(map);
                count++;
            }
        }
    } catch (Exception e) {
        e.printStackTrace();
    }
%>
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>실시간 날씨 및 6시간 추이 시각화</title>
    <!-- Chart.js CDN -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f7f6; margin: 20px; }
        .card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.08); margin-bottom: 25px; }
        h2 { margin-top: 0; color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .form-group { display: flex; gap: 10px; margin-bottom: 20px; align-items: center; }
        select, button { padding: 10px 14px; font-size: 15px; border-radius: 6px; border: 1px solid #ccc; }
        button { background-color: #3498db; color: white; border: none; cursor: pointer; font-weight: bold; }
        button:hover { background-color: #2980b9; }
        .weather-info { display: flex; gap: 20px; margin-top: 15px; }
        .info-box { flex: 1; background: #ebf5fb; padding: 15px; border-radius: 8px; text-align: center; }
        .info-box h3 { margin: 0 0 10px 0; color: #2980b9; font-size: 16px; }
        .info-box p { margin: 0; font-size: 22px; font-weight: bold; color: #2c3e50; }
        .chart-container { position: relative; height: 350px; width: 100%; }
    </style>
</head>
<body>

    <!-- 1. 지역 선택 박스 (location.json 연동) -->
    <div class="card">
        <h2>📍 지역 선택 및 실시간 날씨</h2>
        <form method="GET" action="Project.jsp" id="weatherForm">
            <div class="form-group">
                <select id="step1Select" name="step1"><option value="">1단계 (시·도)</option></select>
                <select id="step2Select" name="step2"><option value="">2단계 (시·군·구)</option></select>
                <select id="step3Select" name="step3"><option value="">3단계 (읍·면·동)</option></select>
                
                <input type="hidden" id="nxInput" name="nx" value="<%= nxStr %>">
                <input type="hidden" id="nyInput" name="ny" value="<%= nyStr %>">
                <button type="submit">날씨 조회</button>
            </div>
        </form>

        <div class="weather-info">
            <div class="info-box">
                <h3>선택 지역</h3>
                <p><%= step1 %> <%= step2 %> <%= step3 %></p>
            </div>
            <div class="info-box">
                <h3>현재 기온</h3>
                <p><%= curTemp %> ℃</p>
            </div>
            <div class="info-box">
                <h3>현재 습도</h3>
                <p><%= curHum %> %</p>
            </div>
            <div class="info-box">
                <h3>1시간 강수량</h3>
                <p><%= curPrec %> mm</p>
            </div>
        </div>
    </div>

    <!-- 2. 최근 6시간 날씨 추이 그래프 (Chart.js) -->
    <div class="card">
        <h2>📊 최근 6시간 날씨 변화 추이</h2>
        <% if (sixHourList.isEmpty()) { %>
            <p style="text-align: center; color: #7f8c8d; padding: 40px 0;">
                기상청 API 응답 데이터를 불러오는 중입니다...
            </p>
        <% } else { %>
            <div class="chart-container">
                <canvas id="weatherChart"></canvas>
            </div>
        <% } %>
    </div>

    <!-- 3. location.json 드롭다운 생성 및 Chart.js 시각화 -->
    <script>
        let locationData = [];
        const selectedStep1 = "<%= step1 %>";
        const selectedStep2 = "<%= step2 %>";
        const selectedStep3 = "<%= step3 %>";

        fetch('./location.json')
            .then(res => res.json())
            .then(data => {
                locationData = data;
                initStep1();
            })
            .catch(err => console.error("location.json 로드 실패:", err));

        function initStep1() {
            const step1Select = document.getElementById('step1Select');
            const step1Set = new Set(locationData.map(item => item["1단계"]));
            
            step1Set.forEach(val => {
                if (val) {
                    const opt = document.createElement('option');
                    opt.value = val;
                    opt.textContent = val;
                    if (val === selectedStep1) opt.selected = true;
                    step1Select.appendChild(opt);
                }
            });

            updateStep2();
            step1Select.addEventListener('change', updateStep2);
        }

        function updateStep2() {
            const step1Val = document.getElementById('step1Select').value;
            const step2Select = document.getElementById('step2Select');
            step2Select.innerHTML = '<option value="">2단계 (시·군·구)</option>';

            const filtered = locationData.filter(item => item["1단계"] === step1Val);
            const step2Set = new Set(filtered.map(item => item["2단계"]));

            step2Set.forEach(val => {
                if (val) {
                    const opt = document.createElement('option');
                    opt.value = val;
                    opt.textContent = val;
                    if (val === selectedStep2) opt.selected = true;
                    step2Select.appendChild(opt);
                }
            });

            updateStep3();
            step2Select.addEventListener('change', updateStep3);
        }

        function updateStep3() {
            const step1Val = document.getElementById('step1Select').value;
            const step2Val = document.getElementById('step2Select').value;
            const step3Select = document.getElementById('step3Select');
            step3Select.innerHTML = '<option value="">3단계 (읍·면·동)</option>';

            const filtered = locationData.filter(item => item["1단계"] === step1Val && item["2단계"] === step2Val);

            filtered.forEach(item => {
                const val = item["3단계"];
                if (val) {
                    const opt = document.createElement('option');
                    opt.value = val;
                    opt.textContent = val;
                    if (val === selectedStep3) opt.selected = true;
                    
                    opt.dataset.nx = item["격자 X"];
                    opt.dataset.ny = item["격자 Y"];
                    step3Select.appendChild(opt);
                }
            });

            step3Select.addEventListener('change', function() {
                const selectedOpt = this.options[this.selectedIndex];
                if (selectedOpt && selectedOpt.dataset.nx) {
                    document.getElementById('nxInput').value = selectedOpt.dataset.nx;
                    document.getElementById('nyInput').value = selectedOpt.dataset.ny;
                }
            });
        }

        // Chart.js 시각화
        <% if (!sixHourList.isEmpty()) { %>
            const labels = [
                <% for (int i = 0; i < sixHourList.size(); i++) { %>
                    "<%= sixHourList.get(i).get("time") %>"<%= (i < sixHourList.size() - 1) ? "," : "" %>
                <% } %>
            ];

            const tempData = [
                <% for (int i = 0; i < sixHourList.size(); i++) { %>
                    <%= sixHourList.get(i).get("temp") %><%= (i < sixHourList.size() - 1) ? "," : "" %>
                <% } %>
            ];

            const humData = [
                <% for (int i = 0; i < sixHourList.size(); i++) { %>
                    <%= sixHourList.get(i).get("hum") %><%= (i < sixHourList.size() - 1) ? "," : "" %>
                <% } %>
            ];

            const ctx = document.getElementById('weatherChart').getContext('2d');
            new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [
                        {
                            label: '기온 (℃)',
                            data: tempData,
                            borderColor: '#e74c3c',
                            backgroundColor: 'rgba(231, 76, 60, 0.1)',
                            yAxisID: 'yTemp',
                            tension: 0.3,
                            fill: true
                        },
                        {
                            label: '습도 (%)',
                            data: humData,
                            borderColor: '#3498db',
                            backgroundColor: 'rgba(52, 152, 219, 0.1)',
                            yAxisID: 'yHum',
                            tension: 0.3,
                            fill: true
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        yTemp: {
                            type: 'linear',
                            position: 'left',
                            title: { display: true, text: '기온 (℃)' }
                        },
                        yHum: {
                            type: 'linear',
                            position: 'right',
                            title: { display: true, text: '습도 (%)' },
                            grid: { drawOnChartArea: false }
                        }
                    }
                }
            });
        <% } %>
    </script>
</body>
</html>