from flask import Flask, jsonify, render_template_string
import requests
import time

app = Flask(__name__)

# Process start time — used by the /api/status health endpoint
start_time = time.time()

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
}

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>0050 專業儀表板</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-datalabels@2"></script>
    <style>
        body { font-family: "PingFang TC", "Microsoft JhengHei", sans-serif; background: #f0f2f5; color: #1a1a1a; margin: 0; padding: 20px; }
        .container { max-width: 1100px; margin: 0 auto; }

        /* 頂部價格區 */
        .header-box { background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); margin-bottom: 20px; }
        .main-info { display: flex; align-items: center; gap: 20px; margin-bottom: 15px; }
        #price { font-size: 3.2rem; font-weight: 800; line-height: 1; }
        .price-details { display: flex; flex-direction: column; }
        #change { font-size: 1.4rem; font-weight: 600; }
        #update-time { color: #888; font-size: 0.9rem; }

        /* 數據欄位區 */
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 15px; border-top: 1px solid #eee; pt: 15px; padding-top: 15px; }
        .stat-item { display: flex; flex-direction: column; }
        .stat-label { font-size: 0.85rem; color: #666; margin-bottom: 4px; }
        .stat-value { font-size: 1.1rem; font-weight: 600; }

        .up { color: #d63031; }
        .down { color: #27ae60; }

        /* 圖表區 */
        .grid { display: grid; grid-template-columns: 1.5fr 1fr; gap: 20px; }
        .card { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.05); }
        h2 { font-size: 1.1rem; color: #444; margin: 0 0 20px 0; border-left: 4px solid #3498db; padding-left: 10px; }

        @media (max-width: 850px) { .grid { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-box">
            <div style="margin-bottom: 10px; font-weight: bold; color: #555;">元大台灣50 (0050.TW)</div>
            <div class="main-info">
                <span id="price">--</span>
                <div class="price-details">
                    <span id="change">--</span>
                    <span id="update-time">初始化中...</span>
                </div>
            </div>
            <div class="stats-grid">
                <div class="stat-item"><span class="stat-label">昨收</span><span id="yest-price" class="stat-value">--</span></div>
                <div class="stat-item"><span class="stat-label">開盤</span><span id="open-price" class="stat-value">--</span></div>
                <div class="stat-item"><span class="stat-label">最高</span><span id="high-price" class="stat-value">--</span></div>
                <div class="stat-item"><span class="stat-label">最低</span><span id="low-price" class="stat-value">--</span></div>
                <div class="stat-item"><span class="stat-label">成交量</span><span id="volume" class="stat-value">--</span></div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>分時走勢</h2>
                <canvas id="priceChart" height="180"></canvas>
            </div>
            <div class="card">
                <h2>成分股佔比總覽</h2>
                <canvas id="pieChart"></canvas>
            </div>
        </div>
    </div>

    <script>
        Chart.register(ChartDataLabels);
        let priceChart, pieChart;
        const priceData = [];
        const priceLabels = [];

        async function updateData() {
            try {
                const res = await fetch('/api/data?' + Date.now());
                const data = await res.json();
                if(data.error) return;

                // 更新大數字
                const p = data.current_price;
                const y = data.yesterday_price;
                const diff = (p - y).toFixed(2);
                const pct = ((diff / y) * 100).toFixed(2);

                document.getElementById('price').innerText = p.toFixed(2);
                const changeEl = document.getElementById('change');
                changeEl.innerText = `${diff > 0 ? '▲' : '▼'} ${Math.abs(diff)} (${pct}%)`;
                changeEl.className = diff >= 0 ? 'up' : 'down';
                document.getElementById('price').className = diff >= 0 ? 'up' : 'down';

                // 更新數值面板
                document.getElementById('yest-price').innerText = y.toFixed(2);
                document.getElementById('open-price').innerText = data.open.toFixed(2);
                document.getElementById('high-price').innerText = data.high.toFixed(2);
                document.getElementById('low-price').innerText = data.low.toFixed(2);
                document.getElementById('volume').innerText = data.volume.toLocaleString() + ' 張';
                document.getElementById('update-time').innerText = data.time + ' 更新';

                // 更新圖表
                const now = data.time.split(' ')[0]; // 只取時間部分
                if (priceLabels[priceLabels.length - 1] !== now) {
                    priceLabels.push(now);
                    priceData.push(p);
                    if (priceLabels.length > 100) { priceLabels.shift(); priceData.shift(); }
                    priceChart.update('none'); // 無動畫更新
                }
            } catch (e) { console.error("Fetch error", e); }
        }

        function initCharts(holdings) {
            priceChart = new Chart(document.getElementById('priceChart'), {
                type: 'line',
                data: { labels: priceLabels, datasets: [{ data: priceData, borderColor: '#3498db', borderWidth: 2, tension: 0.1, fill: true, backgroundColor: 'rgba(52, 152, 219, 0.05)', pointRadius: 0 }] },
                options: {
                    animation: false, // 關閉動畫提升 1s 更新頻率下的效能
                    interaction: { intersect: false, mode: 'index' },
                    plugins: { legend: { display: false }, datalabels: { display: false } },
                    scales: {
                        x: { ticks: { autoSkip: true, maxTicksLimit: 10 } },
                        y: { ticks: { callback: v => v.toFixed(1) } }
                    }
                }
            });

            pieChart = new Chart(document.getElementById('pieChart'), {
                type: 'pie',
                data: {
                    labels: holdings.map(h => h.name),
                    datasets: [{
                        data: holdings.map(h => h.weight),
                        backgroundColor: ['#e74c3c', '#e67e22', '#f1c40f', '#2ecc71', '#1abc9c', '#3498db', '#9b59b6', '#34495e', '#7f8c8d', '#bdc3c7']
                    }]
                },
                options: {
                    plugins: {
                        legend: { position: 'bottom', labels: { padding: 20, boxWidth: 12 } },
                        datalabels: {
                            color: '#fff',
                            font: { weight: 'bold', size: 12 },
                            formatter: (v, ctx) => v > 5 ? ctx.chart.data.labels[ctx.dataIndex] : ''
                        }
                    }
                }
            });
        }

        async function start() {
            const hRes = await fetch('/api/holdings');
            const holdings = await hRes.json();
            initCharts(holdings);
            updateData();
            setInterval(updateData, 10000);
            }

        start();
    </script>
</body>
</html>
"""


@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)


@app.route('/api/status', methods=['GET'])
def get_status():
    """Health endpoint — required by the CI test stage and the Docker HEALTHCHECK."""
    return jsonify({
        "status": "online",
        "uptime": int(time.time() - start_time)
    })


@app.route('/api/data')
def get_data():
    # 改用 Yahoo Finance：TWSE 的 mis API 會擋雲端機房 IP（Cloud Run 連不到），
    # Yahoo 的 chart API 從雲端可正常存取。輸出 JSON 維持原本格式，前端不需改。
    try:
        url = "https://query1.finance.yahoo.com/v8/finance/chart/0050.TW?interval=1d&range=1d"
        res = requests.get(url, headers=HEADERS, timeout=8).json()
        result = res['chart']['result'][0]
        meta = result['meta']
        quote = (result.get('indicators', {}).get('quote') or [{}])[0]

        def first_valid(arr, default):
            for x in (arr or []):
                if x is not None:
                    return x
            return default

        yest = meta.get('chartPreviousClose') or meta.get('previousClose') or 0.0
        curr = meta.get('regularMarketPrice') or yest
        open_p = first_valid(quote.get('open'), yest)
        high = meta.get('regularMarketDayHigh') or first_valid(quote.get('high'), curr)
        low = meta.get('regularMarketDayLow') or first_valid(quote.get('low'), curr)
        # Yahoo 成交量是「股」，轉成「張」(1 張 = 1000 股)
        volume = int((meta.get('regularMarketVolume') or 0) / 1000)

        ts = meta.get('regularMarketTime')
        tstr = time.strftime('%H:%M:%S', time.gmtime(ts + 8 * 3600)) if ts else '--:--:--'

        return jsonify(
            current_price=float(curr),
            yesterday_price=float(yest),
            open=float(open_p),
            high=float(high),
            low=float(low),
            volume=volume,
            time=tstr,
        )
    except Exception as e:
        return jsonify(error=str(e)), 500


@app.route('/api/holdings')
def get_holdings():
    return jsonify([
        {"name": "台積電", "weight": 52.4}, {"name": "鴻海", "weight": 6.1},
        {"name": "聯發科", "weight": 4.5}, {"name": "富邦金", "weight": 2.8},
        {"name": "台達電", "weight": 2.3}, {"name": "國泰金", "weight": 2.1},
        {"name": "中信金", "weight": 1.9}, {"name": "廣達", "weight": 1.8},
        {"name": "聯電", "weight": 1.6}, {"name": "兆豐金", "weight": 1.4}
    ])
