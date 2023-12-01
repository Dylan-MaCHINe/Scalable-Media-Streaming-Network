#establish our provider
provider "aws" {
  region                   = "us-east-1"
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = "default"
}

#create our vpc
resource "aws_vpc" "main-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "main-vpc"
  }
}

#create our internet gateway to give our resources a way to the internet
resource "aws_internet_gateway" "main-igw" {
  vpc_id = "aws_vpc.main-vpc.id"
}

#create our subnets
resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = "aws_vpc.main-vpc.id"
  availability_zone       = "us-east-1a"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true #ensures we get a public IP on launch 
}
resource "aws_subnet" "public-subnet-2" {
  vpc_id                  = "aws_vpc.main-vpc.id"
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

#create our application load balancer (alb)
resource "aws_lb" "app-lb" {
  name                       = "app-lb"
  load_balancer_type         = "application"
  internal                   = false                                                         #means our alb will be used on our external/public subnet instead of our private/internal subnet
  subnets                    = ["aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2"] #distribute traffic equally between these subnets
  security_groups            = ["aws_security_group.alb-sg.id"]
  enable_deletion_protection = false #this option means our alb is not protected if it gets accidentally deleted
}

#not part of the project but this is what our alb would look like if we set it to be used in our internal network:
#resource "aws_lb" "internal_app_lb" {
# name               = "internal-app-lb"   we name our alb internal since it will be used internally in our private subnet
# internal           = true  # This specifies that the load balancer is internal.
# load_balancer_type = "application"
# subnets            = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
# security_groups    = [aws_security_group.internal_alb_sg.id]
#}

#next we create our security group for our alb, which is what will allow HTTP traffic to enter our application load balancer
resource "aws_security_group" "alb-sg" {
  name        = "alb-sg"
  description = "allows HTTP traffic to alb"
  vpc_id      = "aws_vpc.main-vpc.id"
  ingress {
    to_port     = 80
    from_port   = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#next we'll create our alb target group and configure it to only receive HTTP traffic
#alb and target group go together so that the alb knows who to route traffic to (so whoever is in the target group gets the traffic)
#our alb will have another resource created with it called a listener and it will have a set of rules that will evaluate traffic like an ACL 
#purpose of the target group is to set up the targets that the alb will route traffic to
resource "aws_lb_target_group" "app-tg" {
  name     = "app-tg"
  protocol = "HTTP"
  port     = 80
  vpc_id   = aws_vpc.main-vpc.id
}

#next we create our alb listener which we'll set to only listen for HTTP traffic and forward it to our target group on a specified port
#An ALB listener is a process that checks for connection requests using the protocol and port that you configure. When a listener hears a 
#request, it forwards the request to a target group based on the rules you have defined.
resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.app-lb.arn #the load_balancer_arn will be the load balancer resource we created
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"                      #this default action means that our alb_listener will forward traffic to our target groups
    target_group_arn = aws_lb_target_group.app-tg.arn #same thing as our load_balancer_arn, except we're using the target group resource
  }
}

#now we'll create our EC2 instance which will allow content browsing and account management
resource "aws_instance" "app-server" {
  count                       = 2 #the count attribute tells terraform to create 2 identical EC2 instances
  ami                         = "ami-0fc5d935ebf8bc3bc"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public-subnet-1.id
  security_groups             = [aws_security_group.alb-sg.id]
  associate_public_ip_address = true
}

#next we'll create our S3 bucket which will contain our static uploads
resource "aws_s3_bucket" "static-content" {
  bucket = "my-static-content-bucket"
  acl    = "private"
  tags = {
    Name = "StaticContentBucket"
  }
}

#then we'll create an output variable for our DNS resolution which is essentially like the return statement used in coding
output "alb_dns_name" {
  value = aws_lb.app_lb.dns_name #This provides the DNS name of the alb, which is used to access the load balancer over the network
}                                #in our network, the load balancer is it's own thing on the internet which is why it gets its own DNS name and can be accessed over the internet

output "s3_bucket_name" {
  value = aws_s3_bucket.static_content.bucket #this just returns the name of our S3 bucket
}
