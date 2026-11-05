local candles = {}
local price = 100
for index = 1, 64 do
  local open = price
  local close = open + math.sin(index * 0.42) * 3 + math.sin(index * 1.9) * 1.2
  candles[#candles + 1] = {
    x = index,
    open = open,
    high = math.max(open, close) + 1 + math.abs(math.sin(index * 0.9)) * 2,
    low = math.min(open, close) - 1 - math.abs(math.cos(index * 1.1)) * 2,
    close = close,
  }
  price = close
end
return {
  revision = 1,
  title = "OHLC",
  subtitle = "64 candles · native candle primitive",
  series = {
    { id = "ohlc", label = "OHLC", kind = "candles", up_ink = "success", down_ink = "danger", candles = candles },
  },
}
