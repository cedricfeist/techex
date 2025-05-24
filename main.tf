terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">=3.0.0"

  name = "main-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]


  enable_nat_gateway   = true
  enable_dns_hostnames = true

}


#Security Group main VPC for SSH + MongoDB
resource "aws_security_group" "main_vpc_sg" {
  name        = "main_vpc_sg"
  description = "Security group for EC2 instance"
  vpc_id      = module.vpc.vpc_id

  #Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Allow MongoDB
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  #Allow Egress Traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#Use Public Key
resource "aws_key_pair" "ssh_keypair" {
  key_name   = "cfeist-keypair"              # Replace with your desired key pair name
  public_key = var.publickey # Replace with the path to your public key file
}

#Create Backup S3 Bucket
resource "aws_s3_bucket" "backup_bucket" {
  bucket        = "backupbucket-mongodb"
  force_destroy = true

  tags = {
    Name = "BackupBucket"
  }
}





#Disable Public Access Policies
resource "aws_s3_bucket_public_access_block" "public_bucket_block" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

#Public Read Policy
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket     = aws_s3_bucket.backup_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.public_bucket_block]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backup_bucket.arn}/*"
      }
    ]
  })
}

#IAM Policy to allow Backups from DB EC2 Instance
resource "aws_iam_policy" "backup_policy" {
  name = "s3_backup_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      },
      {
        Action   = "ec2:*",
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

#Role to attach policy for EC2 Backups to S3
resource "aws_iam_role" "ec2_backup_role" {
  name = "ec2_backup_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

#Policy Attachment for Backup role + Policy
resource "aws_iam_role_policy_attachment" "backup_policy_attach" {
  role       = aws_iam_role.ec2_backup_role.name
  policy_arn = aws_iam_policy.backup_policy.arn
}

# Instance Profile for EC2 Instance
resource "aws_iam_instance_profile" "ec2_backup_profile" {
  role = aws_iam_role.ec2_backup_role.name
}


#Database EC2 Instance
resource "aws_instance" "mongodb_instance" {
  ami                         = "ami-03c951bbe993ea087" # Ubuntu 20.04 LTS
  
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.ssh_keypair.key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.main_vpc_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_backup_profile.name

  #MongoDB Config
  user_data = <<-EOF
              #!/bin/bash
              #Prep Mongodb Yum
              sudo touch /etc/yum.repos.d/mongodb-org-8.0.repo
              echo '[mongodb-org-8.0]' | sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo
              echo 'name=MongoDB Repository' | sudo tee -a /etc/yum.repos.d/mongodb-org-8.0.repo
              echo 'baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/8.0/x86_64/' | sudo tee -a /etc/yum.repos.d/mongodb-org-8.0.repo
              echo 'gpgcheck=1' | sudo tee -a /etc/yum.repos.d/mongodb-org-8.0.repo
              echo 'enabled=1' | sudo tee -a /etc/yum.repos.d/mongodb-org-8.0.repo
              echo 'gpgkey=https://pgp.mongodb.com/server-8.0.asc' | sudo tee -a /etc/yum.repos.d/mongodb-org-8.0.repo

              #Install Mongodb
              sudo yum install -y mongodb-mongosh-shared-openssl3
              sudo yum install -y mongodb-org

              #Mongo Reachable from outside
              sudo sed -i 's/bindIp: 127.0.0.1  # Enter 0.0.0.0,::.*/bindIp: 0.0.0.0/' /etc/mongod.conf

              #Start Mongodb
              sudo systemctl start mongod
              sudo systemctl daemon-reload
              sudo systemctl enable mongod
              sudo sleep 15

              #Auth
              sudo mongosh --eval 'db.createUser({user: "admin", pwd: "password", roles:[{role: "root", db: "admin"}]})'
              sudo mongosh --eval 'db.getSiblingDB("app").createUser({user: "demouser", pwd: "demopw", roles:[{role: "readWrite", db: "app"}]})'


              #DB Backup Scruipt
              sudo mkdir db_backups
              sudo touch db_backup_script.sh
              echo '#!/bin/bash' | sudo tee -a db_backup_script.sh
              echo 'DIR=`date +%d-%m-%y`' | sudo tee -a db_backup_script.sh
              echo 'DEST=/db_backups/$DIR' | sudo tee -a db_backup_script.sh
              echo 'mkdir $DEST' | sudo tee -a db_backup_script.sh
              echo 'mongodump -h localhost:27017 -o $DEST' | sudo tee -a db_backup_script.sh
              sudo chmod +x db_backup_script.sh 

              #Backup to S3 Script
              sudo touch s3_sync_script.sh
              echo '#!/bin/bash' | sudo tee /s3_sync_script.sh
              echo 'aws s3 sync /db_backups s3://${aws_s3_bucket.backup_bucket.bucket}' | sudo tee -a s3_sync_script.sh
              sudo chmod +x s3_sync_script.sh

              #Cronjob for Backup Scripts
              sudo yum install -y cronie
              sudo systemctl enable crond
              sudo systemctl start crond 
              sudo touch /etc/crontab   
              echo '30 00 * * * root /db_backup_script.sh' | sudo tee /etc/crontab
              echo '31 00 * * * root /s3_sync_script.sh' | sudo tee -a /etc/crontab
              sudo systemctl restart crond


              EOF
  tags = {
    Name = "mongodb_instance"

  }
}

/*

resource "aws_security_group" "k8s_access_sg" {
  vpc_id = module.vpc.vpc_id
  name   = "K8s_access_sg"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#EKS Cluster for Application
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = "tasky_eks_cluster"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Optional
  cluster_endpoint_public_access = true
  #cluster_additional_security_group_ids    = ["${aws_security_group.k8s_access_sg.id}"]
  enable_cluster_creator_admin_permissions = true

  authentication_mode = "API_AND_CONFIG_MAP"

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  #enable_cluster_creator_admin_permissions = true

  #cluster_compute_config = {
  #  enabled                       = true
  #  node_pools                    = ["general-purpose"]
  #additional_security_group_ids = ["${aws_security_group.k8s_access_sg.id}"]
  #}

  eks_managed_node_group_defaults = {
    instance_types = ["m5a.large"]
  }

  eks_managed_node_groups = {
    tasky_nodes = {
      instance_types = ["m5a.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  tags = {
    Name = "Tasky_EKS_Cluster"
  }
}



#Application Deployment


# Kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", "tasky_eks_cluster"]
    command     = "aws"
  }
}

# Create Kubernetes Namespace
resource "kubernetes_namespace" "tasky_namespace" {
  metadata {
    name = "tasky"
  }
}

resource "kubernetes_service_account" "admin_service_account" {
  metadata {
    name      = "admin-service-account"
    namespace = kubernetes_namespace.tasky_namespace.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "admin_sa_binding" {
  metadata {
    name = "admin-sa-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.admin_service_account.metadata[0].name
    namespace = kubernetes_namespace.tasky_namespace.metadata[0].name
  }
}

#docker buildx build --platform linux/amd64 -t cedricfe/tasky:latest --push .

#Create Deployment for App
resource "kubernetes_deployment" "tasky_deployment" {
  depends_on = [module.eks]
  metadata {
    name      = "tasky"
    namespace = kubernetes_namespace.tasky_namespace.metadata[0].name
    labels = {
      app = "tasky"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "tasky"
      }
    }
    template {
      metadata {
        labels = {
          app = "tasky"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.admin_service_account.metadata[0].name
        container {
          name  = "tasky"
          image = "cedricfe/taskyapp:main"

          port {
            container_port = 8080
          }

          env {
            name  = "MONGODB_URI"
            value = "mongodb://admin:password@${aws_instance.mongodb_instance.private_ip}:27017/app?authSource=test"
          }

          env {
            name  = "SECRET_KEY"
            value = "secret123"
          }
        }
      }
    }
  }
}


#Service to expose the app
resource "kubernetes_service" "tasky_svc" {
  depends_on = [module.eks]
  metadata {
    name      = "tasky-service"
    namespace = kubernetes_namespace.tasky_namespace.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-subnets"         = "${module.vpc.public_subnets[0]}, ${module.vpc.public_subnets[1]},${module.vpc.public_subnets[2]}"
      "service.beta.kubernetes.io/aws-load-balancer-security-groups" = aws_security_group.k8s_access_sg.id
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      #"service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
    }
  }
  spec {
    selector = {
      app = "tasky"
    }
    port {
      port        = 80
      target_port = 8080
    }
    load_balancer_ip = null
    type             = "LoadBalancer"
  }
}

*/