# Pipeline setup and AWS operations

## Jenkins setup

- Create a Pipeline from SCM that loads the root `Jenkinsfile`.
- Under **Manage Jenkins → Tools**, configure a Java 17 installation named `OpenJDK 17` and a Maven 3.9+ installation named `M3`.
- Install the Pipeline, Git, Credentials Binding, JUnit, HTML Publisher, OWASP Dependency-Check, and SonarQube Scanner for Jenkins plugins.
- Give the build agent Bash, Docker with Buildx, and `jq`. The AWS deployment also uses Terraform 1.10+ and AWS CLI v2.
- Under **Manage Jenkins → System → SonarQube servers**, add a server named `SonarQube` with a URL reachable from the agent. Select the `sonar-token` secret text credential. Set up the SonarQube project with key `textbook-library` and a webhook to `<jenkins-url>/sonarqube-webhook/` so Jenkins receives the quality gate result.

| Jenkins credential ID | Type | Purpose |
|-----------------------|------|---------|
| `nvd-api-key` | Secret text | OWASP Dependency-Check vulnerability data |
| `sonar-token` | Secret text | SonarQube analysis |
| `dockerhub-creds` | Username and password | Publish the container image to Docker Hub |

## Deploy the AWS demo

Jenkins publishes a Linux ARM64 image to Docker Hub and archives its full digest reference as `published-image.txt`. The optional AWS stage provisions an ARM64 EC2 instance with Terraform and uses AWS Systems Manager Run Command to deploy that exact image. MongoDB runs on a private container network with a local volume. The deployment checks Actuator health, queries textbook ID `0`, and reports the running image reference. If the new application fails validation, the instance tries to restart the previous container and Jenkins reports a failure.

1. Create a public Docker Hub repository named `textbook-library` under the account named in `dockerhub-creds`. EC2 pulls the image anonymously.
2. Provide an AWS public subnet with an internet route for outbound package downloads, Docker Hub, and Systems Manager. The instance security group has no inbound rules.
3. Provide an existing private, versioned S3 bucket in the selected region. Terraform stores the state at `textbook-library/demo.tfstate` and uses an S3 lock file. Give the deployment identity access to that state and lock.
4. Configure the Jenkins agent's AWS identity with temporary credentials or an IAM role. Terraform needs permissions to look up the Amazon Linux AMI and manage the EC2 instance, security group, and instance role/profile, including permission to pass the role. The pipeline also needs to find the managed instance and send and inspect Systems Manager commands. Keep AWS credentials out of the repository.
5. In Jenkins, enable `DEPLOY_TO_AWS` and set `AWS_REGION`, `AWS_SUBNET_ID`, and `TF_STATE_BUCKET`. On success, the deployment log shows the instance ID, textbook lookup result, and deployed image digest. Run a second release and compare its digest with the archived reference from that build.

### View the deployed app

Use AWS CLI v2 with the Session Manager plugin and an identity allowed to start a session. Substitute the instance ID from the Jenkins log.

```bash
aws ssm start-session --region us-east-1 --target i-REPLACE_ME \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3001"],"localPortNumber":["3002"]}'
```

With the session running, open [http://127.0.0.1:3002](http://127.0.0.1:3002) and search for ID `0`.

### Remove the demo

From the repository root, with the same AWS identity and values used for deployment, initialize Terraform and review the destroy plan. Run destroy when you are ready to delete the demo instance and its local database.

```bash
export AWS_REGION=us-east-1
export AWS_SUBNET_ID=subnet-REPLACE_ME
export TF_STATE_BUCKET=REPLACE_ME
export TF_VAR_region="$AWS_REGION" TF_VAR_subnet_id="$AWS_SUBNET_ID"

terraform -chdir=terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="key=textbook-library/demo.tfstate"
terraform -chdir=terraform plan -destroy
terraform -chdir=terraform destroy
```

EC2, its disk, and the public IPv4 address can incur charges while provisioned. MongoDB data survives container updates on the same instance. Instance replacement or teardown removes the local demo database. Manage the existing state bucket and published images separately.


## References

- [Jenkins Pipeline syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [SonarQube quality gates in Jenkins](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/ci-integration/jenkins-integration/pipeline-pause)
- [Terraform S3 state backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [AWS Systems Manager Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html)
