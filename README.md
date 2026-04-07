# CollegeEdge 🏀

**Prediction market divergence detector for college sports**  
Duke University Financial Economics 2026 · Built with Claude

---

## What it does

Compares live betting odds on college sports games across **Polymarket** (decentralised, USDC) and **Kalshi** (CFTC-regulated, USD). When both platforms price the same game differently, one side is mispriced — CollegeEdge finds those gaps and uses Claude AI to explain them.

---

## Setup

### Requirements
- Ruby 3.0+
- `dotenv` gem (auto-installed by start script)

### 1. Clone / download this folder

```bash
cd ~/collegesports-arb
```

### 2. Add your API keys

```bash
cp .env.example .env
nano .env   # or open in any text editor
```

Paste in:
```
KALSHI_API_KEY=your_kalshi_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
```

### 3. Start the server

```bash
chmod +x start.sh
./start.sh
```

### 4. Open the site

```
http://localhost:8080/index.html
```

---

## Architecture

```
collegesports-arb/
├── server.rb       ← Ruby WEBrick backend
│                     • /api/markets  — fetches + matches Polymarket & Kalshi
│                     • /api/analyze  — calls Claude for AI analysis
│                     • /api/health   — health check
├── index.html      ← Frontend (HTML/CSS/JS, no framework)
├── .env            ← Your API keys (never commit this)
├── .env.example    ← Template
└── start.sh        ← One-command startup
```

### Key concepts

| Concept | Details |
|---------|---------|
| Market matching | Extracts team names from titles, finds pairs where both appear on both platforms |
| Gap threshold | Only shows divergences ≥ 3 percentage points |
| EV calculator | `edge = stake × gap_pct / 100` — simplified positive expected value |
| ESPN context | Pulls team record + ranking from ESPN's free public API |
| Caching | 60s TTL on all API responses to avoid rate limits |

---

## Notes

- Kalshi requires a US-resident account for API access
- Polymarket uses their public Gamma API (no auth needed)
- ESPN API is free and public
- All keys stay in `.env` — never hardcode them
