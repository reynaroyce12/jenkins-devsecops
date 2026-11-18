# CI/CD Pipeline with Jenkins, Docker & AWS

A Java application delivery pipeline that builds and tests code, scans dependencies, checks code quality, publishes a container image, and provides an automated deployment path to AWS EC2.

The project demonstrates the path from a source checkout to a verified release. A small Spring Boot application with MongoDB provides a real workload for integration tests, container packaging, and deployment checks.

**Jenkins · Maven · OWASP Dependency-Check · JaCoCo · SonarQube · Docker Buildx · Terraform · AWS Systems Manager**

## Architecture

![Sketch-style architecture showing Jenkins build, security and test stages, container publishing, and optional AWS deployment](docs/images/cicd-architecture.png)

[Edit the diagram in Excalidraw](docs/images/cicd-architecture.excalidraw) by downloading the file and opening it at [excalidraw.com](https://excalidraw.com). A [vector SVG](docs/images/cicd-architecture.svg) is also included. The diagram describes the implemented workflow. Live end-to-end verification is pending as listed below.

## What the pipeline delivers

- **Checks before release.** Unit tests, integration tests, dependency scanning, coverage report generation, and a SonarQube quality gate precede image publishing.
- **A deployable artifact.** Jenkins archives the packaged JAR, builds a Linux ARM64 image from that JAR, tags it with the build number, and records the registry digest.
- **Traceable deployment.** The AWS stage consumes that digest so the requested image can be matched to the published artifact.
- **Infrastructure in code.** Terraform defines the EC2 instance, security group, instance role, and profile. S3 stores Terraform state with locking.
- **Deployment verification and recovery.** The instance checks application and database health, queries a seeded record, and attempts to restore the previous application container if the new release fails validation.

## Pipeline stages

| Stage | Implementation | Output or release condition |
|---|---|---|
| Checkout and compile | Jenkins SCM checkout, Maven, Java 17 | Compiled application |
| Dependency checks in parallel | OWASP Dependency-Check and Maven Versions Plugin | OWASP fails the build at CVSS 9 or above. Versions Plugin lists available updates. |
| Publish scan results | Jenkins Dependency-Check and HTML Publisher plugins | XML and HTML dependency reports |
| Unit tests | JUnit, MockMvc, mocked MongoDB repository | Six tests and a dedicated JUnit report |
| Integration tests | Testcontainers with MongoDB 7 | Ten tests and a separate JUnit report |
| Coverage | JaCoCo with execution data from both suites | HTML and XML coverage reports |
| Static analysis and quality gate | SonarQube Maven scanner and Jenkins webhook integration | Gate must pass within ten minutes |
| Package and archive | Maven package, Jenkins artifact archiving | Executable JAR with fingerprint |
| Build and publish image | Docker Buildx, Docker Hub | ARM64 image and archived `published-image.txt` digest reference |
| Optional AWS deployment | Terraform, AWS CLI, Systems Manager Run Command | Deployment command must finish successfully after health and sample lookup checks |

Test failures stop subsequent stages. Jenkins also skips later stages when a stage makes the build unstable. Concurrent runs of the same pipeline job are disabled.

## Release and deployment design

The Dockerfile supports two build paths. Docker Compose builds from source for local use. Jenkins selects the `packaged` target to put the JAR produced by the pipeline into the runtime image.

`scripts/publish-image.sh` publishes `<docker-user>/textbook-library:<build-number>` and saves `<docker-user>/textbook-library@sha256:...` for deployment. The registry name follows the sample application packaged by this pipeline.

When `DEPLOY_TO_AWS` is enabled, Terraform provisions an Amazon Linux 2023 ARM64 instance. Systems Manager runs the deployment script on that instance. The script pulls the digest, starts MongoDB on an internal Docker network, imports the sample data, and starts the application on the instance's loopback address.

The release check calls `/actuator/health` and performs a database-backed lookup through `/textbook`. After a failed release check, the script attempts to restart the previous application container and returns a failure to Jenkins. Session Manager port forwarding provides browser access. The instance security group has no inbound rules.

MongoDB data persists in a Docker volume across application container updates on the same instance. Replacing or destroying the instance removes that local database. This configuration uses one EC2 instance and can have downtime during application replacement.

## Verification status

| Check | Result |
|---|---|
| Local Docker Compose demo and database seed | Passed, including sample record lookup and repeated import with nine total records |
| Unit and MongoDB integration suites | All 16 tests passed locally on Java 21. Jenkins is configured to use Java 17. |
| Combined coverage and JAR packaging | Verified locally |
| Jenkinsfile syntax | Validated with a temporary Jenkins controller |
| Terraform configuration | Validation passed. A read-only AWS plan proposed five new resources. |
| Full Jenkins run, current security scan, SonarQube gate, and registry push | Live verification pending |
| AWS deployment, second-release digest check, and recovery behavior | Live verification pending. The tested AWS identity lacks Systems Manager read access. |

## Run the packaged workload locally

With Docker and Docker Compose running, execute this from the repository root.

```bash
docker compose up --build -d
docker compose logs -f app
```

The first build downloads images and Maven dependencies. Once Spring Boot reports startup, open [localhost:3001](http://localhost:3001). Compose starts MongoDB and imports nine sample records before launching the app.

```bash
curl -fsS http://localhost:3001/textbook \
  -H 'Content-Type: application/json' \
  -d '{"id":0}'
```

The response should include `Introduction to Software Engineering` and `Ian Sommerville`. Repeating the import updates the same records. Run `docker compose down` to stop the workload. Add `--volumes` to delete the local demo database.

## Sample application

The supplied Spring Boot UI and MongoDB dataset act as the workload packaged by the pipeline. They provide an HTTP endpoint, a database dependency, and a visible result for deployment checks.

![Sample application packaged and tested by the CI/CD pipeline](docs/images/sample-app.png)

*Local sample workload. The deployment workflow and its verification status are described above.*

## Run the tests

Use Java 17, Maven 3.9 or later, and a running Docker engine. The integration suite creates its own MongoDB container.

```bash
mvn clean test
mvn -Pintegration-tests test
mvn jacoco:report
```

Open `target/site/jacoco/index.html` for coverage. Unit reports are in `target/surefire-reports/`; integration reports are in `target/integration-test-reports/`.

## Configure Jenkins and AWS

Follow the [setup and operations guide](docs/operations.md) for Jenkins tools, plugins, SonarQube webhooks, AWS access, S3 state, port forwarding, and teardown.

| Jenkins parameter | Default | Purpose |
|---|---|---|
| `DEPLOY_TO_AWS` | `false` | Enable deployment after image publishing |
| `AWS_REGION` | `us-east-1` | EC2 and Terraform state bucket region |
| `AWS_SUBNET_ID` | Empty | Public subnet with outbound internet access |
| `TF_STATE_BUCKET` | Empty | Existing S3 state bucket |

Store `nvd-api-key`, `sonar-token`, and `dockerhub-creds` in Jenkins credentials. Configure AWS access on the agent using its role or temporary credentials. `.env.example` documents the optional local MongoDB connection setting; `.env` is ignored by Git. Compose reads that file for variable substitution. Running Spring Boot directly requires setting `MONGO_URI` in its process environment.

The AWS instance pulls from a public Docker Hub repository. The state bucket is provided separately. EC2, disk, and public IPv4 usage can incur charges while provisioned. The operations guide includes teardown commands.

## Repository map

```text
Jenkinsfile                    Pipeline stages, test gates, and optional deployment
pom.xml                        Build, test profiles, and JaCoCo configuration
Dockerfile                     Source and packaged-JAR container build paths
compose.yaml                   Local workload, MongoDB, and seed import
scripts/publish-image.sh       Registry push and digest capture
scripts/deploy-aws.sh          Terraform orchestration and Systems Manager command
terraform/main.tf             AWS resources and remote state configuration
terraform/bootstrap.sh.tftpl   Instance setup and deployment script installation
terraform/deploy-instance.sh   Container update, checks, and recovery attempt
src/                          Sample workload and tests
data/                         Sample MongoDB records
docs/                         Operations guide, diagram source, and images
```

## Project background

This project extends an SE441 course exercise with Jenkins pipeline configuration, container packaging, and Terraform deployment work. The Spring Boot application and sample dataset originated in the course starter repositories. This repository presents the delivery workflow and the workload used to exercise it.
