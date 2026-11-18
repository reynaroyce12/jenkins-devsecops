pipeline {
    agent any

    options {
        skipDefaultCheckout()
        skipStagesAfterUnstable()
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(name: 'DEPLOY_TO_AWS', defaultValue: false, description: 'Deploy the published image to the AWS demo.')
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', trim: true, description: 'AWS region for the EC2 demo and Terraform state bucket.')
        string(name: 'AWS_SUBNET_ID', defaultValue: '', trim: true, description: 'Public subnet for the EC2 demo.')
        string(name: 'TF_STATE_BUCKET', defaultValue: '', trim: true, description: 'Existing S3 bucket for Terraform state.')
    }

    tools {
        maven 'M3'
        jdk 'OpenJDK 17'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo 'Checkout succeeded!'
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean compile'
                echo 'Build succeeded!'
            }
        }

        stage('Dependency Scanning Parallel') {
            parallel {
                stage('OWASP Dependency-Check') {
                    steps {
                        withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
                            sh '''
                                mvn -B org.owasp:dependency-check-maven:check \
                                -DfailBuildOnCVSS=9 \
                                -DnvdApiKey=$NVD_API_KEY \
                                -DdataDirectory="$WORKSPACE/.dc-data" \
                                -Dformats=HTML,XML
                            '''
                        }
                        stash includes: 'target/dependency-check-report.*', name: 'dc-reports'
                    }
                }
                stage('Maven Dependency Audit') {
                    steps {
                        sh 'mvn versions:display-dependency-updates'
                        echo 'Maven dependency audit complete!'
                    }
                }
            }
        }

        stage('Publish Dependency-Check Results') {
            steps {
                unstash 'dc-reports'
                dependencyCheckPublisher pattern: 'target/dependency-check-report.xml'
                publishHTML(target: [
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'target',
                    reportFiles: 'dependency-check-report.html',
                    reportName: 'Dependency Check HTML Report'
                ])
            }
        }

        stage('Unit Tests') {
            steps {
                sh 'mvn -B test'
            }
            post {
                always {
                    junit 'target/surefire-reports/TEST-*.xml'
                }
            }
        }

        stage('Integration Tests') {
            steps {
                sh 'mvn -B -Pintegration-tests test'
            }
            post {
                always {
                    junit 'target/integration-test-reports/TEST-*.xml'
                }
            }
        }

        stage('Code Coverage') {
            steps {
                sh 'mvn -B jacoco:report && test -s target/site/jacoco/jacoco.xml'
                publishHTML(target: [
                    allowMissing: false,
                    alwaysLinkToLastBuild: true,
                    keepAll: true,
                    reportDir: 'target/site/jacoco',
                    reportFiles: 'index.html',
                    reportName: 'Code Coverage HTML Report'
                ])
            }
        }

        stage('SAST - SonarQube') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:5.5.0.6356:sonar \
                        -Dsonar.projectKey=textbook-library \
                        -Dsonar.projectName="SE Textbook Library" \
                        -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                    '''
                }
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }

        stage('Docker Build & Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh 'bash scripts/publish-image.sh'
                }
                archiveArtifacts artifacts: 'target/published-image.txt', fingerprint: true
            }
        }

        stage('Deploy & Verify on AWS') {
            when {
                expression { params.DEPLOY_TO_AWS }
            }
            steps {
                timeout(time: 25, unit: 'MINUTES') {
                    sh 'bash scripts/deploy-aws.sh'
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}
