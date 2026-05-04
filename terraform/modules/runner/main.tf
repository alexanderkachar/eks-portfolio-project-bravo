locals {
  name = "${var.project_name}-${var.environment}-runner"

  pat_ssm_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.pat_ssm_parameter_name}"

  register_script = templatefile("${path.module}/runner-register.sh.tpl", {
    pat_ssm_parameter_name = var.pat_ssm_parameter_name
    github_owner           = var.github_owner
    github_repo            = var.github_repo
    runner_name            = local.name
    runner_labels          = var.runner_labels
  })

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    runner_version             = var.runner_version
    runner_register_script_b64 = base64encode(local.register_script)
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "runner" {
  statement {
    sid       = "ECRGetAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPushToProjectRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "EKSDescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [var.cluster_arn]
  }

  statement {
    sid = "SSMReadGitHubPAT"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [local.pat_ssm_arn]
  }

}

resource "aws_iam_role_policy" "runner" {
  name   = "runner-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.runner.json
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name
}

resource "aws_security_group" "this" {
  name        = "${local.name}-sg"
  description = "GitHub Actions runner: no inbound; HTTPS egress only."
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to VPC for interface endpoints (ECR, STS, SSM)."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to internet via NAT for github.com, ghcr.io, public image base layers."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_runner" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "GitHub Actions runner to private EKS API."

  tags = { Name = "${local.name}-to-cluster-api" }
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.runner_subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = { Name = local.name }
}

resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.this.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.runner]
}
