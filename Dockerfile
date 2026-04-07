FROM ruby:3.2.2-slim

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

EXPOSE 8080

CMD ["ruby", "server.rb"]
