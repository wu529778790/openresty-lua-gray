pipeline{

    agent {
        label 'linux'
    }
    environment{
        repo = 'https://gitlab.shenzjd.com/shenzjd-frontend/front-saas-gray.git'
        _date = sh(script: "echo `date '+%m%d%H%M'`", returnStdout: true).trim()
    }

    stages{
        stage('Pull code'){
            steps{
                echo "Pull code from git:${repo}."
                deleteDir()
                checkout([$class: 'GitSCM', branches: [[name: "*/${env.BRANCH}"]], doGenerateSubmoduleConfigurations: false, extensions: [], submoduleCfg: [], userRemoteConfigs: [[credentialsId: 'jenkins.ci', url: "${repo}"]]])
            }
        }
               
        stage('Build &amp; push Image'){
            environment{
            image_name="gray-openrestry"
            gitcommitid = sh(script: "git log -1 --pretty=format:'%h'", returnStdout: true).trim()
            gitcommitmsg = sh(script: "git log -1 --pretty=format:'%B'", returnStdout: true)
            gitcommituser = sh(script: "git log -1 --pretty=format:'%an'", returnStdout: true)
            publish_version="V${BUILD_NUMBER}.${gitcommitid}.${_date}"
            }
            steps{
                sh '''#!/bin/bash
                docker build . -t hub.shenzjd.com/shenzjdrepo/${image_name}:${publish_version}
                docker push hub.shenzjd.com/shenzjdrepo/${image_name}:${publish_version}
                '''
                }
        }

    }
    
}
