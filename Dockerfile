ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3
ARG ALPINE_VERSION=3.21.3

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS build

RUN apk add --no-cache git build-base

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config/config.exs config/
RUN mix deps.get --only $MIX_ENV

COPY config/runtime.exs config/
COPY lib lib

RUN mix deps.compile && mix compile
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache libstdc++ ncurses-libs

ENV LANG=en_US.UTF-8
ENV TERM=xterm-256color
ENV PROMETHEUS=http://host.docker.internal:9090

RUN mkdir -p /data /root/.config/graf_ex_term

WORKDIR /app
COPY --from=build /app/_build/prod/rel/graf_ex_term ./

VOLUME ["/data", "/root/.config/graf_ex_term"]

CMD ["/app/bin/graf_ex_term", "eval", "GrafExTerm.run()"]
