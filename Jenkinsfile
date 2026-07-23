pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build, Test & JaCoCo') {
            steps {
                sh 'mvn clean verify'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        mvn sonar:sonar \
                        -Dsonar.projectKey=Petclinic \
                        -Dsonar.projectName=Petclinic \
                        -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Deploy to Nexus') {
            steps {
                configFileProvider([
                    configFile(
                        fileId: 'd0a2cf88-2da5-4356-8cbf-4be592fb6d75',
                        variable: 'MAVEN_SETTINGS'
                    )
                ]) {
                    sh '''
                        mvn deploy \
                          -s $MAVEN_SETTINGS \
                          -DskipTests \
                          -Dnexus.url=$NEXUS_URL
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'target/site/jacoco/**', fingerprint: true
        }

        success {
            echo 'Pipeline completed successfully!'
        }

        failure {
            echo 'Pipeline failed!'
        }
    }
}