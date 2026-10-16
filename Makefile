build:
	docker-compose build

console:
	docker-compose run --rm web bundle exec rails console

up:
	rm -rf tmp/pids/*
	touch tmp/caching-dev.txt
	docker-compose up

up-mail:
	rm -rf tmp/pids/*
	touch tmp/caching-dev.txt
	docker-compose --profile dev up

stop:
	docker-compose stop

down:
	docker-compose down

install:
	docker-compose run --rm web bundle install
	# docker-compose run --rm web yarn install

lint:
	docker-compose run --rm web bundle exec rubocop
	# docker-compose run --rm web yarn lint
	# docker-compose run --rm web yarn stylelint
	docker-compose run --rm web bundle exec slim-lint app/views/

rspec:
	docker-compose run --rm web bundle exec rspec

test-rails:
	docker-compose run --rm web bundle exec rails test

fix:
	docker-compose run --rm web bundle exec rubocop -a
	# docker-compose run --rm web yarn lint --fix
	# docker-compose run --rm web yarn stylelint --fix

# db:drop は「他セッションが DB に繋いでいると」失敗するので、先にバックエンドを切ってから drop する。
db-reset:
	docker compose up -d db
	@until docker compose exec -T db pg_isready -U postgres >/dev/null 2>&1; do sleep 0.5; done
	@db_name=$$(docker compose exec -T db printenv POSTGRES_DB); \
		docker compose exec -T db psql -U postgres -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$$db_name' AND pid <> pg_backend_pid();"
	docker compose run --rm web bundle exec rails db:drop db:create

db-load-schema:
	docker compose run --rm web bundle exec rails db:schema:load

db-seed:
	docker compose run --rm web bundle exec rails db:seed

setup:
	make db-reset && make db-load-schema && make db-seed

bash:
	docker-compose exec web /bin/bash

test: lint rspec
