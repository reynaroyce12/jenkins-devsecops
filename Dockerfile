FROM maven:3.10.0-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:17-jre AS runtime
WORKDIR /app
EXPOSE 3001
ENTRYPOINT ["java", "-jar", "app.jar"]

FROM runtime AS packaged
COPY target/*.jar app.jar

FROM runtime AS app
COPY --from=build /workspace/target/*.jar app.jar
