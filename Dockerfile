# Dockerfile
# Source: https://github.com/dotnet/dotnet-docker
FROM mcr.microsoft.com/dotnet/runtime-deps:6.0-jammy as build

ARG TARGETOS
ARG TARGETARCH
ARG RUNNER_VERSION=2.311.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.5.0
ARG DOCKER_VERSION=24.0.6
ARG BUILDX_VERSION=0.11.2

RUN apt update -y && apt install curl unzip -y

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-docker-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./docker-hooks \
    && rm runner-container-hooks.zip

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

FROM golang:1.21-alpine3.18 as builder
# Do not remove `git` here, it is required for getting runner version when executing `make build`
RUN apk add --no-cache make git

COPY . /opt/src/act_runner
WORKDIR /opt/src/act_runner

RUN make clean && make build

FROM catthehacker/ubuntu:act-latest-20231008

ENV GITEA_RUNNER_LABELS=ubuntu-latest
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ACTIONS_RUNNER_CONTAINER_HOOKS=/home/runner/docker-hooks/index.js

RUN adduser --disabled-password --gecos "" --uid 1000 runner \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers \
    && echo "root ALL=(ALL) ALL" >> /etc/sudoers

WORKDIR /home/runner

VOLUME /home/runner/externals
VOLUME /home/runner/_work

COPY --chown=runner:docker --from=build /actions-runner .

RUN mkdir -p /runner && chown runner:docker -R /runner && ln -s /data/.actions_runner .runner

USER runner

WORKDIR /runner
RUN chown runner:docker /runner && mkdir -p /home/runner/_work && chown -R runner:docker /home/runner/_work

COPY --from=builder /opt/src/act_runner/gitea-actions-runner /runner/gitea-actions-runner

COPY actions-runner-worker.py /runner
COPY start.sh /runner

CMD ["bash", "/runner/start.sh"]
