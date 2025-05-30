data "aws_autoscaling_groups" "eb_asg" {
  filter {
    name   = "tag:elasticbeanstalk:environment-name"
    values = [aws_elastic_beanstalk_environment.env.name]
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "eb-scale-out"
  autoscaling_group_name = data.aws_autoscaling_groups.eb_asg.names[0]
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 0

  step_adjustment {
    metric_interval_lower_bound = 0
    scaling_adjustment          = 3
  }
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "eb-scale-in"
  autoscaling_group_name = data.aws_autoscaling_groups.eb_asg.names[0]
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 0

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -3
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "eb-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 70

  alarm_description   = "Scale out if CPU > 70%"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = data.aws_autoscaling_groups.eb_asg.names[0]
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "eb-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Maximum"
  threshold           = 5

  alarm_description   = "Scale in if CPU < 5%"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = data.aws_autoscaling_groups.eb_asg.names[0]
  }
}