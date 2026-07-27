pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3'
    }

    environment {
        IMAGE_NAME     = 'petclinic'
        AWS_REGION     = 'us-east-1'
        AWS_ACCOUNT_ID = '316777658873'
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        EKS_CLUSTER =    'myapp-staging-eks'
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
                        mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
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

        stage('Trivy Scan') {
            steps {
                sh '''
                    mkdir -p $HOME/trivytmp
                    mkdir -p $HOME/.cache/trivy

                    TMPDIR=$HOME/trivytmp \
                    trivy image \
                        --cache-dir $HOME/.cache/trivy \
                        --severity HIGH,CRITICAL \
                        $IMAGE_NAME:latest
                '''
            }
        }

        stage('Login to Amazon ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION | \
                    docker login \
                        --username AWS \
                        --password-stdin $ECR_REGISTRY
                '''
            }
        }

        stage('Tag Docker Image') {
            steps {
                sh '''
                    docker tag \
                        $IMAGE_NAME:latest \
                        $ECR_REGISTRY/$IMAGE_NAME:latest
                    
                    docker tag \
                        $IMAGE_NAME:${BUILD_NUMBER} \
                        $ECR_REGISTRY/$IMAGE_NAME:${BUILD_NUMBER}
                '''
            }
        }

        stage('Verify ECR Image Tag') {
            steps {
                sh '''
                    echo "Docker Images After ECR Tagging:"
                    docker images | grep $IMAGE_NAME
                '''
            }
        }

        stage('Push Docker Image to ECR') {
            steps {
                sh '''
                    docker push $ECR_REGISTRY/$IMAGE_NAME:latest
                '''
            }
        }

        stage('Verify Image in ECR') {
            steps {
                sh '''
                    aws ecr describe-images \
                        --repository-name $IMAGE_NAME \
                        --region $AWS_REGION
                        --query 'imageDetails[*].imageTags'
                '''
            }
        }

        stage('Configure kubectl') {
            steps {
                sh '''
                    aws eks update-kubeconfig \
                        --region $AWS_REGION \
                        --name $EKS_CLUSTER

                    kubectl config current-context

                    kubectl get nodes
                '''
            }
        }

        stage('Helm Lint') {
        steps {
            sh '''
                helm lint helm/petclinic
            '''
        }
    }

    stage('Helm Template Validation') {
        steps {
            sh '''
                helm template petclinic helm/petclinic > rendered.yaml
                echo "Helm template validation successful."
                rm -f rendered.yaml
            '''
        }
    }

    stage('Deploy to EKS') {
        steps {
            sh '''
                helm upgrade --install petclinic \
                helm/petclinic \
                -n petclinic \
                --create-namespace \
                --wait \
                --timeout 5m
            '''
        }
    }

    stage('Verify Deployment') {
        steps {
            sh '''
                echo "Waiting for deployment rollout..."

                kubectl rollout status deployment/petclinic \
                    -n petclinic \
                    --timeout=300s

                echo "Pods"
                kubectl get pods -n petclinic

                echo "Services"
                kubectl get svc -n petclinic

                echo "Ingress"
                kubectl get ingress -n petclinic

                echo "PVC"
                kubectl get pvc -n petclinic

                echo "HPA"
                kubectl get hpa -n petclinic
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
            sh '''
                echo "Docker Disk Usage - Before Cleanup"
                docker system df

                # Remove the build-specific image tag
                docker image rm -f $IMAGE_NAME:${BUILD_NUMBER} || true

                # Remove dangling images
                docker image prune -f

                # Remove unused Docker build cache
                docker builder prune -f

                echo "Docker Disk Usage - After Cleanup"
                docker system df
            '''
            cleanWs()
        }
    }
}