# syntax=docker/dockerfile:1

#############################################
# Stage 1: Build
# Uses the full JDK + Maven to compile and package the app.
# This entire stage is discarded from the final image - keeps
# the runtime image free of build tools, source code, and the
# local Maven cache.
#############################################
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app

# Copy only the pom.xml first so Docker can cache the dependency
# download layer separately from source code changes. As long as
# pom.xml doesn't change, this layer is reused on every rebuild -
# saves significant time on repeated CI builds.
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Now copy actual source and build. Any source change invalidates
# only this layer onward, not the dependency download above.
COPY src ./src
RUN mvn -B clean package -DskipTests

# Extract the Spring Boot layered jar into separate layers
# (dependencies, spring-boot-loader, snapshot-dependencies,
# application classes). This lets Docker cache dependency layers
# independently from your actual application code in Stage 2 -
# app-only rebuilds become much smaller/faster to push and pull.
RUN java -Djarmode=layertools -jar target/*.jar extract --destination extracted

#############################################
# Stage 2: Runtime
# Minimal JRE (not full JDK) - smaller attack surface, smaller image.
#############################################
FROM eclipse-temurin:21-jre-jammy AS runtime

# Run as a dedicated non-root user - never run application
# containers as root in production.
RUN groupadd -r spring && useradd -r -g spring spring

WORKDIR /app

# Copy extracted layers in order of change-frequency (least to
# most likely to change) - maximizes Docker layer cache hits.
COPY --from=build --chown=spring:spring /app/extracted/dependencies/ ./
COPY --from=build --chown=spring:spring /app/extracted/spring-boot-loader/ ./
COPY --from=build --chown=spring:spring /app/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=spring:spring /app/extracted/application/ ./

USER spring:spring

EXPOSE 8080

# Health checking is handled by Kubernetes liveness/readiness
# probes at the pod level (hitting /actuator/health from outside
# the container) rather than a Docker-level HEALTHCHECK here -
# avoids needing curl/wget baked into the runtime image at all.

# JVM container-awareness flags: respect cgroup memory limits set
# by Docker/Kubernetes instead of reading host machine's total RAM.
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]