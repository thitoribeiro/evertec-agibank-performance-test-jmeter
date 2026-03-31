FROM eclipse-temurin:17-jre-jammy

ARG JMETER_VERSION=5.6.3
ENV JMETER_HOME=/opt/apache-jmeter-${JMETER_VERSION}
ENV PATH="${JMETER_HOME}/bin:${PATH}"
ENV IN_DOCKER=true

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl python3 && \
    rm -rf /var/lib/apt/lists/* && \
    curl -Lo /tmp/jmeter.tgz \
      "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz" && \
    tar -xzf /tmp/jmeter.tgz -C /opt && \
    rm /tmp/jmeter.tgz

WORKDIR /test

COPY scripts/ scripts/
COPY config/  config/

RUN mkdir -p results/load reports/load results/spike reports/spike

VOLUME ["/test/results", "/test/reports"]

# Default command if none provided
CMD ["bash", "scripts/run-load-test.sh"]
