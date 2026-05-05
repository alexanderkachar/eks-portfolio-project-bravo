locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-app-alb-sg"
  description = "Internet traffic to the Express app ALB."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all egress."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-app-alb-sg"
  }
}

resource "aws_security_group_rule" "alb_to_cluster" {
  type                     = "ingress"
  description              = "App ALB to Kubernetes pod targets."
  from_port                = var.target_port
  to_port                  = var.target_port
  protocol                 = "tcp"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.this.id
}

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-app-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.this.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${local.name_prefix}-app-alb"
  }
}

resource "aws_lb_target_group" "this" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher             = "200-399"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_route53_record" "app" {
  zone_id         = var.hosted_zone_id
  name            = var.app_hostname
  type            = "CNAME"
  ttl             = 60
  records         = [aws_lb.this.dns_name]
  allow_overwrite = true
}
