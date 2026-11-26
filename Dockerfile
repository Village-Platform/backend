# syntax=docker/dockerfile:1
# Production image, deployed to the k3s cluster by bin/deploy (see deploy/k8s/README.md).
# Build locally with:
#   docker build -t village-platform .
#   docker run --rm -p 3000:3000 --env-file .env.production village-platform

ARG RUBY_VERSION=4.0.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libpq5 libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" \
    PORT="3000"

# ---- Build stage: gems + precompiled assets and bootsnap cache ----
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---- Final stage: small runtime image, non-root user ----
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=rails:rails /rails /rails

RUN mkdir -p tmp/pids tmp/cache log storage && chown -R rails:rails tmp log storage
USER 1000:1000

# The bootsnap cache was built above; do not try to write it at runtime.
ENV BOOTSNAP_READONLY="1" \
    HOME="/home/rails"

# The commit this image was built from, reported as service.version on traces and metrics.
# Last, so a new revision does not invalidate the layers above. bin/deploy passes the short SHA; otherwise "unknown".
ARG APP_REVISION=unknown
ENV APP_REVISION=$APP_REVISION

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
