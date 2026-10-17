# Mangao WRS server (Java + Spring Boot) for the online host (Render). Built from the server-java folder.
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/mangao-wrs-server.jar app.jar
ENV TZ=Asia/Manila
EXPOSE 3100
# Small memory settings so it fits the free plan (512 MB).
CMD ["java", "-XX:MaxRAMPercentage=65", "-XX:+UseSerialGC", "-Xss512k", "-XX:TieredStopAtLevel=1", "-Dfile.encoding=UTF-8", "-jar", "app.jar"]
