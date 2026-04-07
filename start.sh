#!/bin/bash
set -e

echo "🏀 CollegeEdge — Starting up..."

# Check Ruby
if ! command -v ruby &> /dev/null; then
  echo "❌ Ruby not found. Install it: brew install ruby"
  exit 1
fi

# Check .env exists
if [ ! -f .env ]; then
  echo "⚠️  No .env found. Copying from .env.example..."
  cp .env.example .env
  echo "📝 Edit .env and add your API keys, then run ./start.sh again."
  exit 1
fi

# Install dotenv gem if needed
if ! gem list dotenv -i &> /dev/null; then
  echo "📦 Installing dotenv gem..."
  gem install dotenv
fi

echo "✅ Starting server on http://localhost:8080"
echo "   Open http://localhost:8080/index.html in Chrome"
echo "   Press Ctrl+C to stop"
echo ""

ruby server.rb
