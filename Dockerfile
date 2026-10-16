# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.1
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /opt/app

ENV LANG=C.UTF-8 \
    TZ=Asia/Tokyo

RUN echo 'Asia/Tokyo' > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

RUN gem install bundler -v 2.6.2

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    postgresql-client \
    libjemalloc2 \
    libvips \
    less \
    sudo \
    git \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Development stage
FROM base AS development

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    libyaml-dev \
    pkg-config \
    nodejs \
    npm \
    vim \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="development" \
    BUNDLE_PATH="/usr/local/bundle"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN gem install foreman

# === Create symlinks for Rails commands (better than aliases) ===
RUN ln -sf /opt/app/bin/rails /usr/local/bin/rails && \
    ln -sf /opt/app/bin/rake /usr/local/bin/rake && \
    echo '#!/bin/bash\nexec bundle exec rspec "$@"' > /usr/local/bin/rspec && \
    chmod +x /usr/local/bin/rspec && \
    echo '#!/bin/bash\nexec bundle exec rubocop "$@"' > /usr/local/bin/rubocop && \
    chmod +x /usr/local/bin/rubocop && \
    echo '#!/bin/bash\nexec bundle exec brakeman "$@"' > /usr/local/bin/brakeman && \
    chmod +x /usr/local/bin/brakeman

ENTRYPOINT ["/opt/app/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bin/dev"]

# Production build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    git \
    libyaml-dev \
    pkg-config \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

# Precompile assets for production
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final production stage
FROM base AS production

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /opt/app /opt/app

# Run as non-root user for security
RUN groupadd --system --gid 1000 app && \
    useradd app --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R app:app db log storage tmp
USER 1000:1000

ENTRYPOINT ["/opt/app/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
