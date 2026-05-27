#!/bin/bash
#
# <swiftbar.title>China Gold AU9999</swiftbar.title>
# <swiftbar.version>1.0</swiftbar.version>
# <swiftbar.author>DingPanBar</swiftbar.author>
# <swiftbar.desc>上海黄金交易所 Au99.99 实时价格（数据源：新浪行情）</swiftbar.desc>
# <swiftbar.dependencies>bash,curl,awk</swiftbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
#
# SwiftBar 插件：在 macOS 状态栏显示国内黄金 AU9999 实时价。
# 文件名中的 60s 表示每 60 秒自动刷新。

URL="https://hq.sinajs.cn/list=gds_AU9999"

RAW=$(curl -s -H 'Referer: https://finance.sina.com.cn' \
  -H 'User-Agent: Mozilla/5.0' --max-time 8 "$URL")

# 取双引号之间的数据段
DATA=$(printf '%s' "$RAW" | sed -n 's/.*"\(.*\)".*/\1/p')

if [ -z "$DATA" ]; then
  echo "AU9999 N/A | color=#999999"
  echo "---"
  echo "数据获取失败（网络或接口异常）| color=red"
  echo "数据源 | href=https://finance.sina.com.cn/futures/quotes/AU0.shtml"
  echo "立即重试 | refresh=true"
  exit 0
fi

IFS=',' read -r -a F <<< "$DATA"
PRICE=${F[0]}
HIGH=${F[4]}
LOW=${F[5]}
TIME=${F[6]}
PREV=${F[7]}
OPEN=${F[8]}
DATE=${F[12]}

# 涨跌额与涨跌幅（基准：昨收）
DIFF=$(awk -v p="$PRICE" -v c="$PREV" 'BEGIN{printf "%.2f", p-c}')
PCT=$(awk -v p="$PRICE" -v c="$PREV" 'BEGIN{ if(c+0==0){print "0.00"} else {printf "%.2f",(p-c)/c*100} }')

# 中国习惯：涨红跌绿
UP=$(awk -v d="$DIFF" 'BEGIN{print (d+0>=0)?1:0}')
if [ "$UP" -eq 1 ]; then
  COLOR="#E53935"; ARROW="▲"; SIGN="+"
else
  COLOR="#2E7D32"; ARROW="▼"; SIGN=""
fi

# 交易时段判断（北京时间，假设系统时区为中国）
# 上海金：日盘 09:00–15:30；夜盘 20:00–次日 02:30；周日及周一凌晨无夜盘。
DOW=$(date +%u)              # 1=Mon .. 7=Sun
T=$((10#$(date +%H%M)))      # 当前时刻 HHMM 数值
DAY=0; EVE=0; EARLY=0
[ "$T" -ge 900 ]  && [ "$T" -le 1530 ] && DAY=1     # 日盘
[ "$T" -ge 2000 ] && EVE=1                          # 夜盘开盘段(当晚)
[ "$T" -le 230 ]  && EARLY=1                         # 夜盘凌晨段(次日)
CLOSED=1
if   [ "$DOW" -ge 1 ] && [ "$DOW" -le 5 ] && { [ "$DAY" -eq 1 ] || [ "$EVE" -eq 1 ]; }; then CLOSED=0
elif [ "$DOW" -ge 2 ] && [ "$DOW" -le 6 ] && [ "$EARLY" -eq 1 ]; then CLOSED=0   # 周二~周六凌晨=前一晚夜盘延续
fi
if [ "$CLOSED" -eq 1 ]; then
  TREND="--"; STATUS="休市"
else
  TREND="$ARROW"; STATUS="交易中"
fi

# 状态栏标题：系统自动配色（不设 color = 跟随菜单栏深浅自动黑/白）、
# 系统默认字号（不设 font/size = 与原生菜单栏一致），涨跌用 ▲▼，休市用 --。
echo "Au ${PRICE} ${TREND}"

# 下拉详情
echo "---"
echo "AU9999 上海金 · ${STATUS} | font=Menlo"
echo "现价  ${PRICE}   ${SIGN}${DIFF} (${SIGN}${PCT}%) | color=${COLOR} font=Menlo"
echo "今开  ${OPEN}    昨收 ${PREV} | font=Menlo"
echo "最高  ${HIGH}    最低 ${LOW} | font=Menlo"
echo "更新  ${DATE} ${TIME} | font=Menlo color=#999999"
echo "---"
echo "新浪行情详情 | href=https://finance.sina.com.cn/futures/quotes/AU0.shtml"
echo "立即刷新 | refresh=true"
