echo "executing user data"
sudo su
apt update
apt install docker.io -y

cd /home/ubuntu
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install unzip -y
unzip awscliv2.zip
./aws/install
sleep 300
rm -rf awscliv2.zip

#with only ECR pull access. TODO: update
AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY/>
AWS_SECRET_ACCESS_KEY=<AWS_SECRET_KEY/>
AWS_REGION="eu-central-1"

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY

docker login -u AWS -p $(aws ecr get-login-password --region eu-central-1) 250373516626.dkr.ecr.eu-central-1.amazonaws.com
docker pull 250373516626.dkr.ecr.eu-central-1.amazonaws.com/lightsailinstance:latest
#docker run -d -p 3000:3000 grafana/grafana
docker run -d -p 80:3000 250373516626.dkr.ecr.eu-central-1.amazonaws.com/lightsailinstance:latest
docker images >> test.txt
echo "user data executed"
