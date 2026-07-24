pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    environment {
        IMAGE_NAME = 'petclinic'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
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
                          -Dsonar.projectName=Petclinic
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

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                        -t $IMAGE_NAME:${BUILD_NUMBER} \
                        -t $IMAGE_NAME:latest .
                '''
            }
        }

        stage('Verify Docker Image') {
            steps {
                sh '''
                    echo "Available Docker Images:"
                    docker images | grep $IMAGE_NAME
                '''
            }
        }
    }

    post {
        success {
            echo '✅ CI Pipeline completed successfully!'
        }

        failure {
            echo '❌ Pipeline failed!'
        }

        always {
            cleanWs()
        }
    }
}