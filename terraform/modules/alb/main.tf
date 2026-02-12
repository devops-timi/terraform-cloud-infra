# ALB
resource "aws_lb" "this" {
  name               = "app-alb"
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]
}

# Target Group
resource "aws_lb_target_group" "this" {
  name     = "app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

# Attach EC2 instances
resource "aws_lb_target_group_attachment" "this" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.instance_ids[count.index]
  port             = 80
}

# Listener
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

