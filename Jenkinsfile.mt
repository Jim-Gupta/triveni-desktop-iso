pipeline {
    agent {
        dockerfile {
            // This tells Jenkins exactly which file to use
            filename 'Dockerfile'
            // Ensures permissions are correct for the 'jenkins' user
            args '-u 110:110 -e HOME=${WORKSPACE} -v /var/lib/jenkins/userContent:/mnt/userContent'
        }
    }
    parameters {
        string(name: 'BASE_ISO_FILE', defaultValue: params.BASE_ISO_FILE ?: '/mnt/userContent/iso-images/ubuntu-24.04.3-desktop-amd64.iso', description: 'Path to Base ISO')
        string(name: 'DRIVERS_DIR', defaultValue: params.DRIVERS_DIR ?: '/mnt/userContent/triveni-drivers', description: 'Path to Drivers Directory')
        string(name: 'SSMT_DEB_DIR', defaultValue: params.SSMT_DEB_DIR ?: '/mnt/userContent/StreamScopeMT_24.04_trunk', description: 'Path to MT Debian')
    }
    environment {
        FAILED_STAGE = "Initialization / Agent Setup"
    }
    stages {
        // Stages are run inside your container

        stage('Build MT ISO') {
            steps {
                script { env.FAILED_STAGE = "Build MT ISO" }
                sh "ant -DBASE_ISO_FILE=${params.BASE_ISO_FILE} -DDRIVERS_DIR=${params.DRIVERS_DIR} \
                -DSSMT_DEB_DIR=${params.SSMT_DEB_DIR}"
            }
        }
    }

    post {
//         always {
//             // This runs inside the container as root and
//             // gives ownership back to the jenkins user (usually UID 111 or 1000)
//             sh 'chown -R 111:117 .'
//         }
        success {
            // Grabs the output file from the dist folder
            archiveArtifacts artifacts: 'dist/*.iso', fingerprint: true
//            sendGoogleChatNotificationMT("✅ Build Successful: ${env.JOB_NAME} [${env.BUILD_NUMBER}]")
        }
        failure {
            script {
                sendGoogleChatNotificationMT("❌ Build Failed: *${env.FAILED_STAGE}* ${env.JOB_NAME} [${env.BUILD_NUMBER}]")
            }
        }
    }
}

def sendGoogleChatNotificationMT(String message) {
    def chatWebHook = "https://chat.googleapis.com/v1/spaces/AAAANJvMvsg/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=WI5JUlqOWa9_f4hfXMDgyj0EfxYzgRH91jUZ93dP6xE"
    def payload = """
        {
            "text": "${message}\\nLink: ${env.BUILD_URL}"
        }
    """.stripIndent()
    sh "curl -X POST -H 'Content-Type: application/json' -d '${payload}' '${chatWebHook}'"
}

