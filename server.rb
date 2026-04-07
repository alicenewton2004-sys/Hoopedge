require 'webrick'
require 'net/http'
require 'json'
require 'uri'
require 'dotenv'

Dotenv.load

KALSHI_API_KEY    = ENV['KALSHI_API_KEY']    || ''
ANTHROPIC_API_KEY = ENV['ANTHROPIC_API_KEY'] || ''

CACHE     = {}
CACHE_TTL = 60

def cached(key, &block)
  entry = CACHE[key]
  return entry[:data] if entry && (Time.now - entry[:time]) < CACHE_TTL
  data = block.call
  CACHE[key] = { data: data, time: Time.now }
  data
end

NBA_TEAMS = {
  'Atlanta'      => ['hawks', 'atlanta hawks', 'atlanta'],
  'Boston'       => ['celtics', 'boston celtics', 'boston'],
  'Brooklyn'     => ['nets', 'brooklyn nets', 'brooklyn'],
  'Charlotte'    => ['hornets', 'charlotte hornets', 'charlotte'],
  'Chicago'      => ['bulls', 'chicago bulls', 'chicago'],
  'Cleveland'    => ['cavaliers', 'cavs', 'cleveland cavaliers', 'cleveland'],
  'Dallas'       => ['mavericks', 'mavs', 'dallas mavericks', 'dallas'],
  'Denver'       => ['nuggets', 'denver nuggets', 'denver'],
  'Detroit'      => ['pistons', 'detroit pistons', 'detroit'],
  'Golden State' => ['warriors', 'golden state warriors', 'golden state'],
  'Houston'      => ['rockets', 'houston rockets', 'houston'],
  'Indiana'      => ['pacers', 'indiana pacers', 'indiana'],
  'LA Clippers'  => ['los angeles clippers', 'los angeles c', 'la clippers', 'clippers'],
  'LA Lakers'    => ['los angeles lakers', 'los angeles l', 'los angeles lake', 'la lakers', 'lakers'],
  'Memphis'      => ['grizzlies', 'memphis grizzlies', 'memphis'],
  'Miami'        => ['heat', 'miami heat', 'miami'],
  'Milwaukee'    => ['bucks', 'milwaukee bucks', 'milwaukee'],
  'Minnesota'    => ['timberwolves', 'minnesota timberwolves', 'minnesota'],
  'New Orleans'  => ['pelicans', 'new orleans pelicans', 'new orleans'],
  'New York'     => ['knicks', 'new york knicks', 'new york'],
  'OKC'          => ['thunder', 'oklahoma city thunder', 'oklahoma city', 'oklahoma'],
  'Orlando'      => ['magic', 'orlando magic', 'orlando'],
  'Philadelphia' => ['76ers', 'sixers', 'philadelphia 76ers', 'philadelphia'],
  'Phoenix'      => ['suns', 'phoenix suns', 'phoenix'],
  'Portland'     => ['trail blazers', 'blazers', 'portland trail blazers', 'portland'],
  'Sacramento'   => ['kings', 'sacramento kings', 'sacramento'],
  'San Antonio'  => ['spurs', 'san antonio spurs', 'san antonio'],
  'Toronto'      => ['raptors', 'toronto raptors', 'toronto'],
  'Utah'         => ['jazz', 'utah jazz', 'utah'],
  'Washington'   => ['wizards', 'washington wizards', 'washington'],
}

def normalize_team(text)
  t = text.to_s.downcase.strip
  NBA_TEAMS.each do |canonical, aliases|
    aliases.sort_by { |a| -a.length }.each do |a|
      return canonical if t.include?(a)
    end
  end
  nil
end

# ── Polymarket: NBA Finals championship markets ───────────────────────────────

def fetch_polymarket_finals
  cached('polymarket_finals') do
    uri    = URI('https://gamma-api.polymarket.com/markets?closed=false&limit=200&tag=sports')
    res    = Net::HTTP.get_response(uri)
    markets = JSON.parse(res.body) rescue []

    results = {}
    markets.each do |m|
      title = m['question'] || m['title'] || ''
      next unless title.match?(/nba finals/i)

      team = normalize_team(title)
      next unless team

      prices    = begin JSON.parse(m['outcomePrices'] || '[]') rescue [] end
      yes_price = prices[0].to_f
      next if yes_price.zero?

      # Use the parent event slug (e.g. "2026-nba-champion") for a working URL
          events     = m['events'].is_a?(Array) ? m['events'] : []
          event_slug = events.first&.dig('slug').to_s.strip
          poly_url   = if event_slug.include?('-')
            "https://polymarket.com/event/#{event_slug}"
          else
            "https://polymarket.com/event/2026-nba-champion"
          end

          existing = results[team]
      if existing.nil? || m['volume'].to_f > existing[:volume]
          results[team] = {
          team:      team,
          yes_price: yes_price,
          url:       poly_url,
          volume:    m['volume'].to_f,
        }
      end
    end
    results
  end
rescue => e
  puts "Polymarket error: #{e}"
  {}
end

# ── Kalshi: NBA Finals championship markets (KXNBA series) ───────────────────

def fetch_kalshi_finals
  return {} if KALSHI_API_KEY.empty?
  cached('kalshi_finals') do
    uri = URI('https://api.elections.kalshi.com/trade-api/v2/markets?limit=200&status=open&series_ticker=KXNBA')
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Token #{KALSHI_API_KEY}"
    req['Content-Type']  = 'application/json'

    res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    data = JSON.parse(res.body) rescue {}
    markets = data['markets'] || []

    results = {}
    markets.each do |m|
      team = normalize_team(m['yes_sub_title'] || m['title'] || '')
      next unless team

      yes_bid = m['yes_bid_dollars'].to_f
      yes_ask = m['yes_ask_dollars'].to_f
      last    = m['last_price_dollars'].to_f
      mid     = last > 0 ? last : (yes_bid + yes_ask) / 2.0

      results[team] = {
        team:    team,
        yes_bid: yes_bid,
        yes_ask: yes_ask,
        yes_mid: mid.round(4),
        no_ask:  (1.0 - yes_bid).round(4),  # price to buy NO = 1 - YES bid
        ticker:  m['ticker'],
        url:     "https://kalshi.com/markets/#{(m['event_ticker'] || m['ticker']).split('-').first.downcase}",
        volume:  m['volume_fp'].to_f,
      }
    end
    results
  end
rescue => e
  puts "Kalshi Finals error: #{e}"
  {}
end

# ── Kalshi: NBA game-winner markets (KXNBAGAME series) ───────────────────────

def fetch_kalshi_games
  return [] if KALSHI_API_KEY.empty?
  cached('kalshi_games') do
    uri = URI('https://api.elections.kalshi.com/trade-api/v2/markets?limit=200&status=open&series_ticker=KXNBAGAME')
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Token #{KALSHI_API_KEY}"
    req['Content-Type']  = 'application/json'

    res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
    data = JSON.parse(res.body) rescue {}
    data['markets'] || []
  end
rescue => e
  puts "Kalshi Games error: #{e}"
  []
end

# ── Build championship futures comparison ─────────────────────────────────────
# Core logic: same event on both platforms → find where buying YES on one
# and NO on the other costs less than $1 (= guaranteed profit)

def build_futures_comparison(kalshi_finals, poly_finals)
  all_teams = (kalshi_finals.keys & poly_finals.keys)  # only teams on BOTH

  results = []
  all_teams.each do |team|
    k = kalshi_finals[team]
    p = poly_finals[team]

    k_yes_ask = k[:yes_ask]   # price you pay to buy YES on Kalshi
    k_yes_bid = k[:yes_bid]   # price you receive if selling YES on Kalshi
    k_mid     = k[:yes_mid]
    k_no_ask  = k[:no_ask]    # price to buy NO on Kalshi = 1 - yes_bid

    p_yes = p[:yes_price]     # price on Polymarket (single midpoint price)
    p_no  = 1.0 - p_yes       # price to buy NO on Polymarket

    # ── Arb check 1: buy YES on Kalshi + buy NO on Polymarket ──────────────
    # If Kalshi prices team lower (cheaper YES), Polymarket has same team higher
    # (so Polymarket NO is cheaper). Collect $1 either way.
    cost1 = (k_yes_ask + p_no).round(4)
    arb1  = cost1 < 0.999 ? {
      buy_yes_on: 'kalshi',
      buy_no_on:  'polymarket',
      yes_price:  k_yes_ask,
      no_price:   p_no.round(4),
      cost:       cost1,
      profit_pct: ((1.0 - cost1) * 100).round(2),
    } : nil

    # ── Arb check 2: buy YES on Polymarket + buy NO on Kalshi ──────────────
    # If Polymarket prices team lower, Kalshi has them higher → Kalshi NO is cheaper
    cost2 = (p_yes + k_no_ask).round(4)
    arb2  = cost2 < 0.999 ? {
      buy_yes_on: 'polymarket',
      buy_no_on:  'kalshi',
      yes_price:  p_yes.round(4),
      no_price:   k_no_ask,
      cost:       cost2,
      profit_pct: ((1.0 - cost2) * 100).round(2),
    } : nil

    best_arb  = [arb1, arb2].compact.max_by { |a| a[:profit_pct] }
    price_gap = ((k_mid - p_yes) * 100).round(2)  # +ve = Kalshi higher

    results << {
      team:      team,
      # Kalshi data
      k_bid:     (k_yes_bid * 100).round(1),
      k_ask:     (k_yes_ask * 100).round(1),
      k_mid:     (k_mid     * 100).round(1),
      k_no_ask:  (k_no_ask  * 100).round(1),
      k_url:     k[:url],
      # Polymarket data
      p_yes:     (p_yes * 100).round(1),
      p_no:      (p_no  * 100).round(1),
      p_url:     p[:url],
      # Analysis
      price_gap:  price_gap,
      arb:        best_arb,
      has_arb:    !best_arb.nil?,
      espn:       nil,
    }
  end

  # Sort: arb opportunities first (by profit %), then by Kalshi price desc
  results.sort_by do |r|
    [r[:has_arb] ? 0 : 1,
     r[:has_arb] ? -r[:arb][:profit_pct] : 0,
     -(r[:k_mid] || 0)]
  end
end

# ── Build game matchups from Kalshi KXNBAGAME ─────────────────────────────────

def build_game_matchups(kalshi_markets)
  by_event = kalshi_markets.group_by { |m| m['event_ticker'] }

  matchups = []
  by_event.each do |event_ticker, legs|
    next if legs.length < 2

    parsed = legs.map do |m|
      team = normalize_team(m['yes_sub_title'] || '')
      next nil unless team

      last  = m['last_price_dollars'].to_f
      ask   = m['yes_ask_dollars'].to_f
      bid   = m['yes_bid_dollars'].to_f
      price = last > 0 ? last : (ask + bid) / 2.0
      next nil if price.zero?

      { team: team, pct: (price * 100).round(1),
        url: "https://kalshi.com/markets/#{(m['event_ticker'] || m['ticker']).split('-').first.downcase}",
        close_time: m['close_time'] }
    end.compact

    next if parsed.length < 2

    a, b = parsed[0], parsed[1]
    matchups << {
      id:         event_ticker,
      team_a:     a[:team], team_b:     b[:team],
      pct_a:      a[:pct],  pct_b:      b[:pct],
      url_a:      a[:url],  url_b:      b[:url],
      close_time: a[:close_time],
      espn_a:     nil,      espn_b:     nil,
    }
  end

  matchups.sort_by { |m| -((m[:pct_a] - m[:pct_b]).abs) }
end

# ── ESPN NBA team data ─────────────────────────────────────────────────────────

def fetch_espn_nba(team_name)
  cached("espn_#{team_name.downcase.gsub(' ', '_')}") do
    uri  = URI('https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams?limit=32')
    res  = Net::HTTP.get_response(uri)
    data = JSON.parse(res.body) rescue {}
    teams = data.dig('sports', 0, 'leagues', 0, 'teams') || []

    found = teams.find do |t|
      full = (t.dig('team', 'displayName') || '').downcase
      loc  = (t.dig('team', 'location')    || '').downcase
      normalize_team(full) == team_name || normalize_team(loc) == team_name
    end
    return nil unless found

    t     = found['team']
    r_uri = URI("https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/#{t['id']}")
    r_res = Net::HTTP.get_response(r_uri)
    r_data = JSON.parse(r_res.body) rescue {}

    {
      name:   t['displayName'],
      record: r_data.dig('team', 'record', 'items', 0, 'summary') || 'N/A',
      logo:   t.dig('logos', 0, 'href'),
    }
  end
rescue => e
  puts "ESPN error for #{team_name}: #{e}"
  nil
end

# ── Claude analysis ────────────────────────────────────────────────────────────

def call_claude(futures, games)
  return { error: 'No Anthropic key' } if ANTHROPIC_API_KEY.empty?

  arbs     = futures.select { |f| f[:has_arb] }
  top_gaps = futures.reject { |f| f[:has_arb] }
                    .sort_by { |f| -f[:price_gap].abs }
                    .first(4)

  arb_str = arbs.map do |f|
    a = f[:arb]
    yes_cents = (a[:yes_price] * 100).round(1)
    no_cents  = (a[:no_price]  * 100).round(1)
    "#{f[:team]}: Buy YES #{a[:buy_yes_on]} @#{yes_cents}¢ + NO #{a[:buy_no_on]} @#{no_cents}¢ " \
    "= #{(a[:cost] * 100).round(1)}¢ total → +#{a[:profit_pct]}% guaranteed"
  end.join("\n")

  gap_str = top_gaps.map do |f|
    dir = f[:price_gap] > 0 ? "Kalshi #{f[:price_gap].abs}pp higher" : "Polymarket #{f[:price_gap].abs}pp higher"
    "#{f[:team]}: Kalshi #{f[:k_mid]}% vs Polymarket #{f[:p_yes]}% (#{dir})"
  end.join("\n")

  games_str = games.first(4)
                   .map { |m| "#{m[:team_a]} #{m[:pct_a]}% vs #{m[:team_b]} #{m[:pct_b]}%" }
                   .join(', ')

  prompt = <<~PROMPT
    You are a sharp prediction market analyst. Both Kalshi and Polymarket offer the SAME event:
    "Will [team] win the 2026 NBA Finals?" — so direct price comparison and arbitrage is possible.

    HOW ARB WORKS: Buy YES on the cheaper platform + NO on the other.
    If total cost < $1.00, you collect exactly $1 regardless of outcome = risk-free profit.

    CONFIRMED ARBITRAGE OPPORTUNITIES:
    #{arb_str.empty? ? 'None currently (spreads are tight today)' : arb_str}

    LARGEST PRICE GAPS (one platform pricing team significantly different):
    #{gap_str}

    TONIGHT'S KALSHI GAME LINES:
    #{games_str}

    Provide sharp analysis (max 250 words):
    1. For each arb: is the return worth execution friction (withdrawal times, liquidity)?
    2. For the biggest gaps: which platform is likely correct and what's driving the difference?
    3. Any current NBA context (injuries, playoff picture) explaining the mispricing?
  PROMPT

  uri = URI('https://api.anthropic.com/v1/messages')
  req = Net::HTTP::Post.new(uri)
  req['x-api-key']         = ANTHROPIC_API_KEY
  req['anthropic-version'] = '2023-06-01'
  req['Content-Type']      = 'application/json'
  req.body = JSON.generate({
    model:      'claude-sonnet-4-20250514',
    max_tokens: 700,
    messages:   [{ role: 'user', content: prompt }],
  })

  res  = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  data = JSON.parse(res.body)
  { analysis: data.dig('content', 0, 'text') || 'No analysis returned' }
rescue => e
  { error: e.message }
end

# ── HTTP Server ────────────────────────────────────────────────────────────────

PORT = (ENV['PORT'] || 8080).to_i
server = WEBrick::HTTPServer.new(Port: PORT, DocumentRoot: File.dirname(__FILE__))

server.mount_proc('/api/markets') do |req, res|
  res['Content-Type']                = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'

  poly_finals    = fetch_polymarket_finals
  kalshi_finals  = fetch_kalshi_finals
  kalshi_games   = fetch_kalshi_games

  futures  = build_futures_comparison(kalshi_finals, poly_finals)
  games    = build_game_matchups(kalshi_games)

  # Attach ESPN data
  espn_cache = {}
  (futures + games).each do |item|
    teams = item[:team] ? [item[:team]] : [item[:team_a], item[:team_b]]
    teams.compact.each { |t| espn_cache[t] ||= fetch_espn_nba(t) }
  end

  futures.each { |f| f[:espn] = espn_cache[f[:team]] }
  games.each do |g|
    g[:espn_a] = espn_cache[g[:team_a]]
    g[:espn_b] = espn_cache[g[:team_b]]
  end

  arb_count   = futures.count(&:dig.curry[:has_arb]) rescue futures.count { |f| f[:has_arb] }
  best_return = futures.select { |f| f[:has_arb] }.map { |f| f[:arb][:profit_pct] }.max || 0

  res.body = JSON.generate({
    futures: futures,
    games:   games,
    meta: {
      kalshi_finals_count: kalshi_finals.length,
      poly_finals_count:   poly_finals.length,
      matched_teams:       futures.length,
      games_count:         games.length,
      arb_count:           arb_count,
      best_return:         best_return.round(2),
      cached_at:           Time.now.to_i,
    },
  })
end

server.mount_proc('/api/analyze') do |req, res|
  res['Content-Type']                = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'

  body    = JSON.parse(req.body || '{}') rescue {}
  futures = body['futures'] || []
  games   = body['games']   || []
  res.body = JSON.generate(call_claude(futures, games))
end

server.mount_proc('/api/health') do |req, res|
  res['Content-Type']                = 'application/json'
  res['Access-Control-Allow-Origin'] = '*'
  res.body = JSON.generate({ status: 'ok', time: Time.now.to_s })
end

trap('INT') { server.shutdown }
puts "HoopEdge running at http://localhost:#{PORT}"
server.start
