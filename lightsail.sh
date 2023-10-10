sudo su
apt update
snap install docker

cd /home/ubuntu
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install unzip -y
unzip awscliv2.zip
./aws/install
sleep 300
rm -rf awscliv2.zip

#with only ECR pull access. TODO: update
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION="eu-central-1"

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY

docker login -u AWS -p $(aws ecr get-login-password --region eu-central-1) 047870419389.dkr.ecr.eu-central-1.amazonaws.com
docker pull 047870419389.dkr.ecr.eu-central-1.amazonaws.com/lightsail:latest
docker images >> test.txt #for testing
docker run -d -p 80:3000 047870419389.dkr.ecr.eu-central-1.amazonaws.com/lightsail:latest
