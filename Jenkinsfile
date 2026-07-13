pipeline {
    agent { label '0.240' }

    options {
        // Abort the entire pipeline if any stage fails
        timestamps()
        ansiColor('xterm')
    }

    stages {

        stage('01 - Let\'s Encrypt Certificate Renewal') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/01-letsencrypt-renewal.sh --force
                '''
            }
        }

        stage('02 - Copy Certificate to Hosts') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/02-copy-cert.sh
                '''
            }
        }

        stage('03 - Restart HAProxy') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/03-restart-haproxy.sh
                '''
            }
        }

    }

    post {
        success {
            echo 'All stages completed successfully. Certificate renewed and HAProxy restarted.'
        }
        failure {
            echo 'Pipeline failed. Check the logs above.'
        }
    }
}
