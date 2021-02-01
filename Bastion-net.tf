# Configure the AWS Provider
provider "aws" {
  region     = "eu-west-2"
  access_key = ""
  secret_key = ""
}

##########################################################
########### Variables for later reference ################
##########################################################
# key variable for refrencing 
variable "key_name" {
  default = "mangoes" # if we keep default blank it will ask for a value when we execute terraform apply
}

# the path to our project root:
variable "base_path" {
  default = "~/Darktrace_bastion/" #the path to our project root.
}



##########################################################
##############      VPC       ############################
##########################################################

# Create a VPC
resource "aws_vpc" "vpc1" {
  cidr_block = "10.10.0.0/16"
  #instance_tenancy = "default"
  enable_dns_hostnames = true #so instance will have a host name not just the ip
  tags = {
    Name = "private dark-vpc-1"
  }
}

#Private subnet:
resource "aws_subnet" "private_subnet" {
  depends_on              = [aws_vpc.vpc1]
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false #this is default value
}

##########################################################
########  Keys for ssh provisioning ######################
##########################################################

# this will create a key with RSA algorithm with 4096 rsa bits
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096 #default set to 2048
}

# this resource will create a key pair using above private key
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.private_key.public_key_openssh

   depends_on = [tls_private_key.private_key]
}

# this resource will save the private key at our specified path.
resource "local_file" "saveKey" {
  content = tls_private_key.private_key.private_key_pem
  filename = "${var.base_path}${var.key_name}.pem"
  
}


##########################################################
################ Gateway #################################
##########################################################

# Create a Gateway for the vpc
resource "aws_internet_gateway" "gateway1" {
  depends_on = [aws_vpc.vpc1]
  vpc_id     = aws_vpc.vpc1.id
}

##########################################################
################ Route Table #################################
##########################################################

# route table with internet gateway as target:
resource "aws_route_table" "igw_route_table" {
  depends_on = [aws_vpc.vpc1, aws_internet_gateway.gateway1]
  vpc_id     = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    #egress_only_gateway_id = "value"
    gateway_id = aws_internet_gateway.gateway1.id
    #instance_id = "value"
    #ipv6_cidr_block = "value"
    #local_gateway_id = "value"
    #nat_gateway_id = "value"
    #network_interface_id = "value"
    #transit_gateway_id = "value"
    #vpc_endpoint_id = "value"
    #vpc_peering_connection_id = "value"
  }
}

# route table association Gateway-Public:
resource "aws_route_table_association" "public_route" {
  depends_on     = [aws_subnet.public_subnet, aws_route_table.igw_route_table]
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.igw_route_table.id
}


# route table with NAT as a target:
resource "aws_route_table" "NAT_route_table" {
  depends_on = [aws_vpc.vpc1, aws_nat_gateway.nat_gateway]
  vpc_id     = aws_vpc.vpc1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

#route table association NAT-Private:
resource "aws_route_table_association" "private_route" {
  depends_on     = [ aws_subnet.private_subnet, aws_route_table.NAT_route_table]
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.NAT_route_table.id
}



##########################################################
############ Elastic IP and NAT Gateway ##################
##########################################################

#elastic ip:
resource "aws_eip" "elastic_ip" {
  vpc = true #find out the meaning of it
}

#to print out the public ip of bastion:
# output "eip_ip" {
#   value = aws_eip.elastic_ip.public_ip
# }

#NAT gateway:
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnet] #aws_eip.elastic_ip
  allocation_id = aws_subnet.public_subnet.id
  subnet_id     = aws_subnet.public_subnet.id
}



##########################################################
################ Bastion #################################
##########################################################

#subnet:
resource "aws_subnet" "public_subnet" {
  depends_on              = [aws_vpc.vpc1]
  vpc_id                  = aws_vpc.vpc1.id
  cidr_block              = "10.10.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-2b"
}


#instance:
resource "aws_instance" "bastion" {
  depends_on                  = [aws_security_group.bastion_sec_group]
  ami                         = "ami-098828924dc89ea4a" #linux2 machine
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sec_group.id]
  subnet_id                   = aws_subnet.public_subnet.id


  
  provisioner "file" {
    source      = "~/Darktrace/mangoes.pem" #if we ssh into the bastion from this vm; else use the location to the local pem file.
    destination = "~/Darktrace_bastion/mangoes.pem"
  }
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host        = self.public_ip
  }

}

output "bastion-ip" {
  value = aws_instance.bastion.public_ip
}

#security group:
resource "aws_security_group" "bastion_sec_group" {
  name   = "bastion_sec_gp"
  vpc_id = aws_vpc.vpc1.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"] #else associate a whitelist
    #description = "value"
    from_port = 22
    #ipv6_cidr_blocks = [ "value" ]
    #prefix_list_ids = [ "value" ]
    protocol = "tcp"
    #security_groups = [ "value" ]
    #self = false
    to_port = 22
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    #description = "value"
    from_port = 0
    #ipv6_cidr_blocks = [ "value" ]
    #prefix_list_ids = [ "value" ]
    protocol = -1
    #security_groups = [ "value" ]
    #self = false
    to_port = 0
  }
}

#########################################################
############# Public subnet app #########################
#########################################################


resource "aws_security_group" "wordpress_sec_group" {
  depends_on = [aws_vpc.vpc1]

  name        = "sg_wordpress"
  description = "Allow http inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "allow TCP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "allow SSH"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sec_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# wordpress ec2 instance
resource "aws_instance" "wordpress" {
  depends_on             = [aws_security_group.wordpress_sec_group, aws_instance.mysql]
  ami                    = "ami-098828924dc89ea4a"
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.wordpress_sec_group.id]
  subnet_id              = aws_subnet.public_subnet.id
  user_data              = <<EOF
            #! /bin/bash
            apt update
            apt install docker -y
            systemctl restart docker
            systemctl enable docker
            docker pull wordpress
            docker run --name wordpress -p 80:80 -e WORDPRESS_DB_HOST=${aws_instance.mysql.private_ip} \
            -e WORDPRESS_DB_USER=root -e WORDPRESS_DB_PASSWORD=root -e WORDPRESS_DB_NAME=wordpressdb -d wordpress
  EOF
  # the instance containing the sql db is later defined.
  tags = {
    Name = "wordpress"
  }
}


#########################################################
############# Private subnet ############################
#########################################################


# #Private subnet:
# resource "aws_subnet" "private_subnet" {
#   depends_on              = [aws_vpc.vpc1]
#   vpc_id                  = aws_vpc.vpc1.id
#   cidr_block              = "10.10.1.0/24"
#   availability_zone       = "eu-west-2a"
#   map_public_ip_on_launch = false #this is default value
# }


#mysql security group
resource "aws_security_group" "mysql_sec_group" {
  depends_on  = [aws_vpc.vpc1]
  name        = "sg mysql"
  description = "Allow mysql inbound traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description     = "allow TCP"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sec_group.id]
  }

  ingress {
    description     = "allow SSH"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sec_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# mysql ec2 instance
resource "aws_instance" "mysql" {
  depends_on             = [aws_security_group.mysql_sec_group, aws_nat_gateway.nat_gateway, aws_route_table_association.private_route]
  ami                    = "ami-098828924dc89ea4a"
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.mysql_sec_group.id]
  subnet_id              = aws_subnet.private_subnet.id
  user_data              = file("~/Darktrace/configure_mysql.sh")
  tags = {
    Name = "mysql-instance"
  }
}

