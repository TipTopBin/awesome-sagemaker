#!/bin/bash

# set -e

download_and_verify () {
  url=$1
  checksum=$2
  out_file=$3

  curl --location --show-error --silent --output $out_file $url

  echo "$checksum $out_file" > "$out_file.sha256"
  sha256sum --check "$out_file.sha256"
  
  rm "$out_file.sha256"
}


cd /tmp/

echo "==============================================="
echo "  Config envs ......"
echo "==============================================="
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bashrc
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bashrc
aws configure set default.region ${AWS_REGION}
aws configure get default.region
aws configure set region $AWS_REGION
export EKS_VPC_ID=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
export EKS_PUB_SUBNET_01=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${EKS_VPC_ID}" "Name=availability-zone, Values=${AWS_REGION}a" --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text)
export EKS_PRI_SUBNET_01=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${EKS_VPC_ID}" "Name=availability-zone, Values=${AWS_REGION}a" --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
# Additional security groups
export EKS_EXTRA_SG=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME} | jq -r '.cluster.resourcesVpcConfig.securityGroupIds[0]')
# Cluster security group
export EKS_CLUSTER_SG=$(aws eks describe-cluster --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME} | jq -r '.cluster.resourcesVpcConfig.clusterSecurityGroupId')
echo "export EKS_VPC_ID=\"$EKS_VPC_ID\"" >> ~/.bashrc
echo "export EKS_PUB_SUBNET_01=\"$EKS_PUB_SUBNET_01\"" >> ~/.bashrc
echo "export EKS_PRI_SUBNET_01=\"$EKS_PRI_SUBNET_01\"" >> ~/.bashrc
echo "export EKS_EXTRA_SG=${EKS_EXTRA_SG}" | tee -a ~/.bashrc
echo "export EKS_CLUSTER_SG=${EKS_CLUSTER_SG}" | tee -a ~/.bashrc
source ~/.bashrc
aws sts get-caller-identity


echo "==============================================="
echo "  Upgrade awscli to v2 ......"
echo "==============================================="
rm -fr awscliv2.zip aws
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
which aws_completer
echo $SHELL
cat >> ~/.bashrc <<EOF
complete -C '/usr/local/bin/aws_completer' aws
EOF
source ~/.bashrc
aws --version


echo "==============================================="
echo "  Install App2Container ......"
echo "==============================================="
#https://docs.aws.amazon.com/app2container/latest/UserGuide/start-step1-install.html
#https://aws.amazon.com/blogs/containers/modernize-java-and-net-applications-remotely-using-aws-app2container/
curl -o /tmp/AWSApp2Container-installer-linux.tar.gz https://app2container-release-us-east-1.s3.us-east-1.amazonaws.com/latest/linux/AWSApp2Container-installer-linux.tar.gz
sudo tar xvf /tmp/AWSApp2Container-installer-linux.tar.gz -C /tmp
# sudo ./install.sh
echo y |sudo /tmp/install.sh
sudo app2container --version
cat >> ~/.bashrc <<EOF
alias a2c="sudo app2container"
EOF
source ~/.bashrc
a2c help
curl -o /tmp/optimizeImage.zip https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/samples/p-attach/dc756bff-1fcd-4fd2-8c4f-dc494b5007b9/attachments/attachment.zip
sudo unzip /tmp/optimizeImage.zip -d /tmp/optimizeImage
sudo chmod 755 /tmp/optimizeImage/optimizeImage.sh
sudo mv /tmp/optimizeImage/optimizeImage.sh /usr/local/bin/optimizeImage.sh
optimizeImage.sh -h


echo "==============================================="
echo "  Install eksctl ......"
echo "==============================================="
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
# 配置自动完成
cat >> ~/.bashrc <<EOF
. <(eksctl completion bash)
alias e=eksctl
complete -F __start_eksctl e
EOF


echo "==============================================="
echo "  Install kubectl ......"
echo "==============================================="
# 安装 kubectl 并配置自动完成
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
cat >> ~/.bashrc <<EOF
source <(kubectl completion bash)
alias k=kubectl
complete -F __start_kubectl k
EOF
source ~/.bashrc
kubectl version --client
# Enable some kubernetes aliases
echo "alias kgn='kubectl get nodes -L beta.kubernetes.io/arch -L eks.amazonaws.com/capacityType -L node.kubernetes.io/instance-type -L eks.amazonaws.com/nodegroup -L topology.kubernetes.io/zone'" | tee -a ~/.bashrc
echo "alias kk='kubectl get nodes -L beta.kubernetes.io/arch -L eks.amazonaws.com/capacityType -L karpenter.sh/capacity-type -L node.kubernetes.io/instance-type -L topology.kubernetes.io/zone -L karpenter.sh/provisioner-name'" | tee -a ~/.bashrc
echo "alias kgp='kubectl get po -o wide'" | tee -a ~/.bashrc
echo "alias kgd='kubectl get deployment -o wide'" | tee -a ~/.bashrc
echo "alias kgs='kubectl get svc -o wide'" | tee -a ~/.bashrc
echo "alias kdn='kubectl describe node'" | tee -a ~/.bashrc
echo "alias kdp='kubectl describe po'" | tee -a ~/.bashrc
echo "alias kdd='kubectl describe deployment'" | tee -a ~/.bashrc
echo "alias kds='kubectl describe svc'" | tee -a ~/.bashrc
echo 'export dry="--dry-run=client -o yaml"' | tee -a ~/.bashrc
echo "alias ka='kubectl apply -f'" | tee -a ~/.bashrc
echo "alias kr='kubectl run $dry'" | tee -a ~/.bashrc
echo "alias ke='kubectl explain'" | tee -a ~/.bashrc
echo "alias tk='kt -n karpenter deploy/karpenter'" | tee -a ~/.bashrc
echo "alias pk='k patch configmap config-logging -n karpenter --patch'" | tee -a ~/.bashrc
# k patch configmap config-logging -n karpenter --patch 
# pk '{"data":{"loglevel.controller":"info"}}'


echo "==============================================="
echo "  Install helm ......"
echo "==============================================="
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
helm repo add stable https://charts.helm.sh/stable


echo "==============================================="
echo "  Install k9s a Kubernetes CLI To Manage Your Clusters In Style ......"
echo "==============================================="
curl -sS https://webinstall.dev/k9s | bash


echo "==============================================="
echo "  Install kubetail ......"
echo "==============================================="
curl -o /tmp/kubetail https://raw.githubusercontent.com/johanhaleby/kubetail/master/kubetail
chmod +x /tmp/kubetail
sudo mv /tmp/kubetail /usr/local/bin/kubetail
cat >> ~/.bashrc <<EOF
alias kt=kubetail
EOF
source ~/.bashrc


echo "==============================================="
echo "  EKS Node Logs Collector (Linux) ......"
echo "==============================================="
# run this script on your eks node
sudo curl -o /usr/local/bin/enic https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/log-collector-script/linux/eks-log-collector.sh
sudo chmod +x /usr/local/bin/enic
enic help


echo "==============================================="
echo "  EKS Pod Information Collector ......"
echo "==============================================="
# https://github.com/awslabs/amazon-eks-ami/tree/master/log-collector-script/linux
sudo curl -o /usr/local/bin/epic https://raw.githubusercontent.com/aws-samples/eks-pod-information-collector/main/eks-pod-information-collector.sh
sudo chmod +x /usr/local/bin/epic
# epic -p <Pod_Name> -n <Pod_Namespace>
# epic --podname <Pod_Name> --namespace <Pod_Namespace>


echo "==============================================="
echo "  Install c9 to open files in cloud9 ......"
echo "==============================================="
npm install -g c9


echo "==============================================="
echo "  Install jq, envsubst (from GNU gettext utilities) and bash-completion ......"
echo "==============================================="
# moreutils: The command sponge allows us to read and write to the same file (cat a.txt|sponge a.txt)
sudo yum -y install jq gettext bash-completion moreutils tree zsh


echo "==============================================="
echo "  Install yq for yaml processing ......"
echo "==============================================="
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    sudo chmod +x /usr/bin/yq


echo "==============================================="
echo "  Install Java ......"
echo "==============================================="
sudo yum -y install java-11-amazon-corretto
#sudo alternatives --config java
#sudo update-alternatives --config javac
java -version
javac -version


echo "==============================================="
echo "  Expand disk space ......"
echo "==============================================="
wget https://raw.githubusercontent.com/DATACNTOP/streaming-analytics/main/utils/scripts/resize-ebs.sh -O /tmp/resize-ebs.sh
chmod +x /tmp/resize-ebs.sh
/tmp/resize-ebs.sh 100


echo "==============================================="
echo "  More Aliases ......"
echo "==============================================="
cat >> ~/.bashrc <<EOF
alias c=clear
EOF


# 最后再执行一次 source
echo "source ~/.bashrc"
shopt -s expand_aliases
source ~/.bashrc
