# CI/CD Pipeline with Jenkins, Docker & AWS

This project is a CI/CD pipeline built with Jenkins. It takes a Java app from GitHub, builds it, runs security checks and tests, and publishes the app to Docker Hub.

It uses a small Spring Boot app with MongoDB as the sample app. The repo also includes Terraform files and scripts for optional AWS deployment.

## Architecture

![CI/CD pipeline from code checkout to Docker publishing and optional AWS deployment](docs/images/cicd-architecture.png)


## What it does

1. Jenkins pulls the code from GitHub and builds it with Maven and Java 17.
2. OWASP Dependency-Check scans the libraries for known vulnerabilities. Maven also checks for available updates.
3. The pipeline runs 6 unit tests and 10 integration tests. The integration tests use a real MongoDB container.
4. JaCoCo creates a coverage report, and SonarQube checks the code quality.
5. Jenkins saves the JAR, builds an ARM64 Docker image, and pushes it to Docker Hub.

The pipeline stops if tests or the SonarQube quality gate fail. The dependency scan also stops the build for vulnerabilities with a CVSS score of 9 or higher.


## Run locally

Start Docker Desktop, then run these commands from the project folder.

```bash
docker compose up --build -d
docker compose logs -f app
```

Once the app starts, open [localhost:3001](http://localhost:3001) and search for ID `0`. Compose starts MongoDB and loads nine sample records automatically.

To stop the app, run `docker compose down`.

## Run the tests

Use Java 17, Maven 3.9 or later, and a running Docker engine.

```bash
mvn clean test
mvn -Pintegration-tests test
mvn jacoco:report
```

Open `target/site/jacoco/index.html` to view coverage.

## Jenkins and AWS setup

Follow the [setup guide](docs/operations.md) to configure Jenkins, SonarQube, and Docker Hub.

The project also includes an optional AWS stage. Terraform creates the EC2 resources, and Systems Manager runs the published image and checks the app. You can enable this stage with `DEPLOY_TO_AWS` in Jenkins. It is off by default.

The setup guide includes AWS permissions, build parameters, and cleanup commands. Store tokens in Jenkins credentials. Use `.env.example` as a template for local settings.

