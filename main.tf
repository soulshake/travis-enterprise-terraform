variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-east-1"
}

# Travis Enterprise Worker AMIs
# using Ubuntu Trusty 14.04 LTS (x64)
variable "aws_amis" {
  default = {
    "us-east-1" = "ami-759bc50a"
  }
}

variable "aws_key_name" {
  description = "The AWS SSH name for sshing into the workers."
}

variable "worker_count" {
  description = "The number of Worker instances to start."
  default     = 1
}

variable "enterprise_host_name" {
  description = "The fully qualified hostname of the Travis Enterprise Platform."
}

variable "rabbitmq_password" {
  description = "The password of the Enterprise Platform RabbitMQ."
}

# Specify the provider and access details
provider "aws" {
  version = "~> 1.4"
  region  = "${var.aws_region}"
}

# Our default security group to access the worker instances over SSH
resource "aws_security_group" "travis-enterprise-workers" {
  name        = "aj-cyan-travis-enterprise-workers"
  description = "AJ Cyan Travis Enterprise Workers"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "travis-enterprise-platform" {
  name        = "aj-cyan-travis-enterprise-platform"
  description = "AJ Cyan Travis Enterprise Platform"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # web access from anywhere
  ingress {
    from_port   = 8800
    to_port     = 8800
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 5672	Custom TCP Rule	For RabbitMQ Non-SSL.
  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 4567	Custom TCP Rule	For RabbitMQ SSL.
  ingress {
    from_port   = 4567
    to_port     = 4567
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 443	HTTPS	Web application over HTTPS access.
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 80	HTTP	Web application access.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "platform" {
  instance = "${aws_instance.platform.id}"
}

resource "aws_instance" "platform" {
  # instance_type   = "c4.2xlarge"
  instance_type           = "c3.xlarge"
  disable_api_termination = false
  ami                     = "${lookup(var.aws_amis, var.aws_region)}"
  security_groups         = ["${aws_security_group.travis-enterprise-platform.name}"]
  key_name                = "${var.aws_key_name}"
  count                   = 1

  #public_dns      = "cyan.soulshake.net"

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }
  tags {
    Name = "aj-cyan-travis-enterprise-platform"
  }
  user_data = <<USER_DATA
#!/bin/bash
TRAVIS_ENTERPRISE_HOST="${var.enterprise_host_name}"
TRAVIS_ENTERPRISE_SECURITY_TOKEN="${var.rabbitmq_password}"
curl -L -o /tmp/installer.sh https://enterprise.travis-ci.com/install
sudo bash /tmp/installer.sh
USER_DATA
}

resource "aws_instance" "workers" {
  instance_type   = "c3.xlarge"
  ami             = "${lookup(var.aws_amis, var.aws_region)}"
  security_groups = ["${aws_security_group.travis-enterprise-workers.name}"]
  key_name        = "${var.aws_key_name}"
  count           = "${var.worker_count}"

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = "50"
  }

  tags {
    Name = "aj-cyan-travis-enterprise-worker"
  }

  user_data = <<USER_DATA
#!/bin/bash
TRAVIS_ENTERPRISE_HOST="${var.enterprise_host_name}"
TRAVIS_ENTERPRISE_SECURITY_TOKEN="${var.rabbitmq_password}"
sed -i "s/\# export TRAVIS_ENTERPRISE_HOST=\"enterprise.yourhostname.corp\"/export TRAVIS_ENTERPRISE_HOST=\"$TRAVIS_ENTERPRISE_HOST\"/" /etc/default/travis-enterprise
sed -i "s/\# export TRAVIS_ENTERPRISE_SECURITY_TOKEN=\"abcd1234\"/export TRAVIS_ENTERPRISE_SECURITY_TOKEN=\"$TRAVIS_ENTERPRISE_SECURITY_TOKEN\"/" /etc/default/travis-enterprise

echo "export TRAVIS_WORKER_BUILD_API_INSECURE_SKIP_VERIFY='false'" >> /etc/default/travis-enterprise
echo "export TRAVIS_WORKER_DOCKER_BINDS='/var/run/docker/sock:/var/run/docker.sock'" >> /etc/default/travis-enterprise

echo '${file("${license.rli}")}' >> /etc/default/license.rli

curl -L -o /tmp/installer.sh https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/installer.sh

sudo bash /tmp/installer.sh \
--travis_enterprise_host="${var.enterprise_host_name}" \
--travis_enterprise_security_token="${var.rabbitmq_password}"
USER_DATA
}
